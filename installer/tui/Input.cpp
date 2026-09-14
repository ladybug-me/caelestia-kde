#include "Input.hpp"
#include "Term.hpp"
#include "Globals.hpp"
#include <csignal>
#include <unistd.h>
#include <sys/select.h>
#include <unordered_map>

using namespace std;

extern volatile sig_atomic_t g_sigint_received;
extern volatile sig_atomic_t g_sigterm_received;

namespace Input {
    unordered_map<string, string> Key_escapes = {
        {"\x1b", "escape"}, {"\n", "enter"}, {"\r", "enter"},
        {"\x1b[A", "KEY_up"}, {"\x1b[B", "KEY_down"}, {"\x1b[C", "KEY_right"}, {"\x1b[D", "KEY_left"},
        {"\x1b[Z", "KEY_shift_tab"},
        {"\x1b[5~", "KEY_page_up"}, {"\x1b[6~", "KEY_page_down"},
        {"\x1b[H", "KEY_home"}, {"\x1b[1~", "KEY_home"}, {"\x1b[7~", "KEY_home"}, {"\x1bOH", "KEY_home"},
        {"\x1b[F", "KEY_end"}, {"\x1b[4~", "KEY_end"}, {"\x1b[8~", "KEY_end"}, {"\x1bOF", "KEY_end"}
    };

    string get() {
        char buf[256];
        ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
        if (n <= 0) return "";
        string key(buf, n);

        if (key.length() == 1 && key[0] == 3) { // Ctrl+C
            g_quit = true;
            return "signal_interrupt";
        }

        if (Key_escapes.count(key)) return Key_escapes[key];
        return key;
    }

    string wait_key(int timeout_ms) {
        while (!g_quit) {
            if (g_sigint_received || g_sigterm_received) {
                return "signal_interrupt";
            }

            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(STDIN_FILENO, &fds);
            timeval tv;
            timeval* ptv = nullptr;
            if (timeout_ms >= 0) {
                tv.tv_sec = timeout_ms / 1000;
                tv.tv_usec = (timeout_ms % 1000) * 1000;
                ptv = &tv;
            }
            int res = select(STDIN_FILENO + 1, &fds, nullptr, nullptr, ptv);
            if (res > 0) {
                return get();
            } else if (res == 0) {
                return ""; // timeout
            } else {
                if (errno == EINTR) {
                    if (g_resized) return "resize";
                    if (g_sigint_received || g_sigterm_received) return "signal_interrupt";
                    continue;
                }
            }
        }
        return "";
    }
}
