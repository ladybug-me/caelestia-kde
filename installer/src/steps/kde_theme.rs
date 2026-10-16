use std::fs;
use std::path::{Path, PathBuf};

use crate::js;
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure, wallpapers_dir};

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    output::info("Applying KDE settings");
    println!();

    apply_darkly(context);
    apply_fonts(context);
    cliphist_service();

    output::ok("KDE settings applied.");
    set_wallpaper(context);

    Ok(())
}

fn apply_darkly(context: &Context) {
    if !context.flag("APPLY_DARKLY", true) {
        output::skip("Skipping Darkly theme");
        return;
    }

    output::info("Applying Darkly plasma style...");
    write_key("plasmarc", "Theme", "name", "darkly");

    let theme = Path::new("/usr/share/plasma/desktoptheme/darkly");
    if theme.is_dir() {
        let target = data_home().join("plasma").join("desktoptheme");
        let _ = fs::create_dir_all(&target);
        #[cfg(unix)]
        {
            let _ = std::os::unix::fs::symlink(theme, target.join("Darkly"));
            let _ = std::os::unix::fs::symlink(theme, target.join("darkly"));
        }
    }

    output::info("Applying Darkly application style...");
    write_key("kdeglobals", "KDE", "widgetStyle", "darkly");
    write_key("kdeglobals", "General", "ColorScheme", "Darkly");

    output::info("Applying Darkly window decoration...");
    if decoration_installed() {
        write_key(
            "kwinrc",
            "org.kde.kdecoration2",
            "library",
            "org.kde.darkly",
        );
        write_key("kwinrc", "org.kde.kdecoration2", "theme", "@darkly");
    } else {
        write_key(
            "kwinrc",
            "org.kde.kdecoration2",
            "library",
            "org.kde.breeze",
        );
        write_key("kwinrc", "org.kde.kdecoration2", "theme", "Breeze");
    }
}

fn decoration_installed() -> bool {
    const PLUGIN: &str = "org.kde.kdecoration3/org.kde.darkly.so";

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(directory) = process::capture("qtpaths6", &["--plugin-dir"])
        && !directory.is_empty()
    {
        candidates.push(PathBuf::from(directory).join(PLUGIN));
    }
    for directory in ["/usr/lib/qt6/plugins", "/usr/local/lib/qt6/plugins"] {
        candidates.push(Path::new(directory).join(PLUGIN));
    }
    candidates.push(
        paths::home()
            .join(".local")
            .join("lib")
            .join("qt6")
            .join("plugins")
            .join(PLUGIN),
    );

    candidates.iter().any(|candidate| candidate.is_file())
}

fn apply_fonts(context: &Context) {
    if !context.flag("APPLY_FONTS", true) {
        output::skip("Skipping custom fonts application.");
        return;
    }

    if !process::available("lookandfeeltool") {
        return;
    }

    if !context.flag("APPLY_DARKLY", true) {
        output::skip(
            "Skipping Darkly LNF as Darkly theme was opted out. (Fonts must be applied manually)",
        );
        return;
    }

    let listed = process::capture("lookandfeeltool", &["--list"]).unwrap_or_default();
    let available = listed
        .lines()
        .any(|line| line.trim().eq_ignore_ascii_case("darkly"));
    if available {
        output::info("Applying custom fonts and LNF via lookandfeeltool...");
        let _ = process::succeeds("lookandfeeltool", &["--apply", "Darkly"], None);
    }
}

fn cliphist_service() {
    output::info("Setting up cliphist background service...");

    let bin = paths::home().join(".local").join("bin");
    let units = paths::home().join(".config").join("systemd").join("user");
    let _ = fs::create_dir_all(&bin);
    let _ = fs::create_dir_all(&units);

    let runner = bin.join("caelestia-cliphist");
    if fs::write(&runner, CLIPHIST_RUNNER).is_ok() {
        paths::make_executable(&runner);
    }
    let _ = fs::write(units.join("cliphist.service"), CLIPHIST_UNIT);

    let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
    let _ = process::succeeds(
        "systemctl",
        &["--user", "enable", "--now", "cliphist.service"],
        None,
    );
    output::ok("Cliphist background service enabled.");
}

