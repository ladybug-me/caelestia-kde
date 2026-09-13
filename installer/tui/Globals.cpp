#include "Globals.hpp"
#include <iostream>
#include <fstream>

std::atomic<bool> g_resized{false};
std::atomic<bool> g_quit{false};
int g_term_width = 80;
int g_term_height = 24;
std::string g_base_distro = "unknown";
std::string g_bundle_dir = ".";
std::string g_sudo_bin_dir;
std::vector<std::string> g_startup_problems;

Config g_config;
bool g_logout = false;
json g_theme;
json g_menu;
std::unordered_map<std::string, std::string> g_theme_colors;

// A hex value (#rrggbb) becomes 24-bit truecolor; anything else is a legacy ANSI
// suffix (e.g. "36m").
std::string color_sequence(const std::string& value) {
    if (value.size() == 7 && value[0] == '#') {
        int r = std::stoi(value.substr(1, 2), nullptr, 16);
        int g = std::stoi(value.substr(3, 2), nullptr, 16);
        int b = std::stoi(value.substr(5, 2), nullptr, 16);
        return "\x1b[38;2;" + std::to_string(r) + ";" + std::to_string(g) + ";" + std::to_string(b) + "m";
    }
    return "\x1b[" + value;
}

void load_theme() {
    g_theme_colors.clear();

    std::string path = g_bundle_dir + "/installer/data/theme.json";
    std::ifstream f(path);
    if (f.is_open()) {
        try {
            g_theme = json::parse(f, nullptr, true, true);
            if (g_theme.contains("palette") && g_theme["palette"].is_object()) {
                for (auto& [name, value] : g_theme["palette"].items()) {
                    if (value.is_string()) {
                        g_theme_colors[name] = color_sequence(value.get<std::string>());
                    }
                }
            } else if (g_theme.contains("colors") && g_theme["colors"].is_object()) {
                // Legacy theme files store raw ANSI suffixes under "colors".
                for (auto& [name, value] : g_theme["colors"].items()) {
                    if (value.is_string()) {
                        g_theme_colors[name] = color_sequence(value.get<std::string>());
                    }
                }
            }
        } catch (...) {
            std::cerr << "Failed to parse theme.json" << std::endl;
            g_startup_problems.push_back("theme.json could not be parsed - using the built-in colors");
        }
    } else {
        std::cerr << "Could not open theme.json at " << path << std::endl;
        g_startup_problems.push_back("theme.json not found - using the built-in colors (re-run setup.sh)");
    }

    std::string menu_path = g_bundle_dir + "/installer/data/menu.json";
    std::ifstream f2(menu_path);
    if (f2.is_open()) {
        try {
            g_menu = json::parse(f2, nullptr, true, true);
        } catch (...) {
            std::cerr << "Failed to parse menu.json" << std::endl;
            g_startup_problems.push_back("menu.json could not be parsed - using the built-in menu");
        }
    } else {
        std::cerr << "Could not open menu.json at " << menu_path << std::endl;
        g_startup_problems.push_back("menu.json not found - using the built-in menu (re-run setup.sh)");
    }
}

