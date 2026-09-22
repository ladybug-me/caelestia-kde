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

volatile sig_atomic_t g_sigint_received = 0;
volatile sig_atomic_t g_sigterm_received = 0;

void handle_sigwinch(int) {
    g_resized = true;
}

void handle_sigint(int) {
    g_sigint_received = 1;
}

void handle_sigterm(int) {
    g_sigterm_received = 1;
}

void check_signals() {
    if (g_sigint_received || g_sigterm_received) {
        g_quit = true;
        Term::restore();
        if (!g_sudo_bin_dir.empty() && run_shell("rm -rf \"" + g_sudo_bin_dir + "\"") != 0) {
            cerr << "[installer] warning: could not remove the sudo shim directory " << g_sudo_bin_dir << endl;
        }
        exit(130);
    }
}

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

    std::cerr << "[installer] bundle dir: " << g_bundle_dir << std::endl;

    std::cout << "\x1b[?25l" << std::flush;
    Term::init();

    load_theme();

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

    const char* env_distro = getenv("BASE_DISTRO");
    if (env_distro && string(env_distro) != "") {
        g_base_distro = env_distro;
    }

    if (preset_action.empty()) {
        std::cerr << "[installer] phase 1: welcome_screen" << std::endl;
        UI::welcome_screen();
        check_signals();

        if (g_quit) {
            std::cerr << "[installer] user quit at welcome screen" << std::endl;
            Term::restore();
            std::cout << "\n\n\nExiting installer.\n";
            return 0;
        }
    }

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

    std::cerr << "[installer] phase 2: sudo_prompt" << std::endl;
    if (!UI::sudo_prompt()) {
        std::cerr << "[installer] user canceled at sudo prompt" << std::endl;
        Term::restore();
        return 0;
    }
    check_signals();

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

        for (const auto& pair : g_answers) {
            setenv(pair.first.c_str(), pair.second.c_str(), 1);
        }

        if (const char* home = getenv("HOME")) {
            string cfg_dir = string(home) + "/.config/caelestia-kde";
            std::string safe_dir = cfg_dir;
            for (size_t pos = 0; (pos = safe_dir.find('\'', pos)) != std::string::npos; pos += 4)
                safe_dir.replace(pos, 1, "'\\\''");
            if (run_shell("mkdir -p '" + safe_dir + "'") != 0)
                cerr << "[installer] warning: could not create " << cfg_dir
                     << "; the step scripts will not get the answers file." << endl;
            ofstream env_file(cfg_dir + "/install.env", ios::out | ios::trunc);
            if (env_file.is_open()) {
                for (const auto& pair : g_answers) {
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
    std::cerr << "[installer] phase 4: execute (" << Runner::steps.size() << " steps)" << std::endl;
    Runner::execute();

    check_signals();
    // Phase 5: Complete
    std::cerr << "[installer] phase 5: complete_screen" << std::endl;
    UI::complete_screen();
    Term::restore();

    if (g_answers["REMOVE_CACHE"] == "true") {
        string cache_dir = xdg_cache_dir() + "/caelestia-kde";
        // Best effort: the cache is scratch space, and a failed removal only costs
        // the next run the disk space it was asked to free.
        (void)run_shell("rm -rf \"" + cache_dir + "\"");
    }

    // Secure cleanup of sudo credentials
    if (!g_sudo_bin_dir.empty() && run_shell("rm -rf \"" + g_sudo_bin_dir + "\"") != 0) {
        cerr << "[installer] warning: could not remove the sudo shim directory " << g_sudo_bin_dir << endl;
    }

    if (g_logout) {
        cout << "\nLogging out...\n";
        if (run_shell("qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null") != 0)
            cerr << "[installer] warning: the session did not accept the logout request; log out manually." << endl;
    } else {
        cout << "\nCaelestia installation complete. Remember to log out to activate your new session.\n";
    }

    // Write completion marker so setup.sh can distinguish success from early exit
    std::cerr << "[installer] done (success)" << std::endl;
    return 0;
}
