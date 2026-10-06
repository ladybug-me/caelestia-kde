#include "StepPolicy.hpp"

namespace {
bool answer_is_true(const std::map<std::string, std::string> &answers,
                    const char *name) {
  const auto it = answers.find(name);
  return it != answers.end() && it->second == "true";
}
} // namespace

namespace StepPolicy {
bool is_skipped(const std::string &step_name,
                const std::map<std::string, std::string> &answers) {
  if (step_name == "Update system") {
    return answer_is_true(answers, "SKIP_SYSTEM_UPDATE");
  }
  if (step_name == "Install SDDM theme") {
    return !answer_is_true(answers, "INSTALL_SDDM");
  }
  if (step_name == "Install optional components") {
    static const char *optional_answers[] = {
        "INSTALL_VSCODE", "INSTALL_ZED", "INSTALL_SPICETIFY",
        "INSTALL_DISCORD", "INSTALL_TODOIST", "INSTALL_FIREFOX_THEME",
    };
    for (const char *answer : optional_answers) {
      if (answer_is_true(answers, answer)) {
        return false;
      }
    }
    return true;
  }
  return false;
}
} // namespace StepPolicy