fn set_wallpaper(context: &Context) {
    let walls = wallpapers_dir(context);
    let pack_default = walls
        .join("dharmx-digital")
        .join("a_couple_of_people_standing_on_a_mountain.png");
    let fallback = context
        .bundle
        .join("shell")
        .join("assets")
        .join("wallpaper.webp");
    let chosen = if pack_default.is_file() {
        pack_default
    } else {
        fallback
    };

    let state = paths::state_dir().join("caelestia");
    let recorded = fs::read_to_string(state.join("wallpaper").join("path.txt")).unwrap_or_default();
    let in_use = recorded.trim().to_string();

    if !in_use.is_empty() && Path::new(&in_use).is_file() {
        output::skip(&format!(
            "Keeping the wallpaper in use: {}",
            basename(Path::new(&in_use))
        ));
        let in_use = Path::new(&in_use);
        apply_wallpaper(in_use);
        patch_breeze_login_wallpaper(in_use);
        return;
    }

    if !chosen.is_file() {
        return;
    }

    output::info(&format!(
        "Setting default wallpaper to {}...",
        basename(&chosen)
    ));
    apply_wallpaper(&chosen);

    let directory = state.join("wallpaper");
    let _ = fs::create_dir_all(&directory);
    let _ = fs::write(
        directory.join("path.txt"),
        format!("{}\n", chosen.display()),
    );

    if process::available("kwriteconfig6") {
        write_key(
            "kscreenlockerrc",
            "Greeter",
            "WallpaperPlugin",
            "org.kde.image",
        );
        let image = format!("file://{}", chosen.display());
        let _ = process::succeeds(
            "kwriteconfig6",
            &[
                "--file",
                "kscreenlockerrc",
                "--group",
                "Greeter",
                "--group",
                "Wallpaper",
                "--group",
                "org.kde.image",
                "--group",
                "General",
                "--key",
                "Image",
                &image,
            ],
            None,
        );
    }

    patch_breeze_login_wallpaper(&chosen);
}

fn apply_wallpaper(image: &Path) {
    if !process::available("qdbus6") {
        return;
    }

    let url = js::string(&format!("file://{}", image.display()));
    let script = plasma_script(&url);
    let _ = process::succeeds(
        "qdbus6",
        &[
            "org.kde.plasmashell",
            "/PlasmaShell",
            "org.kde.PlasmaShell.evaluateScript",
            &script,
        ],
        None,
    );
}

fn plasma_script(url: &str) -> String {
    format!(
        "
            var allDesktops = desktops();
            for (i=0; i < allDesktops.length; i++) {{
                d = allDesktops[i];
                d.wallpaperPlugin = 'org.kde.image';
                d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
                d.writeConfig('Image', '{url}');
            }}
        "
    )
}

fn patch_breeze_login_wallpaper(image: &Path) {
    if crate::install_kind::is_packaged() {
        return;
    }
    if !Path::new("/usr/share/sddm/themes/breeze/theme.conf").is_file() {
        return;
    }

    let expression = format!("s|^background=.*|background={}|", image.display());
    let _ = privileges::elevated(
        "sed",
        &[
            "-i",
            &expression,
            "/usr/share/sddm/themes/breeze/theme.conf",
        ],
        None,
    );
}

fn write_key(file: &str, group: &str, key: &str, value: &str) {
    let _ = process::succeeds(
        "kwriteconfig6",
        &["--file", file, "--group", group, "--key", key, value],
        None,
    );
}

fn basename(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default()
}

fn data_home() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| paths::home().join(".local").join("share"))
}

const CLIPHIST_RUNNER: &str = r#"#!/bin/bash
set -uo pipefail

private_mime_types='application/x-krita-|image/x-inkscape-svg'

for helper in wl-paste cliphist wl-clip-persist; do
    command -v "$helper" >/dev/null 2>&1 || { echo "missing: $helper" >&2; exit 1; }
done

wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &
wl-clip-persist --clipboard regular \
    --all-mime-type-regex "(?i)^(?!(?:${private_mime_types})).+" &
wait -n
"#;

const CLIPHIST_UNIT: &str = r#"[Unit]
Description=Clipboard history service
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/caelestia-cliphist
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_cliphist_service_starts_the_runner_it_writes() {
        assert!(CLIPHIST_UNIT.contains("ExecStart=%h/.local/bin/caelestia-cliphist"));
        assert!(CLIPHIST_UNIT.contains("WantedBy=default.target"));
        assert!(CLIPHIST_RUNNER.contains("wl-clip-persist --clipboard regular"));
        assert!(CLIPHIST_RUNNER.contains("wait -n"));
    }

    #[test]
    fn the_wallpaper_script_carries_the_escaped_url() {
        let image = Path::new("/home/me/My Walls/w.png");
        let url = js::string(&format!("file://{}", image.display()));
        assert!(url.contains("\\u0020"), "a space has to be escaped: {url}");

        let script = plasma_script(&url);
        assert!(
            script.contains(&format!("d.writeConfig('Image', '{url}');")),
            "{script}"
        );
        assert!(script.contains("d.wallpaperPlugin = 'org.kde.image';"));
        assert!(script.contains("d.currentConfigGroup = Array('Wallpaper',"));
    }

    #[test]
    fn a_path_is_named_by_its_last_component() {
        assert_eq!(basename(Path::new("/home/me/wall.png")), "wall.png");
        assert_eq!(basename(Path::new("wall.png")), "wall.png");
    }
}
