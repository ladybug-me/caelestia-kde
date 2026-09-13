#include <functional>
#include "UI.hpp"
#include "Globals.hpp"
#include "Term.hpp"
#include "Input.hpp"
#include "Draw.hpp"
#include "Runner.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <sys/wait.h>
#include <sys/stat.h>
#include <signal.h>
#include <thread>
#include <unordered_map>
#include <unistd.h>
#include <vector>

using namespace std;

std::map<std::string, std::string> g_answers;

namespace {

// Writes the password 0600 at creation, so there is no window where it is
// readable - the TOCTOU race of creating under the default umask then chmod'ing.
bool write_password_file_secure(const string& path, const string& password) {
    int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd == -1) {
        return false;
    }
    string data = password + "\n";
    ssize_t written = write(fd, data.c_str(), data.size());
    close(fd);
    return written == static_cast<ssize_t>(data.size());
}

// O_EXCL, so an existing file or symlink at @p path is never followed or overwritten.
bool write_file_excl(const string& path, const string& content, int mode) {
    int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode);
    if (fd == -1) {
        return false;
    }
    ssize_t written = write(fd, content.c_str(), content.size());
    close(fd);
    return written == static_cast<ssize_t>(content.size());
}

bool is_systemd_inhibit(pid_t pid) {
    ifstream cmdline("/proc/" + to_string(pid) + "/cmdline", ios::binary);
    string command((istreambuf_iterator<char>(cmdline)), istreambuf_iterator<char>());
    return command.find("systemd-inhibit") != string::npos;
}

