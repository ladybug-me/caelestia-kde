#pragma once
#include "json.hpp"
#include <atomic>
#include <string>
#include <unordered_map>
#include <vector>

using json = nlohmann::json;

extern json g_theme;
extern json g_menu;
extern std::unordered_map<std::string, std::string> g_theme_colors;

extern std::vector<std::string> g_startup_problems;

extern std::atomic<bool> g_resized;
extern std::atomic<bool> g_quit;
extern int g_term_width;
extern int g_term_height;
extern std::string g_base_distro;
extern std::string g_bundle_dir;
extern std::string g_sudo_bin_dir;

void load_bundle_dir();
void load_theme();

/// The user's cache root: $XDG_CACHE_HOME, else $HOME/.cache, else /tmp when a caller
/// has neither. Shared so no caller has to decide what an unset HOME means, and so
/// none of them can build a string straight from a null getenv() result.
std::string xdg_cache_dir();

/// Runs a shell command and returns system()'s status, for callers that check it and
/// for the ones that mark a deliberate ignore with a (void) cast.
int run_shell(const std::string& command);

struct Config {
  bool enable_transaction_confirm = true;
  bool remove_cache = false;
  bool apply_darkly = true;
  bool apply_custom_fonts = true;
};

extern Config g_config;
extern bool g_logout;
