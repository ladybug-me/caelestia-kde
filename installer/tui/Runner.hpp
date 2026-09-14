#pragma once
#include <string>
#include <vector>

namespace Runner {
    struct Phase {
        std::string id;
        std::string name;
    };

    struct Step {
        std::string name;
        std::string script_path;
        std::string status; // "PENDING", "RUNNING", "OK", "WARN", "FAILED", "SKIPPED", "IGNORED"
        std::string phase;  // phase id
    };

    extern const std::vector<Phase> phases;
    extern std::vector<Step> steps;

    bool step_is_skipped(const Step& step);

    std::string show_error_dialog(const std::string& step_name, const std::string& script_path, const std::string& error_detail, int term_w, int term_h);
    void draw_progress_ui(size_t current_index);
    void execute();
}
