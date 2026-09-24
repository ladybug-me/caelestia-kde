#include "Globals.hpp"
#include <cctype>
#include <iostream>
#include <fstream>
#include <iterator>
#include <sstream>
#include <cstdlib>

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

std::string xdg_cache_dir() {
    if (const char* cache = std::getenv("XDG_CACHE_HOME"))
        return cache;
    if (const char* home = std::getenv("HOME"))
        return std::string(home) + "/.cache";
    // The same last resort UI.cpp uses for its state directory: somewhere writable
    // when the environment names no home at all.
    return "/tmp";
}

namespace {

// The same ID lists detect_base_distro() in scripts/lib/packages.sh reads,
// so the TUI and the step scripts cannot disagree about a distro's family.
const char* const kArchIds[] = {
    "arch", "cachyos", "endeavouros", "manjaro", "artix", "archlinux",
};
const char* const kFedoraIds[] = {
    "fedora", "nobara", "bazzite", "rhel", "centos", "almalinux", "rocky",
};
const char* const kDebianIds[] = {
    "debian", "ubuntu", "pop", "mint", "kali", "raspbian",
    "elementary", "zorin", "deepin", "devuan",
};

bool known_id(const char* const* ids, size_t count, const std::string& value) {
    for (size_t i = 0; i < count; ++i) {
        if (value == ids[i])
            return true;
    }
    return false;
}

std::string unquote(std::string value) {
    if (value.size() >= 2 && value.front() == '"' && value.back() == '"')
        value.erase(value.size() - 1, 1).erase(0, 1);
    return value;
}

std::string lowercase(std::string value) {
    for (char& c : value)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return value;
}

} // namespace

std::string detect_distro_from_os_release(const std::string& path) {
    // The TUI normally gets BASE_DISTRO from setup.sh, which reads
    // /etc/os-release through scripts/lib/packages.sh. A direct run of the
    // compiled binary (CONTRIBUTING's ./installer/build/caelestia-install
    // "$PWD") has no setup.sh, and the "unknown" default then dies at
    // scripts/02-all-packages.sh with "No package list for 'unknown'". ID is
    // consulted first, then ID_LIKE, exactly like the shell-side detection;
    // the package-manager fallback has no equivalent here because the step
    // scripts run it themselves.
    std::ifstream in(path);
    if (!in)
        return "";

    std::string id;
    std::string id_like;
    std::string line;
    while (std::getline(in, line)) {
        if (line.compare(0, 3, "ID=") == 0)
            id = unquote(line.substr(3));
        else if (line.compare(0, 8, "ID_LIKE=") == 0)
            id_like = unquote(line.substr(8));
    }

    id = lowercase(id);
    if (known_id(kArchIds, std::size(kArchIds), id))
        return "arch";
    if (known_id(kFedoraIds, std::size(kFedoraIds), id))
        return "fedora";
    if (known_id(kDebianIds, std::size(kDebianIds), id))
        return "debian";

    // ID_LIKE names the families a distro is compatible with ("archlinux",
    // "rhel fedora", "debian ubuntu"), space- or comma-separated.
    for (char& c : id_like)
        if (c == ',')
            c = ' ';
    std::istringstream like(lowercase(id_like));
    std::string token;
    while (like >> token) {
        if (known_id(kArchIds, std::size(kArchIds), token))
            return "arch";
        if (known_id(kFedoraIds, std::size(kFedoraIds), token))
            return "fedora";
        if (known_id(kDebianIds, std::size(kDebianIds), token))
            return "debian";
    }
    return "";
}

int run_shell(const std::string& command) {
    return std::system(command.c_str());
}

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
