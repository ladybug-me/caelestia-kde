#include "Draw.hpp"
#include "Globals.hpp"
#include <iostream>
#include <map>

using namespace std;

namespace Draw {
    const string esc = "\x1b[";
    const string reset = esc + "0m";
    const string bold = esc + "1m";
    const string dim = esc + "2m";

    string repeat(const string& s, int n) {
        string out;
        if (n <= 0) return out;
        out.reserve(s.size() * static_cast<size_t>(n));
        for (int i = 0; i < n; ++i) out += s;
        return out;
    }

    string fit(const string& text, size_t max_len) {
        if (max_len == 0) return string();
        if (text.size() <= max_len) return text;
        if (max_len <= 3) return text.substr(0, max_len);
        return text.substr(0, max_len - 3) + "...";
    }

    string strip_ansi(const string& text) {
        string out;
        out.reserve(text.size());
        for (size_t i = 0; i < text.size(); ++i) {
            char c = text[i];
            if (c == '\x1b') {
                if (i + 1 < text.size() && text[i + 1] == '[') {
                    i += 2;
                    while (i < text.size()) {
                        char f = text[i];
                        if ((f >= 'A' && f <= 'Z') || (f >= 'a' && f <= 'z') || f == '~') break;
                        ++i;
                    }
                } else if (i + 1 < text.size() && text[i + 1] == ']') {
                    i += 2;
                    while (i < text.size() && text[i] != '\x07') ++i;
                } else if (i + 1 < text.size()) {
                    ++i;
                }
                continue;
            }
            out += c;
        }
        return out;
    }

    string color(const string& name) {
        if (name.empty()) {
            return "";
        }

        if (name.find("\x1b[") != string::npos) {
            return name;
        }

        if (name == "reset") {
            return reset;
        }
        if (name == "bold") {
            return bold;
        }
        if (name == "dim") {
            return dim;
        }

        static const string bold_prefix = "bold_";
        if (name.rfind(bold_prefix, 0) == 0 && name.size() > bold_prefix.size()) {
            return bold + color(name.substr(bold_prefix.size()));
        }

        auto it = g_theme_colors.find(name);
        if (it != g_theme_colors.end()) {
            return it->second;
        }
        return esc + "39m";
    }

    string glyph(const string& name) {
        if (!g_theme.is_null() && g_theme.contains("glyphs") &&
            g_theme["glyphs"].is_object() && g_theme["glyphs"].contains(name) &&
            g_theme["glyphs"][name].is_string()) {
            return g_theme["glyphs"][name].get<string>();
        }
        static const map<string, string> fallback = {
            {"pending", "[ ]"},     {"running", "[>]"},      {"ok", "[OK]"},
            {"warn", "[WARN]"},     {"failed", "[ERR]"},     {"skipped", "[SKIP]"},
            {"checkbox_on", "[x]"}, {"checkbox_off", "[ ]"},
            {"select_left", "<"},   {"select_right", ">"},
        };
        auto it = fallback.find(name);
        return it != fallback.end() ? it->second : "?";
    }

    string status_glyph(const string& status) {
        if (status == "RUNNING") return glyph("running");
        if (status == "OK") return glyph("ok");
        if (status == "WARN") return glyph("warn");
        if (status == "FAILED") return glyph("failed");
        if (status == "SKIPPED") return glyph("skipped");
        if (status == "IGNORED") return "[IGNORED]";
        return glyph("pending");
    }

    string status_color(const string& status) {
        if (status == "RUNNING") return "primary";
        if (status == "OK") return "success";
        if (status == "WARN") return "warning";
        if (status == "FAILED") return "error";
        if (status == "IGNORED") return "warning";
        return "muted"; // PENDING, SKIPPED
    }

    string to(int line, int col) {
        return esc + to_string(line) + ";" + to_string(col) + "H";
    }

    string clear() {
        return esc + "2J" + to(1, 1);
    }

    string sync_start() { return esc + "?2026h"; }
    string sync_end()   { return esc + "?2026l"; }

    void box(int x, int y, int w, int h, const string& title, const string& border_color, const string& title_color) {
        if (w < 2 || h < 2) return;
        string tl = "+", tr = "+", bl = "+", br = "+", hz = "-", vt = "|";
        string c = color(border_color);
        string tc = title_color.empty() ? reset : color(title_color);
        string out = c;

        out += to(y, x) + tl + repeat(hz, w - 2) + tr;
        out += to(y + h - 1, x) + bl + repeat(hz, w - 2) + br;

        for (int i = 1; i < h - 1; i++) {
            out += to(y + i, x) + vt;
            out += to(y + i, x + w - 1) + vt;
        }

        if (!title.empty()) {
            int pad = (w - static_cast<int>(title.length()) - 2) / 2;
            if (pad > 0) {
                out += to(y, x + pad) + bold + reset + c + "[" + reset + bold + tc + title + reset + c + "]" + reset;
            }
        }
        cout << out << reset;
    }

    void text(int x, int y, const string& txt, const string& color_name) {
        string c = color_name.empty() ? "" : color(color_name);
        cout << to(y, x) << c << txt << reset;
    }

    void text_center(int y, const string& txt, const string& color_name) {
        int x = (g_term_width - static_cast<int>(txt.length())) / 2;
        if (x < 0) x = 0;
        text(x, y, txt, color_name);
    }

    int problems(int x, int y, int w, int max) {
        int line = y;
        for (const auto& problem : g_startup_problems) {
            if (line - y >= max) break;
            text(x, line, fit(problem, (size_t)w), "warning");
            ++line;
        }
        return line;
    }
}
