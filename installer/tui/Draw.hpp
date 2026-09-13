#pragma once
#include <string>

namespace Draw {
    extern const std::string reset;
    extern const std::string bold;
    extern const std::string dim;

    // Resolves a palette name from theme.json (hex -> 24-bit ANSI) or a legacy ANSI
    // suffix. Supports "bold_<name>" prefixes.
    std::string color(const std::string& name);

    std::string to(int line, int col);
    std::string clear();
    std::string sync_start();
    std::string sync_end();

    // Plain-text status markers from the theme: pending, running, ok, warn, failed,
    // skipped, checkbox_on, checkbox_off, select_left, select_right.
    std::string glyph(const std::string& name);

    // Status is one of PENDING, RUNNING, OK, WARN, FAILED, SKIPPED.
    std::string status_glyph(const std::string& status);
    std::string status_color(const std::string& status);

    // Repeat a string n times, truncate with "...", and strip ANSI from log output.
    std::string repeat(const std::string& s, int n);
    std::string fit(const std::string& text, size_t max_len);
    std::string strip_ansi(const std::string& text);

    // Draws the startup problems from g_startup_problems at (x, y), at most max lines,
    // clipped to w; returns the next free line.
    int problems(int x, int y, int w, int max);

    void box(int x, int y, int w, int h, const std::string& title = "", const std::string& border_color = "container", const std::string& title_color = "");
    void text(int x, int y, const std::string& txt, const std::string& color_name = "");
    void text_center(int y, const std::string& txt, const std::string& color_name = "");
}