void release_kde_inhibit(const string& cookie_file) {
    ifstream cookie(cookie_file);
    string value;
    getline(cookie, value);
    if (value.empty())
        return;
    pid_t child = fork();
    if (child == 0) {
        execlp("qdbus6", "qdbus6", "org.freedesktop.ScreenSaver",
               "/ScreenSaver", "org.freedesktop.ScreenSaver.UnInhibit",
               value.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }
    if (child > 0)
        waitpid(child, nullptr, 0);
}

// Sets up the sudo askpass environment after a successful password check: password
// file, askpass helper, sudo wrapper, screen inhibitor, and SUDO_PASS.
bool setup_sudo_environment(const string& pw) {
    // A per-run user-owned temp dir, not a fixed /tmp path: mkdtemp is 0700 and the
    // O_EXCL writes below cannot follow a symlink planted at a known name.
    char tmpl[] = "/tmp/caelestia-bin.XXXXXX";
    char* dir = mkdtemp(tmpl);
    if (!dir) {
        return false;
    }
    g_sudo_bin_dir = dir;

    if (!write_password_file_secure(g_sudo_bin_dir + "/pass.txt", pw)) {
        std::filesystem::remove_all(g_sudo_bin_dir);
        g_sudo_bin_dir.clear();
        return false;
    }

    string askpass = "#!/bin/bash\ncat " + g_sudo_bin_dir + "/pass.txt\n";
    if (!write_file_excl(g_sudo_bin_dir + "/askpass.sh", askpass, 0700)) {
        std::filesystem::remove_all(g_sudo_bin_dir);
        g_sudo_bin_dir.clear();
        return false;
    }

    string wrapper = "#!/bin/bash\nexport SUDO_ASKPASS=" + g_sudo_bin_dir +
                     "/askpass.sh\nexec /usr/bin/sudo -A \"$@\"\n";
    if (!write_file_excl(g_sudo_bin_dir + "/sudo", wrapper, 0700)) {
        std::filesystem::remove_all(g_sudo_bin_dir);
        g_sudo_bin_dir.clear();
        return false;
    }

    // Also export SUDO_PASS for some scripts (like 09-system-tweaks.sh) that might rely on it
    setenv("SUDO_PASS", pw.c_str(), 1);

    const char* runtime = getenv("XDG_RUNTIME_DIR");
    const char* home = getenv("HOME");
    string state_dir = string(runtime ? runtime : (getenv("XDG_STATE_HOME")
        ? getenv("XDG_STATE_HOME")
        : (home ? string(home) + "/.local/state" : "/tmp"))) + "/caelestia";
    std::error_code state_error;
    std::filesystem::create_directories(state_dir, state_error);
    if (state_error || chmod(state_dir.c_str(), 0700) != 0) {
        std::filesystem::remove_all(g_sudo_bin_dir);
        g_sudo_bin_dir.clear();
        return false;
    }
    const string pid_file = state_dir + "/inhibit.pid";
    const string cookie_file = state_dir + "/kde_inhibit.cookie";

    // Reap an inhibitor left by a killed earlier run, whose EXIT trap never ran. Only
    // a process whose command line identifies it as our inhibitor is killed.
    ifstream old_pid(pid_file);
    pid_t pid = 0;
    old_pid >> pid;
    if (pid > 0 && is_systemd_inhibit(pid))
        kill(pid, SIGKILL);
    release_kde_inhibit(cookie_file);

    // Start background keep-awake for display (sleep inhibitor)
    pid = fork();
    if (pid == 0) {
        execlp("systemd-inhibit", "systemd-inhibit", "--what=idle:sleep",
               "--who=Caelestia installer", "--why=Installation in progress",
               "bash", "-c", "while :; do sleep 600; done",
               static_cast<char*>(nullptr));
        _exit(127);
    }
    if (pid > 0) {
        ofstream pid_out(pid_file);
        pid_out << pid << '\n';
    }

    int cookie_fd = open(cookie_file.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    pid = fork();
    if (pid == 0) {
        if (cookie_fd >= 0)
            dup2(cookie_fd, STDOUT_FILENO);
        execlp("qdbus6", "qdbus6", "org.freedesktop.ScreenSaver",
               "/ScreenSaver", "org.freedesktop.ScreenSaver.Inhibit",
               "Caelestia installer", "Installation in progress",
               static_cast<char*>(nullptr));
        _exit(127);
    }
    if (cookie_fd >= 0)
        close(cookie_fd);
    if (pid > 0)
        waitpid(pid, nullptr, 0);
    return true;
}

// Human-readable distro label shown on the welcome screen.
string distro_label(const string& id) {
    if (id == "arch") return "Arch-based Linux";
    if (id == "fedora") return "Fedora";
    if (id == "debian") return "Debian-based Linux";
    return id.empty() ? "unknown" : id;
}

const char* navigate_hint() {
    return "Up/Down navigate  Enter select  Left/Esc back";
}

// True when the given step name appears in the failed-steps file.
bool check_failed(const string& file, const string& target) {
    ifstream f(file);
    string line;
    while (getline(f, line)) {
        if (line.find(target) != string::npos) return true;
    }
    return false;
}

// True when the caelestia command (the shell wrapper installed by the
// installer) exists. Update and Uninstall are only offered once it does.
bool is_caelestia_installed() {
    auto executable = [](const string& p) {
        return access(p.c_str(), X_OK) == 0;
    };

    const char* home = getenv("HOME");
    if (home && executable(string(home) + "/.local/bin/caelestia"))
        return true;
    if (executable("/usr/local/bin/caelestia"))
        return true;
    if (executable("/usr/bin/caelestia"))
        return true;

    // Fall back to a PATH search for installs in other prefixes.
    const char* path = getenv("PATH");
    if (path) {
        string paths(path);
        size_t start = 0;
        while (start <= paths.size()) {
            size_t end = paths.find(':', start);
            if (end == string::npos)
                end = paths.size();
            string dir = paths.substr(start, end - start);
            if (!dir.empty() && executable(dir + "/caelestia"))
                return true;
            start = end + 1;
        }
    }
    return false;
}

} // anonymous namespace

namespace UI {
    void welcome_screen() {
        // Drain buffered input left over from terminal setup, so stale
        // escape sequences cannot skip the screen instantly.
        for (int drain = 0; drain < 10 && !Input::get().empty(); ++drain) { }

        vector<string> art;
        if (!g_theme.is_null() && g_theme.contains("splash_screen") && g_theme["splash_screen"].contains("art")) {
            for (auto& line : g_theme["splash_screen"]["art"]) {
                art.push_back(line.get<string>());
            }
        }
        if (art.empty()) art.push_back("Caelestia installer");

        int art_width = 0;
        for (const auto& line : art) {
            if ((int)line.length() > art_width) art_width = (int)line.length();
        }
        int art_height = (int)art.size();

        string art_color = "accent";
        string author = "By @ladybug-me";
        string co_author = "Co-maintainer: 0xSolanaceae";
        if (!g_theme.is_null() && g_theme.contains("splash_screen")) {
            if (g_theme["splash_screen"].contains("art_color"))
                art_color = g_theme["splash_screen"]["art_color"].get<string>();
            if (g_theme["splash_screen"].contains("author"))
                author = g_theme["splash_screen"]["author"].get<string>();
            if (g_theme["splash_screen"].contains("co_author"))
                co_author = g_theme["splash_screen"]["co_author"].get<string>();
        }

        while (!g_quit) {
            if (g_resized) { Term::get_size(); g_resized = false; }

            cout << Draw::sync_start() << Draw::clear();

            int x = 1, y = 1;
            int w = g_term_width - 2;
            int h = g_term_height - 2;

            if (w < 30 || h < 12) {
                Draw::text_center(g_term_height / 2 - 1, "Caelestia installer", "primary");
                Draw::text_center(g_term_height / 2, "Press Enter to continue (Esc to quit)...", "muted");
                cout << Draw::sync_end() << flush;
                string key = Input::wait_key();
                if (key == "enter" || key == " ") return;
                if (key == "escape") { g_quit = true; return; }
                continue;
            }

            Draw::box(x, y, w, h, "", "primary", "primary");

            int left = x + (w - art_width) / 2;
            if (left < x + 1) left = x + 1;
            int top = y + 2;

            cout << Draw::color(art_color) << Draw::bold;
            for (int i = 0; i < art_height; ++i) {
                cout << Draw::to(top + i, left);
                cout << art[i] << flush;
            }
            cout << Draw::reset;

            int ty = top + art_height + 1;
            Draw::text_center(ty, author, "muted");
            Draw::text_center(ty + 1, co_author, "muted");
            Draw::text_center(ty + 3, "Caelestia installer", "primary");
            Draw::text_center(ty + 6, "Detected distribution: " + distro_label(g_base_distro), "secondary");

            // Startup problems sit under the distribution line, but only when
            // there is room for them above the continue hint.
            if (ty + 7 < y + h - 3)
                Draw::problems(x + 2, ty + 7, w - 4, 2);

            Draw::text_center(y + h - 2, "Press Enter to continue (Esc to quit)...", "muted");

            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();
            if (key == "enter" || key == " ") return;
            if (key == "escape") { g_quit = true; return; }
        }
    }

    std::string action_select() {
        struct Action {
            string id;
            string title;
            string help;
        };
        vector<Action> actions;
        actions.push_back({"install", "Install Caelestia", "Install the shell, packages, themes, and configs."});
        if (is_caelestia_installed()) {
            actions.push_back({"update", "Update Caelestia", "Pull the latest code and rebuild the shell."});
            actions.push_back({"uninstall", "Uninstall Caelestia", "Remove the shell and restore backups where available."});
        }
        actions.push_back({"exit", "Exit", "Leave without changing anything."});

        int selected = 0;
        while (!g_quit) {
            if (g_resized) { Term::get_size(); g_resized = false; }
            cout << Draw::sync_start() << Draw::clear();

            int x = 1, y = 1;
            int w = g_term_width - 2;
            int h = g_term_height - 2;
            if (w < 30 || h < 12) {
                cout << Draw::sync_end() << flush;
                return "install";
            }

            Draw::box(x, y, w, h, "CAELESTIA SETUP", "primary", "on_surface");
            Draw::text(x + 2, y + 2, navigate_hint(), "muted");

            for (size_t i = 0; i < actions.size(); ++i) {
                string col = (int)i == selected ? "bold_primary" : "muted";
                Draw::text(x + 4, y + 4 + (int)i,
                           ((int)i == selected ? "> " : "  ") + actions[i].title, col);
            }

            int help_y = y + 5 + (int)actions.size();
            if (help_y < y + h - 2)
                Draw::text(x + 4, help_y, Draw::fit(actions[selected].help, (size_t)(w - 8)), "secondary");

            // Startup problems go above the footer, where nothing else is drawn.
            if (y + h - 4 > help_y + 1)
                Draw::problems(x + 2, y + h - 4, w - 4, 2);

            Draw::text(x + 2, y + h - 2, Draw::fit("Esc - Exit", (size_t)(w - 4)), "muted");

            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();
            if (key == "KEY_up") {
                if (selected > 0) selected--;
            } else if (key == "KEY_down") {
                if (selected < (int)actions.size() - 1) selected++;
            } else if (key == "enter" || key == " ") {
                return actions[selected].id;
            } else if (key == "escape") {
                return "exit";
            }
        }
        return "exit";
    }

    void init_menu_defaults(const json& items) {
        std::function<void(const json&)> walk = [&](const json& arr) {
            for (size_t i = 0; i < arr.size(); ++i) {
                auto& item = arr[i];
                if (item.contains("type") && item["type"] == "submenu" && item.contains("items")) {
                    walk(item["items"]);
                } else if (item.contains("id") && item.contains("default") &&
                           g_answers.find(item["id"].get<string>()) == g_answers.end()) {
                    if (item["default"].is_boolean())
                        g_answers[item["id"].get<string>()] = item["default"].get<bool>() ? "true" : "false";
                    else if (item["default"].is_string())
                        g_answers[item["id"].get<string>()] = item["default"].get<string>();
                }
            }
        };
        walk(items);
    }

    bool sudo_prompt() {
        string pw = "";
        string error_msg = "";
        int attempts = 0;
        int box_width = 56;
        int box_height = 8;

        while (!g_quit) {
            if (g_resized) { Term::get_size(); g_resized = false; }
            cout << Draw::sync_start() << Draw::clear();

            int left = (g_term_width - box_width) / 2;
            if (left < 1) left = 1;
            int top = (g_term_height - box_height) / 2;
            if (top < 1) top = 1;

            Draw::box(left, top, box_width, box_height, "PRIVILEGE ESCALATION", "accent", "on_surface");
            Draw::text(left + 2, top + 2, "Root privileges are required to install packages.", "on_surface");
            Draw::text(left + 2, top + 3, "Password: ", Draw::bold + Draw::color("primary"));

            // Masked password
            string masked(pw.length(), '*');
            masked.resize(30, ' ');
            Draw::text(left + 12, top + 3, masked, Draw::reset);

            if (!error_msg.empty()) {
                Draw::text(left + 2, top + 5, error_msg, "error");
            }

            Draw::text(left + 2, top + box_height - 2, "Esc - Cancel", "muted");

            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();

            auto submit = [&](const string& candidate) -> bool {
                cout << Draw::sync_start();
                Draw::text(left + 2, top + 5, "Verifying...                                 ", "warning");
                cout << Draw::sync_end() << flush;

                FILE* pipe = popen("sudo -S true 2>/dev/null", "w");
                if (pipe) {
                    fprintf(pipe, "%s\n", candidate.c_str());
                    fflush(pipe);
                    int status = pclose(pipe);
                    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
                        if (setup_sudo_environment(candidate))
                            return true;
                        error_msg = "Could not prepare secure sudo helpers.";
                        pw.clear();
                        return false;
                    }
                }
                attempts++;
                if (attempts >= 3) {
                    Term::restore();
                    cout << "Too many incorrect password attempts.\n";
                    exit(1);
                }
                error_msg = "Incorrect password, please try again. (" + to_string(attempts) + "/3)";
                pw.clear();
                return false;
            };

            if (key == "enter") {
                if (pw.empty()) continue;
                if (submit(pw)) return true;
            } else if (key == "backspace" || (key.length() == 1 && (key[0] == '\x7f' || key[0] == '\x08'))) { // Backspace
                if (!pw.empty()) pw.pop_back();
                error_msg.clear();
            } else if (key == "escape") {
                return false;
            } else if (key.find("KEY_") == 0) {
                // ignore internal named keys like KEY_up
            } else if (!key.empty()) {
                // Normal printable chars, including pasted multi-char/UTF-8 text.
                bool all_printable = true;
                for (char c : key) {
                    if ((unsigned char)c < 32 || c == 127) all_printable = false;
                }
                if (all_printable) {
                    pw += key;
                    error_msg.clear();
                } else if (key.find('\n') != string::npos || key.find('\r') != string::npos) {
                    // Pasted text with a trailing newline: strip and submit.
                    string cleaned = "";
                    for (char c : key) {
                        if ((unsigned char)c >= 32 && c != 127) cleaned += c;
                    }
                    pw += cleaned;
                    if (!pw.empty() && submit(pw)) return true;
                }
            }
        }
        return false;
    }

    bool review_screen() {
        size_t scroll = 0;

        while (!g_quit) {
            if (g_resized) { Term::get_size(); g_resized = false; }
            cout << Draw::sync_start() << Draw::clear();

            int x = 1, y = 1;
            int w = g_term_width - 2;
            int h = g_term_height - 2;
            if (w < 30 || h < 10) {
                cout << Draw::sync_end() << flush;
                return false;
            }

            Draw::box(x, y, w, h, "REVIEW INSTALLATION", "primary", "on_surface");

            // Build lines grouped by phase.
            struct Line { string text; string color; };
            vector<Line> lines;
            for (const auto& ph : Runner::phases) {
                lines.push_back({ph.name, "bold_primary"});
                for (const auto& st : Runner::steps) {
                    if (st.phase != ph.id) continue;
                    if (Runner::step_is_skipped(st)) {
                        lines.push_back({"  " + Draw::glyph("skipped") + " " + st.name + " (skipped)", "muted"});
                    } else {
                        lines.push_back({"  " + Draw::glyph("pending") + " " + st.name, "on_surface"});
                    }
                }
                lines.push_back({"", ""});
            }

            int max_rows = h - 5;
            if (max_rows < 1) max_rows = 1;
            if (lines.size() > (size_t)max_rows) {
                if (scroll > lines.size() - (size_t)max_rows) scroll = lines.size() - (size_t)max_rows;
            } else {
                scroll = 0;
            }

            for (int r = 0; r < max_rows && (scroll + (size_t)r) < lines.size(); ++r) {
                const Line& ln = lines[scroll + (size_t)r];
                if (ln.text.empty()) continue;
                Draw::text(x + 2, y + 2 + r, Draw::fit(ln.text, (size_t)(w - 4)), ln.color);
            }

            Draw::text_center(y + h - 3, "Press Enter to begin installation",
                              Draw::bold + Draw::color("primary"));
            Draw::text_center(y + h - 2, "Esc - go back to configuration", "muted");

            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();
            if (key == "enter") return true;
            if (key == "escape" || key == "KEY_left") return false;
            if (key == "KEY_up") {
                if (scroll >= 3) scroll -= 3; else scroll = 0;
            } else if (key == "KEY_down") {
                size_t max_scroll = lines.size() > (size_t)max_rows ? lines.size() - (size_t)max_rows : 0;
                if (scroll + 3 <= max_scroll) scroll += 3;
            }
        }
        return false;
    }

    // Parse and redraw one frame of the full-screen log view. Non-blocking, so call it
    // repeatedly while the view is up; a size check skips re-reading an unchanged log.
    void log_view_tick(const std::string& log_path, LogViewState& s) {
        if (g_resized) { Term::get_size(); g_resized = false; s.redraw = true; }

        long size_now = -1;
        {
            struct stat st {};
            if (stat(log_path.c_str(), &st) == 0)
                size_now = (long)st.st_size;
        }
        if (!s.redraw && size_now == s.last_size)
            return;
        s.last_size = size_now;

        string content;
        {
            ifstream in(log_path, ios::binary);
            if (in) {
                in.seekg(0, ios::end);
                streamoff len = in.tellg();
                const streamoff kMax = 1024 * 1024; // tail at most 1 MiB
                if (len > kMax)
                    in.seekg(len - kMax, ios::beg);
                else
                    in.seekg(0, ios::beg);
                stringstream ss;
                ss << in.rdbuf();
                content = ss.str();
            }
        }

        s.lines.clear();
        s.issues.clear();
        string line;
        auto push_line = [&]() {
            if (line.find("[WARN]") != string::npos || line.find("[ERR]") != string::npos)
                s.issues.push_back(s.lines.size());
            s.lines.push_back(Draw::strip_ansi(line));
            line.clear();
        };
        for (char ch : content) {
            if (ch == '\n')
                push_line();
            else
                line += ch;
        }
        if (!line.empty())
            push_line();
        s.redraw = true;

        // Follow keeps the newest line on screen; otherwise hold the paused position.
        int show = g_term_height - 6;
        if (show < 1) show = 1;
        long max_scroll = (long)s.lines.size() - show;
        if (max_scroll < 0) max_scroll = 0;
        if (s.follow) {
            s.view_top = max_scroll;
        } else {
            if (s.view_top > max_scroll) s.view_top = max_scroll;
            if (s.view_top < 0) s.view_top = 0;
        }

        cout << Draw::sync_start() << Draw::clear();

        int x = 1, y = 1;
        int w = g_term_width - 2;
        int h = g_term_height - 2;
        if (w < 20 || h < 6) { cout << Draw::sync_end() << flush; return; }

        Draw::box(x, y, w, h, "INSTALL LOG", "primary", "on_surface");

        for (int i = 0; i < show && (s.view_top + (long)i) < (long)s.lines.size(); ++i) {
            long idx = s.view_top + (long)i;
            string color;
            if (s.lines[idx].find("[ERR]") != string::npos)
                color = "error";
            else if (s.lines[idx].find("[WARN]") != string::npos)
                color = "warning";
            Draw::text(x + 2, y + 2 + i, Draw::fit(s.lines[idx], (size_t)(w - 4)), color);
        }

        string status = s.follow ? "Following" : "Paused";
        string help = "Up/Down/PgUp/PgDn scroll   n/p - next issue   L - back";
        Draw::text(x + 2, y + h - 2,
                   Draw::fit(status + "    " + help, (size_t)(w - 4)), "muted");
        cout << Draw::sync_end() << flush;
    }

    // Applies one key to the log view. Returns true when the key leaves the view
    // (L/Tab/Esc/Ctrl+C). Paging is recomputed per frame so it survives a resize.
    bool log_view_key(const std::string& key, LogViewState& s) {
        if (key == "l" || key == "L" || key == "KEY_shift_tab" ||
            key == "escape" || key == "signal_interrupt")
            return true;

        int show = g_term_height - 6;
        if (show < 1) show = 1;
        int page = show > 1 ? show - 1 : 1;
        long max_scroll = (long)s.lines.size() - show;
        if (max_scroll < 0) max_scroll = 0;

        if (key == "KEY_up") {
            s.follow = false;
            if (s.view_top > 0) { s.view_top--; s.redraw = true; }
        } else if (key == "KEY_down") {
            if (!s.follow) {
                if (s.view_top < max_scroll) { s.view_top++; s.redraw = true; }
                if (s.view_top >= max_scroll) s.follow = true;
            }
        } else if (key == "KEY_page_up") {
            s.follow = false;
            long before = s.view_top;
            s.view_top -= page;
            if (s.view_top < 0) s.view_top = 0;
            if (s.view_top != before) s.redraw = true;
        } else if (key == "KEY_page_down") {
            if (!s.follow) {
                long before = s.view_top;
                s.view_top += page;
                if (s.view_top > max_scroll) s.view_top = max_scroll;
                if (s.view_top >= max_scroll) s.follow = true;
                if (s.view_top != before) s.redraw = true;
            }
        } else if (key == "KEY_home") {
            s.follow = false;
            if (s.view_top != 0) { s.view_top = 0; s.redraw = true; }
        } else if (key == "KEY_end") {
            if (!s.follow || s.view_top != max_scroll) { s.follow = true; s.view_top = max_scroll; s.redraw = true; }
        } else if (key == "n" || key == "N") {
            long target = -1;
            for (size_t idx : s.issues) {
                if ((long)idx > s.view_top) { target = (long)idx; break; }
            }
            if (target == -1 && !s.issues.empty()) target = (long)s.issues[0];
            if (target != -1) {
                s.follow = false;
                s.view_top = target - show / 2;
                if (s.view_top < 0) s.view_top = 0;
                s.redraw = true;
            }
        } else if (key == "p" || key == "P") {
            long target = -1;
            for (size_t i = s.issues.size(); i-- > 0;) {
                if ((long)s.issues[i] < s.view_top) { target = (long)s.issues[i]; break; }
            }
            if (target == -1 && !s.issues.empty()) target = (long)s.issues.back();
            if (target != -1) {
                s.follow = false;
                s.view_top = target - show / 2;
                if (s.view_top < 0) s.view_top = 0;
                s.redraw = true;
            }
        }
        return false;
    }

    // Blocking full-screen tail of the install log. Only safe on the Complete screen: it
    // reads keys until the user leaves, so the install loop must not call it mid-step.
    // The runner keeps log_open instead and drives log_view_tick/log_view_key, so steps
    // advance underneath an open view.
    void log_view(const std::string& log_path) {
        LogViewState s;
        while (!g_quit) {
            log_view_tick(log_path, s);
            string key = Input::wait_key(100);
            if (log_view_key(key, s)) return;
        }
    }

    void complete_screen() {
        string cache_dir = string(getenv("XDG_CACHE_HOME") ? getenv("XDG_CACHE_HOME") : (string(getenv("HOME")) + "/.cache")) + "/caelestia-kde";
        string steps_file = cache_dir + "/failed_steps.txt";
        string pkgs_file = cache_dir + "/failed_packages.txt";
        string patches_file = cache_dir + "/failed_patches.txt";
        string log_path = cache_dir + "/install.log";

        while (true) {
            if (g_resized) { Term::get_size(); g_resized = false; }
            cout << Draw::sync_start() << Draw::clear();

            int w = g_term_width - 2;
            if (w > 80) w = 80;
            int h = g_term_height - 2;
            int left = (g_term_width - w) / 2;
            int top = 1;
            const size_t content_width = w > 4 ? static_cast<size_t>(w - 4) : 0;

            // Gather error status
            vector<string> failed_pkgs;
            ifstream pf(pkgs_file);
            string pkg;
            while (getline(pf, pkg)) {
                if (!pkg.empty()) failed_pkgs.push_back(pkg);
            }
            bool shell_failed = check_failed(steps_file, "Build Caelestia Shell");
            bool has_errors = !failed_pkgs.empty() || shell_failed;

            Draw::box(left, top, w, h, has_errors ? "INSTALLATION COMPLETED WITH WARNINGS" : "INSTALLATION COMPLETE", has_errors ? "warning" : "success", "on_surface");

            int y = top + 2;

            const char* start_epoch_str = getenv("INSTALL_START_EPOCH");
            if (start_epoch_str && y < top + h - 4) {
                long elapsed = time(NULL) - atol(start_epoch_str);
                long hours = elapsed / 3600;
                long mins = (elapsed % 3600) / 60;
                long secs = elapsed % 60;
                char buf[64];
                snprintf(buf, sizeof(buf), "Finished in %ldh %ldm %lds", hours, mins, secs);
                Draw::text(left + 2, y++, Draw::fit(Draw::glyph("ok") + " " + buf, content_width), "success");
            }

            if (has_errors) {
                y++;
                if (y < top + h - 4) {
                    Draw::text(left + 2, y++, "ATTENTION NEEDED", Draw::bold + Draw::color("error"));
                }
                if (shell_failed && y < top + h - 4) {
                    Draw::text(left + 2, y++, Draw::fit("- Shell build failed (check missing dependencies in log).", content_width), "error");
                }
                if (!failed_pkgs.empty() && y < top + h - 4) {
                    string pkg_str = "- Failed packages: ";
                    for (size_t i = 0; i < failed_pkgs.size(); ++i) {
                        if (i > 0) pkg_str += ", ";
                        pkg_str += failed_pkgs[i];
                    }
                    Draw::text(left + 2, y++, Draw::fit(pkg_str, content_width), "error");
                }
            }

            y++;
            if (y < top + h - 11) {
                Draw::text(left + 2, y++, "QUICK START & SHORTCUTS", Draw::bold + Draw::color("primary"));
                Draw::text(left + 2, y++, Draw::fit("  Super / Super+Space   Application Launcher", content_width), "on_surface");
                Draw::text(left + 2, y++, Draw::fit("  Super+Return          Terminal", content_width), "on_surface");
                Draw::text(left + 2, y++, Draw::fit("  Super+/               Show Keybinds Helper", content_width), "on_surface");
                Draw::text(left + 2, y++, Draw::fit("  Super+V               Clipboard History", content_width), "on_surface");
                Draw::text(left + 2, y++, Draw::fit("  Super+Shift+S         Screenshot Tool", content_width), "on_surface");
                Draw::text(left + 2, y++, Draw::fit("  Super+B               Sidebar & Notifications", content_width), "on_surface");
            }

            y++;
            if (y < top + h - 6) {
                Draw::text(left + 2, y++, "NEXT STEPS", Draw::bold + Draw::color("warning"));
                Draw::text(left + 2, y++, Draw::fit("- Log out and back in to start your new Caelestia session.", content_width));
                Draw::text(left + 2, y++, Draw::fit("- Full log saved to: " + log_path, content_width), "muted");
            }

            Draw::text(left + 2, top + h - 3, Draw::fit("Press L to view the full log", content_width), "muted");
            Draw::text(left + 2, top + h - 2, Draw::fit("Log out now? (Y/n): ", content_width), Draw::bold + Draw::color("on_surface"));
            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();
            if (key == "y" || key == "Y" || key == "enter") {
                g_logout = true;
                break;
            } else if (key == "n" || key == "N" || key == "escape") {
                g_logout = false;
                break;
            } else if (key == "l" || key == "L") {
                log_view(log_path);
                // The loop redraws the summary after returning from the log.
            }
        }
    }
}

