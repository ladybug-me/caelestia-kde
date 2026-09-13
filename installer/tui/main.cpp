#include "Globals.hpp"
#include "Term.hpp"
#include "UI.hpp"
#include "Runner.hpp"
#include <iostream>
#include <fstream>
#include <csignal>
#include <cstdlib>
#include <sys/wait.h>
#include <unistd.h>

using namespace std;

// sig_atomic_t is the only cross-signal-safe type; all cleanup is deferred to the
// main loop.
volatile sig_atomic_t g_sigint_received = 0;
volatile sig_atomic_t g_sigterm_received = 0;

void handle_sigwinch(int) {
    g_resized = true;
}

void handle_sigint(int) {
    // Only set the flag - no library calls from signal context; check_signals() cleans up.
    g_sigint_received = 1;
}

void handle_sigterm(int) {
    g_sigterm_received = 1;
}

void check_signals() {
    if (g_sigint_received || g_sigterm_received) {
        g_quit = true;
        Term::restore();
        if (!g_sudo_bin_dir.empty()) {
            system(("rm -rf \"" + g_sudo_bin_dir + "\"").c_str());
        }
        exit(130);
    }
}

// Hands the terminal to an interactive script (update.sh or uninstall.sh) and exits.
// Those drive the terminal themselves, so re-entering the TUI's raw/alternate screen
// afterwards corrupts it and wedges the installer. Re-run the installer for the next action.
void run_external(const std::string& script_path) {
    Term::restore();
    pid_t child = fork();
    if (child == 0) {
        execlp("bash", "bash", script_path.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }
    int status = 1;
    if (child > 0)
        waitpid(child, &status, 0);
    int rc = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    std::cout << "\n"
              << (rc == 0 ? "Finished." : "Finished with errors.")
              << std::endl;
    exit(rc == 0 ? 0 : 1);
}

int main(int argc, char** argv) {
    // Detect bundle dir from the executable. A non-action first argument can
    // override it, while "--update"/"--uninstall" preselect the action.
    char buf[1024];
    ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf)-1);
    if (len != -1) {
        buf[len] = '\0';
        string path(buf);
        size_t pos = path.find_last_of('/');
        if (pos != string::npos) {
            g_bundle_dir = path.substr(0, pos);
        }
    }

    std::string preset_action;
    if (argc > 1) {
        std::string first = argv[1];
        if (first == "--update") {
            preset_action = "update";
        } else if (first == "--uninstall") {
            preset_action = "uninstall";
        } else {
            g_bundle_dir = first;
        }
    }

    // Early diagnostic: print bundle dir to stderr so setup.sh can capture it
    std::cerr << "[installer] bundle dir: " << g_bundle_dir << std::endl;

    // Hide cursor immediately so the TUI never flashes it
    std::cout << "\x1b[?25l" << std::flush;
    Term::init();

    load_theme();

    // The step scripts are the one thing the TUI cannot run without. The theme and menu
    // checks live in load_theme() above, which records failures for the screens to draw,
    // since the alternate screen hides stderr.
    {
        std::string scripts_dir = g_bundle_dir + "/scripts";
        if (!std::ifstream(scripts_dir + "/00a-system-update.sh").good()) {
            std::cerr << "[installer] WARNING: scripts directory missing at " << scripts_dir << std::endl;
            g_startup_problems.push_back("step scripts not found - the installer cannot run any step");
        }
    }

    signal(SIGWINCH, handle_sigwinch);
    signal(SIGINT, handle_sigint);
    signal(SIGTERM, handle_sigterm);

    // Distro detection happens in setup.sh and arrives via BASE_DISTRO.
    const char* env_distro = getenv("BASE_DISTRO");
    if (env_distro && string(env_distro) != "") {
        g_base_distro = env_distro;
    }

    // Phase 1: Welcome (splash merged into the frame)
    if (preset_action.empty()) {
        std::cerr << "[installer] phase 1: welcome_screen" << std::endl;
        UI::welcome_screen();
        check_signals();

        // Esc on the welcome screen sets g_quit; exit as cleanly as the other cancels.
        if (g_quit) {
            std::cerr << "[installer] user quit at welcome screen" << std::endl;
            Term::restore();
            std::cout << "\n\n\nExiting installer.\n";
            return 0;
        }
    }

    // Phase 1.5: Action select. Update and uninstall hand off to their scripts on the
    // real terminal; install continues into the wizard.
    std::string action = preset_action;
    while (true) {
        if (action.empty()) {
            std::cerr << "[installer] phase 1.5: action_select" << std::endl;
            action = UI::action_select();
        }
        if (action == "exit") {
            Term::restore();
            return 0;
        }
        if (action == "update" || action == "uninstall") {
            std::cerr << "[installer] action: " << action << std::endl;
            std::string script = g_bundle_dir + (action == "update" ? "/update.sh" : "/uninstall.sh");
            run_external(script); // exits; does not return
        }
        break; // install
    }

    // Phase 2: Sudo Auth
    std::cerr << "[installer] phase 2: sudo_prompt" << std::endl;
    if (!UI::sudo_prompt()) {
        std::cerr << "[installer] user canceled at sudo prompt" << std::endl;
        Term::restore();
        return 0;
    }
    check_signals();

    // Phase 3: Configure -> Review (review happens before any step runs).
    if (!g_menu.is_null() && g_menu.contains("menu")) {
        std::cerr << "[installer] phase 3: configure + review" << std::endl;
        UI::init_menu_defaults(g_menu["menu"]);

        bool begin = false;
        while (!begin && !g_quit) {
            if (!UI::render_menu(g_menu["menu"], "CONFIGURATION")) {
                std::cerr << "[installer] user backed out of menu" << std::endl;
                Term::restore();
                return 0;
            }
            if (UI::review_screen()) {
                begin = true;
            }
        }
        if (g_quit) {
            Term::restore();
            return 0;
        }

        // Export all answers as environment variables for the bash scripts
        for (const auto& pair : g_answers) {
            setenv(pair.first.c_str(), pair.second.c_str(), 1);
        }

        // Persist the install-time menu choices so update.sh can restore them: a fresh
        // update process runs the deploy/build/tweak scripts with none of these env vars
        // set, so every script gate (${DEFAULT_SHELL:-fish}, ${INSTALL_FISH:-true}, ...)
        // would fall back to its hardcoded default and silently revert the user's choice.
        if (const char* home = getenv("HOME")) {
            string cfg_dir = string(home) + "/.config/caelestia-kde";
            std::string safe_dir = cfg_dir;
            for (size_t pos = 0; (pos = safe_dir.find('\'', pos)) != std::string::npos; pos += 4)
                safe_dir.replace(pos, 1, "'\\\''");
            system(("mkdir -p '" + safe_dir + "'").c_str());
            ofstream env_file(cfg_dir + "/install.env", ios::out | ios::trunc);
            if (env_file.is_open()) {
                for (const auto& pair : g_answers) {
                    // Only persist entries that are valid shell env names.
                    if (pair.first.empty())
                        continue;
                    bool valid = (pair.first[0] == '_') ||
                                 (pair.first[0] >= 'a' && pair.first[0] <= 'z') ||
                                 (pair.first[0] >= 'A' && pair.first[0] <= 'Z');
                    if (!valid)
                        continue;
                    for (char c : pair.first) {
                        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                              (c >= '0' && c <= '9') || c == '_')) {
                            valid = false;
                            break;
                        }
                    }
                    if (!valid)
                        continue;

                    // Single-quoted so a value with shell metacharacters stays parseable.
                    env_file << pair.first << "='";
                    for (char c : pair.second) {
                        if (c == '\'')
                            env_file << "'\\''";
                        else
                            env_file << c;
                    }
                    env_file << "'\n";
                }
                env_file.close();
            }
        }
    } else {
        std::cerr << "[installer] phase 3: skipped (no menu loaded)" << std::endl;
    }

    check_signals();
    // Phase 4: Execute
    std::cerr << "[installer] phase 4: execute (" << Runner::steps.size() << " steps)" << std::endl;
    Runner::execute();

    check_signals();
    // Phase 5: Complete
    std::cerr << "[installer] phase 5: complete_screen" << std::endl;
    UI::complete_screen();
    Term::restore();

    if (g_answers["REMOVE_CACHE"] == "true") {
        string cache_dir = string(getenv("XDG_CACHE_HOME") ? getenv("XDG_CACHE_HOME") : (string(getenv("HOME")) + "/.cache")) + "/caelestia-kde";
        system(("rm -rf \"" + cache_dir + "\"").c_str());
    }

    // Secure cleanup of sudo credentials
    if (!g_sudo_bin_dir.empty()) {
        system(("rm -rf \"" + g_sudo_bin_dir + "\"").c_str());
    }

    if (g_logout) {
        cout << "\nLogging out...\n";
        system("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null");
    } else {
        cout << "\nCaelestia installation complete. Remember to log out to activate your new session.\n";
    }

    // Write completion marker so setup.sh can distinguish success from early exit
    std::cerr << "[installer] done (success)" << std::endl;
    return 0;
}
