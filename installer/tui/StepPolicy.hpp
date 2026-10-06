#pragma once

#include <map>
#include <string>

namespace StepPolicy {
bool is_skipped(const std::string &step_name,
                const std::map<std::string, std::string> &answers);
} // namespace StepPolicy
