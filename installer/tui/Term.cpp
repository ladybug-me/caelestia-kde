#include "Term.hpp"
#include "Globals.hpp"
#include <iostream>
#include <unistd.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <cstdlib>

using namespace std;

namespace Term {
    termios initial_settings;
    bool initialized = false;

    void get_size() {
        winsize wsize{};
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &wsize) >= 0 && wsize.ws_col > 0) {
            g_term_width = wsize.ws_col;
            g_term_height = wsize.ws_row;
        } else {
            int fd = open("/dev/tty", O_RDONLY | O_CLOEXEC);
            if (fd != -1) {
                if (ioctl(fd, TIOCGWINSZ, &wsize) >= 0 && wsize.ws_col > 0) {
                    g_term_width = wsize.ws_col;
                    g_term_height = wsize.ws_row;
                }
                close(fd);
            }
        }
    }

    void restore() {
        if (initialized) {
            tcsetattr(STDIN_FILENO, TCSANOW, &initial_settings);
            cout << "\x1b[0m\x1b[?1049l\x1b[?25h" << flush; // reset, exit alt screen, show cursor
            initialized = false;
        }
    }

    void init() {
        if (!initialized && isatty(STDIN_FILENO)) {
            tcgetattr(STDIN_FILENO, &initial_settings);
            termios settings = initial_settings;
            settings.c_lflag &= ~(ECHO | ICANON);
            settings.c_cc[VMIN] = 0;
            settings.c_cc[VTIME] = 0;
            tcsetattr(STDIN_FILENO, TCSANOW, &settings);

            cout << "\x1b[?1049h\x1b[?25l" << flush; // enter alt screen, hide cursor
            initialized = true;
            atexit(restore);
        }
        get_size();
    }
}
