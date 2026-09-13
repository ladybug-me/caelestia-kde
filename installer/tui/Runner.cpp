#include "Runner.hpp"
#include "Draw.hpp"
#include "Globals.hpp"
#include "Input.hpp"
#include "Term.hpp"
#include "UI.hpp"
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

using namespace std;

// Signal flags defined in main.cpp (global scope, not in any namespace).
extern volatile sig_atomic_t g_sigint_received;
extern volatile sig_atomic_t g_sigterm_received;

namespace {
// Spinner frame for the running step, advanced on each poll timeout.
static size_t g_spin_frame = 0;

std::string env_val(const char* name) {
  const char* v = getenv(name);
  return v ? std::string(v) : std::string();
}

bool env_is_true(const char* name) { return env_val(name) == "true"; }

// The log bytes appended since start_offset, so a step's own output can be scanned
// for warning markers.
bool log_tail_since(const std::string& log_path, long start_offset,
                    std::string& out) {
  FILE* f = fopen(log_path.c_str(), "rb");
  if (!f)
    return false;
  fseek(f, 0, SEEK_END);
  long end = ftell(f);
  if (end <= start_offset) {
    fclose(f);
    return false;
  }
  fseek(f, start_offset, SEEK_SET);
  size_t n = static_cast<size_t>(end - start_offset);
  std::string buf(n, '\0');
  size_t got = fread(&buf[0], 1, n, f);
  fclose(f);
  buf.resize(got);
  out = std::move(buf);
  return true;
}

// Forks a bash step with stdout/stderr appended to the shared install log, keeping the
// terminal for the TUI.
pid_t spawn_step(const string& script_path, int log_fd) {
  pid_t child = fork();
  if (child < 0)
    return -1;

  if (child == 0) {
    if (log_fd >= 0) {
      dup2(log_fd, STDOUT_FILENO);
      dup2(log_fd, STDERR_FILENO);
    }
    // stdbuf line-buffers the redirected stdout/stderr, so each line reaches the file
    // (and the live view) as printed rather than in a 4 KiB stdio buffer at step end.
    execlp("stdbuf", "stdbuf", "-oL", "-eL", "bash", script_path.c_str(),
           static_cast<char*>(nullptr));
    // Fall back to plain bash if stdbuf is unavailable (e.g. minimal image).
    execlp("bash", "bash", script_path.c_str(), static_cast<char*>(nullptr));
    _exit(127);
  }
  return child;
}
// The menu answers are authoritative; they reach the environment only after the review
// screen, so that screen must read them directly.
bool answer_is_true(const char* name) {
  auto it = g_answers.find(name);
  if (it != g_answers.end())
    return it->second == "true";
  return env_is_true(name);
}

// The last `max_lines` lines of the log, ANSI stripped. The log is large and appended
// live, so only a fixed tail is read.
bool read_log_tail(const std::string& log_path, size_t max_lines,
                   std::vector<std::string>& out) {
  out.clear();
  std::ifstream in(log_path, std::ios::binary);
  if (!in)
    return false;
  in.seekg(0, std::ios::end);
  std::streamoff len = in.tellg();
  const std::streamoff kMax = 512 * 1024;
  if (len > kMax)
    in.seekg(len - kMax, std::ios::beg);
  else
    in.seekg(0, std::ios::beg);
  std::string content((std::istreambuf_iterator<char>(in)),
                      std::istreambuf_iterator<char>());
  std::vector<std::string> lines;
  std::string line;
  for (char ch : content) {
    if (ch == '\n') {
      lines.push_back(Draw::strip_ansi(line));
      line.clear();
    } else {
      line += ch;
    }
  }
  if (!line.empty())
    lines.push_back(Draw::strip_ansi(line));
  size_t start = lines.size() > max_lines ? lines.size() - max_lines : 0;
  for (size_t i = start; i < lines.size(); ++i)
    out.push_back(lines[i]);
  return true;
}

// Animated status glyph for the currently running step.
string spin_glyph() {
  static const char* frames[] = {"[/]", "[-]", "[\\]", "[|]"};
  return frames[g_spin_frame % 4];
}
} // namespace

