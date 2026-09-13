#pragma once
#include <cstddef>
#include <map>
#include <string>
#include <vector>
#include "json.hpp"

extern std::map<std::string, std::string> g_answers;

namespace UI {
    void welcome_screen();
    bool sudo_prompt();

    // Top-level action: "install", "update", "uninstall", or "exit".
    std::string action_select();

    // Seeds g_answers from menu item defaults (idempotent).
    void init_menu_defaults(const nlohmann::json& menu_items);

    // Returns true when the user asks to proceed to the review screen.
    bool render_menu(const nlohmann::json& menu_items, const std::string& title);

    // Returns true to begin installation, false to go back to configuration.
    bool review_screen();

    // Full-screen live tail of the install log; returns on L/Tab/Esc.
    // Blocking: only safe where no step is still running (Complete screen).
    void log_view(const std::string& log_path);

    // The runner keeps one instance across steps, so scroll/follow position survives
    // while the install advances underneath an open log view.
    struct LogViewState {
        bool redraw = true;   // force a full redraw on the next tick
        long last_size = -1;  // install.log size at the last parse
        std::vector<std::string> lines;   // ANSI-stripped log lines
        std::vector<size_t> issues;       // indices of lines with [WARN]/[ERR]
        long view_top = 0;    // index of the first visible line
        bool follow = true;   // auto-scroll to the newest line
    };

    // Parse + redraw one frame of the full-screen log view. Non-blocking;
    // call repeatedly while the view is on screen (handles resize itself).
    void log_view_tick(const std::string& log_path, LogViewState& state);

    // Apply one key to the log view state (scroll/follow/next issue).
    // Returns true when the key asks to leave the view (L/Tab/Esc/Ctrl+C).
    bool log_view_key(const std::string& key, LogViewState& state);

    void complete_screen();
}