namespace UI {
    bool render_menu(const json& menu_items, const std::string& title) {
        struct MenuItemMeta {
            string type;
            string title;
            string id;
            string help;
            vector<string> options;
            unordered_map<string, int> option_index;
        };

        int selected = 0;
        int num_items = static_cast<int>(menu_items.size());
        if (num_items == 0) return true;

        // Seed defaults for this (sub)menu (idempotent: only fills gaps).
        init_menu_defaults(menu_items);

        vector<MenuItemMeta> meta;
        meta.reserve(static_cast<size_t>(num_items));
        for (int i = 0; i < num_items; ++i) {
            auto& item = menu_items[i];
            MenuItemMeta m;
            m.type = item.contains("type") ? item["type"].get<string>() : "action";
            m.title = item.contains("title") ? item["title"].get<string>() : "Unknown";
            m.id = item.contains("id") ? item["id"].get<string>() : "";
            m.help = item.contains("help") ? item["help"].get<string>() : "";

            if (m.type == "select" && item.contains("options") && item["options"].is_array()) {
                auto& opts = item["options"];
                m.options.reserve(opts.size());
                for (size_t oi = 0; oi < opts.size(); ++oi) {
                    string opt = opts[oi].get<string>();
                    m.option_index[opt] = static_cast<int>(oi);
                    m.options.push_back(opt);
                }
                if (!m.id.empty() && !m.options.empty() && g_answers[m.id].empty()) {
                    g_answers[m.id] = m.options[0];
                }
            }

            meta.push_back(std::move(m));
        }

        auto build_display = [&](int index) {
            const auto& m = meta[index];
            string display;
            if (m.type == "submenu") {
                display = m.title + " >";
            } else if (m.type == "boolean") {
                bool val = (g_answers[m.id] == "true");
                display = (val ? Draw::glyph("checkbox_on") : Draw::glyph("checkbox_off")) + " " + m.title;
            } else if (m.type == "select") {
                display = m.title + ": " + Draw::glyph("select_left") + " " + g_answers[m.id] + " " + Draw::glyph("select_right");
            } else {
                display = m.title;
            }
            return display;
        };

        while (!g_quit) {
            if (g_resized) { Term::get_size(); g_resized = false; }

            int w = 64;
            for (int i = 0; i < num_items; ++i) {
                int len = static_cast<int>(build_display(i).length());
                if (len + 8 > w) w = len + 8;
            }
            if (w > g_term_width - 4) w = g_term_width - 4;

            int h = num_items + 7;
            if (h > g_term_height - 4) h = g_term_height - 4;
            int left = (g_term_width - w) / 2;
            int top = (g_term_height - h) / 2;
            int start_y = top + 4;
            int max_len = w - 8;

            cout << Draw::sync_start() << Draw::clear();

            Draw::box(left, top, w, h, title, "primary", "on_surface");

            Draw::text(left + 2, top + 2, Draw::fit(navigate_hint(), (size_t)(w - 4)), "muted");

            for (int i = 0; i < num_items; ++i) {
                if (start_y + i >= top + h - 1) break;
                string display = Draw::fit(build_display(i), (size_t)max_len);
                string line = (i == selected ? "> " : "  ") + display;
                if (static_cast<int>(line.length()) < max_len + 2) {
                    line.append(static_cast<size_t>(max_len + 2 - static_cast<int>(line.length())), ' ');
                }
                string color_name = (i == selected) ? "bold_primary" : "on_surface";
                Draw::text(left + 4, start_y + i, line, color_name);
            }

            // Help text for the selected item.
            const string& help = meta[selected].help;
            if (!help.empty()) {
                Draw::text(left + 2, top + h - 2, Draw::fit(help, (size_t)(w - 4)), "muted");
            }

            cout << Draw::sync_end() << flush;

            string key = Input::wait_key();
            auto& item = menu_items[selected];
            auto& selected_meta = meta[selected];
            string type = selected_meta.type;
            string id = selected_meta.id;

            if (key == "KEY_up") {
                if (selected > 0) selected--;
            }
            else if (key == "KEY_down") {
                if (selected < num_items - 1) selected++;
            }
            else if (key == "KEY_right" || key == "enter" || key == " ") {
                if (type == "action") {
                    if (id == "action_back") return false;
                    if (id == "action_review" || id == "action_proceed") return true;
                } else if (type == "submenu") {
                    if (item.contains("items")) {
                        bool proceed = render_menu(item["items"], selected_meta.title);
                        if (proceed) return true; // review chosen from a submenu bubbles up
                    }
                } else if (type == "boolean") {
                    g_answers[id] = (g_answers[id] == "true") ? "false" : "true";
                } else if (type == "select") {
                    if (!selected_meta.options.empty()) {
                        int current_idx = 0;
                        auto it = selected_meta.option_index.find(g_answers[id]);
                        if (it != selected_meta.option_index.end()) current_idx = it->second;
                        current_idx = (current_idx + 1) % static_cast<int>(selected_meta.options.size());
                        g_answers[id] = selected_meta.options[static_cast<size_t>(current_idx)];
                    }
                }
            } else if (key == "KEY_left") {
                if (type == "select") {
                    if (!selected_meta.options.empty()) {
                        int current_idx = 0;
                        auto it = selected_meta.option_index.find(g_answers[id]);
                        if (it != selected_meta.option_index.end()) current_idx = it->second;
                        current_idx = (current_idx - 1 + static_cast<int>(selected_meta.options.size())) % static_cast<int>(selected_meta.options.size());
                        g_answers[id] = selected_meta.options[static_cast<size_t>(current_idx)];
                    }
                } else {
                    return false; // back out of submenu
                }
            } else if (key == "escape") {
                return false;
            }
        }
        return false;
    }
}