namespace Runner {
const vector<Phase> phases = {
    {"prepare", "Prepare"},   {"packages", "Packages"},
    {"configure", "Configure"}, {"build", "Build"},
    {"finalize", "Finalize"},
};

// The backup step runs inside Prepare, so the phase story reads true: snapshot, then
// install.
vector<Step> steps = {
    {"Refresh mirrors", "scripts/00-refresh-mirrors.sh", "PENDING", "prepare"},
    {"Update system", "scripts/00a-system-update.sh", "PENDING", "prepare"},
    {"Ensure prerequisites", "scripts/01-ensure-prereqs.sh", "PENDING",
     "prepare"},
    {"Update submodules", "scripts/02a-submodules.sh", "PENDING", "prepare"},
    {"Back up current setup", "scripts/00-backup-themes.sh", "PENDING",
     "prepare"},
    {"Install packages", "scripts/02-all-packages.sh", "PENDING",
     "packages"},
    {"Install lock screen greeter", "scripts/02-packages.sh", "PENDING",
     "packages"},
    {"Deploy config files", "scripts/03-deploy-configs.sh", "PENDING",
     "configure"},
    {"Download wallpapers", "scripts/03a-wallpapers.sh", "PENDING",
     "configure"},
    {"Apply KDE theme", "scripts/04-deploy-kde.sh", "PENDING", "configure"},
    {"Install SDDM theme", "scripts/05-sddm-theme.sh", "PENDING",
     "configure"},
    {"Enable system services", "scripts/06-services.sh", "PENDING",
     "configure"},
    {"Configure KDE applications", "scripts/07-kde-apps.sh", "PENDING",
     "configure"},
    {"Build Caelestia shell", "scripts/08-build-shell.sh", "PENDING",
     "build"},
    {"Apply system tweaks", "scripts/09-system-tweaks.sh", "PENDING",
     "finalize"},
    {"Create autostart entries", "scripts/10-autostart.sh", "PENDING",
     "finalize"},
    {"Install optional components", "scripts/11-optional-apps.sh", "PENDING",
     "finalize"},
};

bool step_is_skipped(const Step& step) {
  if (step.name == "Update system") {
    return answer_is_true("SKIP_SYSTEM_UPDATE");
  }
  if (step.name == "Install SDDM theme") {
    return !answer_is_true("INSTALL_SDDM");
  }
  if (step.name == "Install optional components") {
    static const char* opt[] = {"INSTALL_VSCODE",  "INSTALL_ZED",
                                "INSTALL_SPICETIFY", "INSTALL_DISCORD",
                                "INSTALL_TODOIST", "INSTALL_FIREFOX_THEME"};
    for (const char* name : opt) {
      if (answer_is_true(name))
        return false;
    }
    return true;
  }
  return false;
}

string show_error_dialog(const string &step_name, const string &script_path,
                         const string &error_detail, int term_w, int term_h) {
  int selected = 0;
  vector<string> opts = {"Retry", "Ignore", "Exit"};

  // Split the captured output into lines and keep only the last few so the
  // dialog fits on screen while still showing the actual error.
  vector<string> detail;
  {
    string line;
    for (char ch : error_detail) {
      if (ch == '\n') {
        detail.push_back(line);
        line.clear();
      } else {
        line += ch;
      }
    }
    if (!line.empty())
      detail.push_back(line);
    while (detail.size() > 10)
      detail.erase(detail.begin());
  }

  while (true) {
    if (g_resized) {
      Term::get_size();
      g_resized = false;
      term_w = g_term_width;
      term_h = g_term_height;
    }

    cout << Draw::sync_start() << Draw::clear();

    int w = term_w - 6;
    if (w < 30)
      w = 30;
    if (w > term_w - 2)
      w = term_w - 2;
    int h = 12 + (int)detail.size();
    if (h > term_h - 2)
      h = term_h - 2;
    if (h < 12)
      h = 12;
    if (w < 24 || h < 10) {
      cout << Draw::sync_end() << flush;
      return "Exit";
    }
    int x = (term_w - w) / 2;
    if (x < 1)
      x = 1;
    int y = (term_h - h) / 2;
    if (y < 1)
      y = 1;

    Draw::box(x, y, w, h, "INSTALLATION ERROR", "error", "error");

    int ly = y + 2;
    Draw::text(x + 2, ly++, "Step failed:", "error");
    Draw::text(x + 2, ly++, Draw::fit(step_name, (size_t)(w - 4)),
               "bold_on_surface");
    ly++;
    Draw::text(x + 2, ly++, "Script:", "error");
    Draw::text(x + 2, ly++, Draw::fit(script_path, (size_t)(w - 4)),
               "bold_on_surface");
    ly++;
    Draw::text(x + 2, ly++, "Last output:", "error");

    int opt_y = y + h - 3;
    for (auto &l : detail) {
      if (ly >= opt_y)
        break;
      Draw::text(x + 2, ly++, Draw::fit(Draw::strip_ansi(l), (size_t)(w - 4)),
                 "");
    }

    for (size_t i = 0; i < opts.size(); ++i) {
      string col = ((int)i == selected) ? "bold_primary" : "muted";
      Draw::text(x + 4 + (int)i * 12, opt_y,
                 ((int)i == selected ? "> " : "  ") + opts[i], col);
    }
    cout << Draw::sync_end() << flush;

    string key = Input::wait_key();
    if (key == "KEY_left") {
      if (selected > 0)
        selected--;
    } else if (key == "KEY_right") {
      if (selected < (int)opts.size() - 1)
        selected++;
    } else if (key == "enter") {
      return opts[selected];
    } else if (key == "escape") {
      return "Exit";
    }
  }
}

void draw_progress_ui(size_t current_index) {
  if (g_resized) {
    Term::get_size();
    g_resized = false;
  }

  cout << Draw::sync_start() << Draw::clear();

  int x = 1, y = 1;
  int w = g_term_width - 2;
  int h = g_term_height - 2;
  if (w < 24 || h < 8) {
    cout << Draw::sync_end() << flush;
    return;
  }

  Draw::box(x, y, w, h, "", "container", "primary");

  // Progress bar
  string progress_text =
      to_string(current_index) + "/" + to_string(steps.size());
  int bar_w = w - 8 - (int)progress_text.length();
  if (bar_w < 6)
    bar_w = 6;
  size_t done = (current_index * (size_t)bar_w) / steps.size();
  if (done > (size_t)bar_w)
    done = (size_t)bar_w;
  bool arrow = done < (size_t)bar_w;
  string bar = Draw::repeat("=", (int)done) + (arrow ? ">" : "") +
               Draw::repeat(" ", bar_w - (int)done - (arrow ? 1 : 0));
  Draw::text(x + 2, y + 1, "[" + bar + "] " + progress_text, "primary");

  // Aggregate status per phase, then build display lines grouped by phase.
  auto phase_status = [&](const string &pid) -> string {
    bool any_failed = false, any_running = false, any_pending = false,
         any_warn = false, any_ignored = false;
    bool all_skipped = true;
    for (const auto &st : steps) {
      if (st.phase != pid)
        continue;
      if (st.status == "FAILED")
        any_failed = true;
      else if (st.status == "RUNNING")
        any_running = true;
      else if (st.status == "PENDING")
        any_pending = true;
      else if (st.status == "WARN")
        any_warn = true;
      else if (st.status == "IGNORED")
        any_ignored = true;
      if (st.status != "SKIPPED")
        all_skipped = false;
    }
    if (any_failed)
      return string("FAILED");
    if (any_running)
      return string("RUNNING");
    if (any_pending)
      return string("PENDING");
    if (any_warn)
      return string("WARN");
    if (any_ignored)
      return string("IGNORED");
    if (all_skipped)
      return string("SKIPPED");
    return string("OK");
  };

  struct Line {
    string text;
    string color;
    size_t step_idx;
  };
  vector<Line> lines;
  for (const auto &ph : phases) {
    string ps = phase_status(ph.id);
    lines.push_back({Draw::status_glyph(ps) + " " + ph.name,
                     "bold_" + Draw::status_color(ps), (size_t)-1});
    for (size_t i = 0; i < steps.size(); ++i) {
      if (steps[i].phase != ph.id)
        continue;
      string color_name = Draw::status_color(steps[i].status);
      string glyph = Draw::status_glyph(steps[i].status);
      if (i == current_index && steps[i].status == "RUNNING") {
        color_name = "bold_" + color_name;
        glyph = spin_glyph();
      }
      lines.push_back({"  " + glyph + " " + steps[i].name, color_name, i});
    }
  }

  // Scroll so the current step stays visible when the list overflows.
  int max_rows = h - 4;
  if (max_rows < 1)
    max_rows = 1;
  size_t scroll = 0;
  if (lines.size() > (size_t)max_rows) {
    size_t focus = 0;
    for (size_t li = 0; li < lines.size(); ++li) {
      if (lines[li].step_idx == current_index) {
        focus = li;
        break;
      }
    }
    if (focus == 0 && current_index == steps.size()) {
      focus = lines.size() - 1;
    }
    if (focus > (size_t)(max_rows / 2))
      scroll = focus - (size_t)(max_rows / 2);
    if (scroll + (size_t)max_rows > lines.size())
      scroll = lines.size() - (size_t)max_rows;
  }

  for (int r = 0; r < max_rows && (scroll + (size_t)r) < lines.size(); ++r) {
    const Line &ln = lines[scroll + (size_t)r];
    Draw::text(x + 2, y + 2 + r, Draw::fit(ln.text, (size_t)(w - 4)),
               ln.color);
  }

  string hint = "L - Full log    Ctrl+C - Cancel";
  Draw::text(x + 2, y + h - 2, Draw::fit(hint, (size_t)(w - 4)),
             Draw::color("muted"));

  cout << Draw::sync_end() << flush;
}

void execute() {
  string cache_dir =
      string(getenv("XDG_CACHE_HOME") ? getenv("XDG_CACHE_HOME")
                                      : (string(getenv("HOME")) + "/.cache")) +
      "/caelestia-kde";
  setenv("CACHE_DIR", cache_dir.c_str(), 1);
  setenv("BUILDDIR", (cache_dir + "/makepkg-build").c_str(), 1);
  setenv("PKGDEST", (cache_dir + "/makepkg-packages").c_str(), 1);
  setenv("SRCDEST", (cache_dir + "/makepkg-sources").c_str(), 1);
  setenv("SRCPKGDEST", (cache_dir + "/makepkg-srcpackages").c_str(), 1);

  std::error_code fs_error;
  for (const string& path : {cache_dir, cache_dir + "/makepkg-build",
                             cache_dir + "/makepkg-packages",
                             cache_dir + "/makepkg-sources",
                             cache_dir + "/makepkg-srcpackages"}) {
    std::filesystem::create_directories(path, fs_error);
    if (fs_error) {
      Term::restore();
      cerr << "Could not create installer cache directory at " << path << ": "
           << fs_error.message() << endl;
      exit(1);
    }
  }
  std::filesystem::remove(cache_dir + "/failed_steps.txt", fs_error);
  std::filesystem::remove(cache_dir + "/failed_packages.txt", fs_error);
  std::filesystem::remove(cache_dir + "/failed_patches.txt", fs_error);

  setenv("BASE_DISTRO", g_base_distro.c_str(), 1);
  setenv("BUNDLE_DIR", g_bundle_dir.c_str(), 1);

  // Inject our sudo wrapper into the PATH so step scripts never prompt.
  string current_path = getenv("PATH") ? getenv("PATH") : "/usr/bin";
  if (!g_sudo_bin_dir.empty()) {
    setenv("PATH", (g_sudo_bin_dir + ":" + current_path).c_str(), 1);
  }

  setenv("CONFIRM_ARG", "--noconfirm", 1);

  // One shared install log: every step appends to it, and the live log view
  // tails it from the Install screen.
  string log_path = cache_dir + "/install.log";
  int log_fd = open(log_path.c_str(),
                    O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0644);
  if (log_fd < 0) {
    Term::restore();
    cerr << "Could not open installation log at " << log_path << ": "
         << strerror(errno) << endl;
    exit(1);
  }

  // The log view is a persistent display mode, not a blocking screen: the step loop
  // keeps polling the child and advancing while it is open, so watching the full log
  // never stalls the install. It stays open across step boundaries until L/Tab/Esc.
  bool log_open = false;
  UI::LogViewState log_state;

  // Draws the progress screen only when the live log view is not covering it.
  auto show_progress = [&](size_t idx) {
    if (!log_open)
      draw_progress_ui(idx);
  };

  for (size_t i = 0; i < steps.size(); ++i) {
  retry_step:
    if (step_is_skipped(steps[i])) {
      steps[i].status = "SKIPPED";
      // Keep the shared log a complete record when a step is gated off.
      dprintf(log_fd, "\n[CAELESTIA] %s (skipped)\n", steps[i].name.c_str());
      if (log_open) {
        UI::log_view_tick(log_path, log_state);
      } else {
        draw_progress_ui(i);
      }
      continue;
    }

    steps[i].status = "RUNNING";
    show_progress(i);

    // Where this step's log output starts, so its segment can be scanned for [WARN]
    // afterwards.
    long start_offset = 0;
    if (log_fd >= 0) {
      struct stat st {};
      if (fstat(log_fd, &st) == 0)
        start_offset = st.st_size;
      dprintf(log_fd, "\n[CAELESTIA] %s\n", steps[i].name.c_str());
    }

    string script = g_bundle_dir + "/" + steps[i].script_path;
    pid_t child = spawn_step(script, log_fd);
    if (child < 0) {
      steps[i].status = "FAILED";
      show_progress(i);
      string action = show_error_dialog(steps[i].name, steps[i].script_path,
                                        "Could not start the step script.",
                                        g_term_width, g_term_height);
      if (action == "Retry") {
        goto retry_step;
      } else if (action == "Ignore") {
        steps[i].status = "IGNORED";
        continue;
      }
      Term::restore();
      exit(1);
    }

    // Poll the child, redraw on resize, and let the user toggle the log view. The view
    // is non-blocking: waitpid keeps running beneath it, so the step finishes and the
    // next starts even with the full log on screen.
    int child_status = 0;
    while (true) {
      pid_t r = waitpid(child, &child_status, WNOHANG);
      if (r == child)
        break;
      if (r < 0 && errno != EINTR) {
        child_status = 127;
        break;
      }

      if (g_resized && !log_open)
        draw_progress_ui(i);

      if (g_sigint_received || g_sigterm_received || g_quit) {
        kill(child, SIGTERM);
        int st2 = 0;
        waitpid(child, &st2, 0);
        Term::restore();
        if (!g_sudo_bin_dir.empty()) {
          system(("rm -rf \"" + g_sudo_bin_dir + "\"").c_str());
        }
        exit(130);
      }

      // Poll faster while the live log is open so its tail stays smooth; in
      // progress mode the longer timeout paces the spinner.
      string key = Input::wait_key(log_open ? 100 : 200);

      bool closed_log = false;
      if (key == "l" || key == "L" || key == "KEY_shift_tab" ||
          (log_open && key == "escape")) {
        // Toggle the full-screen log. Opening resets scroll state so the view
        // follows the newest output; closing returns to the progress screen.
        log_open = !log_open;
        if (log_open) {
          log_state = UI::LogViewState();
        } else {
          closed_log = true;
        }
      } else if (log_open) {
        // Scroll/pause/next-issue keys; the view is redrawn below.
        UI::log_view_key(key, log_state);
      }

      if (log_open) {
        UI::log_view_tick(log_path, log_state);
      } else if (closed_log || g_resized || key.empty()) {
        // Advance the spinner each poll timeout so a running step shows activity.
        if (key.empty())
          g_spin_frame++;
        draw_progress_ui(i);
      }
    }

    int exit_code = WIFEXITED(child_status) ? WEXITSTATUS(child_status) : 1;

    if (exit_code == 0) {
      // A step can succeed while reporting non-fatal problems; scan its own output
      // for [WARN] and surface WARN.
      string delta;
      bool warned = log_fd >= 0 &&
                    log_tail_since(log_path, start_offset, delta) &&
                    delta.find("[WARN]") != string::npos;
      steps[i].status = warned ? "WARN" : "OK";
    } else {
      steps[i].status = "FAILED";
      show_progress(i);

      string detail;
      {
        vector<string> tail;
        read_log_tail(log_path, 12, tail);
        for (size_t t = 0; t < tail.size(); ++t) {
          if (t)
            detail += "\n";
          detail += tail[t];
        }
      }
      string action = show_error_dialog(steps[i].name, steps[i].script_path,
                                        detail, g_term_width, g_term_height);
      if (action == "Retry") {
        goto retry_step;
      } else if (action == "Ignore") {
        steps[i].status = "IGNORED";
      } else {
        Term::restore();
        exit(1);
      }
    }
  }

  if (log_fd >= 0)
    close(log_fd);

  if (log_open) {
    // Every step is done. Hand the (now static) log to the blocking viewer so
    // the user can review the whole install before the summary screen; nothing
    // is left running to stall, so blocking here is fine.
    UI::log_view(log_path);
  } else {
    draw_progress_ui(steps.size());
    this_thread::sleep_for(chrono::seconds(2));
  }
}
} // namespace Runner
