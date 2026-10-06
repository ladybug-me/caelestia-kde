#include "StepPolicy.hpp"

#include <iostream>
#include <map>
#include <string>

namespace {

using Answers = std::map<std::string, std::string>;

int failures = 0;

void expect_skipped(bool expected, const char *step, const Answers &answers) {
  const bool actual = StepPolicy::is_skipped(step, answers);
  if (actual != expected) {
    std::cerr << "FAIL: " << step << " expected skipped=" << expected
              << " but got " << actual << '\n';
    ++failures;
  }
}

} // namespace

int main() {
  // Explicit checks rather than assert(): NDEBUG compiles assert() away, which
  // would silently turn this suite into a pass.
  expect_skipped(true, "Update system", {{"SKIP_SYSTEM_UPDATE", "true"}});
  expect_skipped(false, "Update system", {{"SKIP_SYSTEM_UPDATE", "false"}});
  expect_skipped(true, "Install SDDM theme", Answers{});
  expect_skipped(false, "Install SDDM theme", {{"INSTALL_SDDM", "true"}});
  expect_skipped(true, "Install optional components", Answers{});
  expect_skipped(false, "Install optional components", {{"INSTALL_ZED", "true"}});
  expect_skipped(false, "Build Caelestia shell", Answers{});

  if (failures > 0) {
    std::cerr << failures << " step-policy check(s) failed\n";
    return 1;
  }
  std::cout << "step-policy checks passed\n";
  return 0;
}
