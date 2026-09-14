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

    std::string action_select();

    void init_menu_defaults(const nlohmann::json& menu_items);

    bool render_menu(const nlohmann::json& menu_items, const std::string& title);

    bool review_screen();

    void log_view(const std::string& log_path);

    struct LogViewState {
        bool redraw = true;   // force a full redraw on the next tick
        long last_size = -1;  // install.log size at the last parse
        std::vector<std::string> lines;   // ANSI-stripped log lines
        std::vector<size_t> issues;       // indices of lines with [WARN]/[ERR]
        long view_top = 0;    // index of the first visible line
        bool follow = true;   // auto-scroll to the newest line
    };

    void log_view_tick(const std::string& log_path, LogViewState& state);

    bool log_view_key(const std::string& key, LogViewState& state);

    void complete_screen();
}
