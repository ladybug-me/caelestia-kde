use std::fs;
use std::path::{Path, PathBuf};

use crate::install_kind;
use crate::output;
use crate::paths;
use crate::process;
use crate::steps::{Context, Failure};

const AUTOSTART_TEMPLATE: &str = r#"#!/bin/bash
# Where this install's files are. environment.d carries the same values for a
# session; they are repeated because the unit can start this outside one.
#
# The command the shell and its widgets call by name must be on PATH for everything
# this spawns: the 08-build-shell step installs it into ~/.local/bin, which a session started
# by the display manager does not necessarily have on PATH.
export PATH="__BIN_DIR__:$PATH"
export QML2_IMPORT_PATH="__QML_IMPORT_PATH__"
export CAELESTIA_LIB_DIR="__LIB_DIR__"
export CAELESTIA_BIN_DIR="__BIN_DIR__"
export CAELESTIA_SHELL_CONFIG="__SHELL_CONFIG__"
export QS_NO_RELOAD_POPUP=1
export QS_DROP_EXPENSIVE_FONTS=1
export QS_DISABLE_CRASH_HANDLER=1
export QSG_RENDER_LOOP=threaded
export QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
# Quickshell imports its Hyprland IPC module even on KDE for API compatibility.
# Its missing-socket warning is expected when this KDE port has no Hyprland instance.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    if [[ -n "${QT_LOGGING_RULES:-}" ]]; then
        export QT_LOGGING_RULES="${QT_LOGGING_RULES};quickshell.hyprland.ipc.warning=false"
    else
        export QT_LOGGING_RULES="quickshell.hyprland.ipc.warning=false"
    fi
fi
# Self-heal Caelestia lock screen if KDE updates or kconf_update reset it
if [ -f "$HOME/.local/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreen.qml" ] || [ -f "/usr/share/plasma/shells/caelestia.desktop/contents/lockscreen/LockScreen.qml" ]; then
    if command -v kreadconfig6 >/dev/null 2>&1 && command -v kwriteconfig6 >/dev/null 2>&1; then
        current_shell="$(kreadconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" 2>/dev/null || true)"
        if [ "$current_shell" != "caelestia.desktop" ]; then
            kwriteconfig6 --file plasmashellrc --group "Shell" --key "ShellPackage" "caelestia.desktop" 2>/dev/null || true
        fi
        kwriteconfig6 --file kscreenlockerrc --group "Greeter" --key "Theme" --delete 2>/dev/null || true
    fi
fi
# No --daemonize: the unit supervises this process and sends its stdout/stderr to
# the journal. Detaching would replace that with /dev/null, and every app launched
# from the shell inherits those descriptors - which is how the shell was handing
# apps a stdout that goes nowhere. Vesktop deadlocks in exactly that state when a
# call starts (issue #402); reproducible outside the shell with
# `vesktop >/dev/null 2>&1`.
#
# It also makes the old stdbuf wrapper unnecessary: journald stdio is what the
# line-buffering hack worked around, and stdbuf leaked LD_PRELOAD=libstdbuf.so into
# every launched app besides.
exec "__QUICKSHELL_PATH__" -n -p "__SHELL_CONFIG__"
"#;

const SHELL_UNIT: &str = r#"[Unit]
Description=Caelestia Shell
PartOf=graphical-session.target
After=graphical-session.target
Before=xdg-desktop-autostart.target

[Service]
Type=exec
ExecStart=%h/.local/bin/caelestia-autostart.sh
# A shell that cannot start is retried, but not in a tight loop: systemd gives up on
# a unit that starts five times in ten seconds, and clearing that state falls to an
# install. Upstream's unit waits the same five seconds between attempts.
Restart=on-failure
RestartSec=5s
TimeoutStopSec=5s
Slice=session.slice

[Install]
WantedBy=graphical-session.target
"#;

pub fn run(context: &Context) -> Result<(), Failure> {
    let home = paths::home();
    let autostart = home.join(".config").join("autostart");
    let units = home.join(".config").join("systemd").join("user");
    let _ = fs::create_dir_all(&autostart);
    let _ = fs::create_dir_all(home.join(".local").join("bin"));

    println!();
    println!();
    output::info("Setting up autostart entries");
    println!();

    let quickshell =
        find_quickshell().ok_or("Quickshell is not installed or is not available in PATH.")?;

    if install_kind::is_packaged() {
        packaged(&home, &units);
    } else {
        let shell_config = install_kind::shell_config();
        if !shell_config.is_file() {
            return Err(format!(
                "Caelestia Shell entrypoint not found: {} (run caelestia-install step 08-build-shell first)",
                shell_config.display()
            )
            .into());
        }
        write_launcher(&home, &quickshell, &shell_config, &units);
    }

    retire_old_autostart(&autostart);
    let _ = process::succeeds(
        "systemctl",
        &["--user", "reset-failed", "caelestia-shell.service"],
        None,
    );
    clear_dangling_enable_links(&units);

    let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
    if process::succeeds(
        "systemctl",
        &["--user", "enable", "caelestia-shell.service"],
        None,
    ) {
        output::ok("Caelestia Shell unit enabled.");
    } else {
        output::warn(
            "Could not enable caelestia-shell.service; start the shell with 'systemctl --user start caelestia-shell.service'.",
        );
    }

    declare_wayland_interfaces(&home, &quickshell);
    retire_material_you(&home, &autostart, &units);

    if home
        .join(".config")
        .join("caelestia")
        .join("status_icons_order.txt")
        .is_file()
    {
        output::skip(
            "Status icon order file left to the shell, which migrates it into bar.statusIcons.",
        );
    }

    request_window_preview(context, &home, &quickshell);
    output::ok("Autostart entries configured.");
    Ok(())
}

fn find_quickshell() -> Option<PathBuf> {
    for name in ["quickshell", "qs"] {
        if let Some(found) = process::locate(name) {
            return Some(found);
        }
    }
    ["/usr/bin/quickshell", "/usr/local/bin/quickshell"]
        .iter()
        .map(PathBuf::from)
        .find(|candidate| process::is_executable(candidate))
}

fn packaged(home: &Path, units: &Path) {
    let unit = units.join("caelestia-shell.service");
    if unit.is_file() {
        let _ = fs::remove_file(&unit);
        output::info("Removed the user's copy of the shell unit; the package's is the one to use.");
    }

    let launcher = home
        .join(".local")
        .join("bin")
        .join("caelestia-autostart.sh");
    if launcher.is_file() {
        let _ = fs::remove_file(&launcher);
        output::info(
            "Removed the user's copy of the shell launcher; the package's is the one to use.",
        );
    }
}

fn write_launcher(home: &Path, quickshell: &Path, shell_config: &Path, units: &Path) {
    println!("  Creating Caelestia Shell autostart entry...");

    let script = AUTOSTART_TEMPLATE
        .replace(
            "__BIN_DIR__",
            &install_kind::bin_dir().display().to_string(),
        )
        .replace("__QML_IMPORT_PATH__", &install_kind::qml_import_path())
        .replace(
            "__LIB_DIR__",
            &install_kind::lib_dir().display().to_string(),
        )
        .replace("__SHELL_CONFIG__", &shell_config.display().to_string())
        .replace("__QUICKSHELL_PATH__", &quickshell.display().to_string());

    let launcher = home
        .join(".local")
        .join("bin")
        .join("caelestia-autostart.sh");
    let _ = fs::write(&launcher, script);
    paths::make_executable(&launcher);

    println!("  Creating the Caelestia Shell unit...");
    let _ = fs::create_dir_all(units);
    let _ = fs::write(units.join("caelestia-shell.service"), SHELL_UNIT);
}

fn retire_old_autostart(autostart: &Path) {
    let retired = autostart.join("caelestiashell.desktop");
    if !retired.is_file() {
        return;
    }

    let _ = fs::remove_file(&retired);
    let _ = process::succeeds(
        "systemctl",
        &["--user", "disable", "app-caelestiashell@autostart.service"],
        None,
    );
    output::info("Removed the retired autostart entry; the shell's unit replaced it.");
}

fn clear_dangling_enable_links(units: &Path) {
    let Ok(entries) = fs::read_dir(units) else {
        return;
    };

    for entry in entries.filter_map(Result::ok) {
        let wants = entry.path().join("caelestia-shell.service");
        let Ok(metadata) = fs::symlink_metadata(&wants) else {
            continue;
        };
        if !metadata.file_type().is_symlink() || wants.exists() {
            continue;
        }
        let _ = fs::remove_file(&wants);
        output::info("Removed an enable link that named a copy of the shell unit that is gone.");
    }
}

fn declare_wayland_interfaces(home: &Path, quickshell: &Path) {
    println!("  Creating quickshell KDE Wayland interface declaration...");
    let applications = home.join(".local").join("share").join("applications");
    let _ = fs::create_dir_all(&applications);

    let canonical = canonical_path(quickshell);
    let desktop = format!(
        "[Desktop Entry]\nType=Application\nName=Quickshell\nNoDisplay=true\nExec={canonical}\nX-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1,org_kde_plasma_window_management\n"
    );
    let _ = fs::write(applications.join("quickshell.desktop"), desktop);

    let _ = process::succeeds(
        "update-desktop-database",
        &[&applications.display().to_string()],
        None,
    );
    refresh_sycoca();
    output::ok("Quickshell Wayland interface declaration created.");
}

fn canonical_path(path: &Path) -> String {
    fs::canonicalize(path)
        .unwrap_or_else(|_| path.to_path_buf())
        .display()
        .to_string()
}

fn refresh_sycoca() {
    if process::available("kbuildsycoca6") {
        let _ = process::succeeds("kbuildsycoca6", &["--noincremental"], None);
    } else if process::available("kbuildsycoca5") {
        let _ = process::succeeds("kbuildsycoca5", &["--noincremental"], None);
    }
}

fn retire_material_you(home: &Path, autostart: &Path, units: &Path) {
    println!("  Retiring the KDE Material You Colors service...");
    let _ = fs::remove_file(autostart.join("kde-material-you-colors.desktop"));

    let unit = units.join("kde-material-you-colors.service");
    if unit.exists() {
        let _ = process::succeeds(
            "systemctl",
            &[
                "--user",
                "disable",
                "--now",
                "kde-material-you-colors.service",
            ],
            None,
        );
        let _ = fs::remove_file(&unit);
        let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
        output::ok(
            "kde-material-you-colors no longer applies the scheme; its service was removed.",
        );
    } else {
        output::skip("kde-material-you-colors service is not installed.");
    }

    let schemes = home.join(".local").join("share").join("color-schemes");
    if let Ok(entries) = fs::read_dir(&schemes) {
        for entry in entries.filter_map(Result::ok) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("MaterialYou") && name.ends_with(".colors") {
                let _ = fs::remove_file(entry.path());
            }
        }
    }
}

fn request_window_preview(context: &Context, home: &Path, quickshell: &Path) {
    let source = context.bundle.join("assets").join("org.quickshell.desktop");
    if !source.is_file() {
        return;
    }

    println!("  Requesting KWin screencast interface for window previews...");
    let Ok(text) = fs::read_to_string(&source) else {
        return;
    };

    let canonical = canonical_path(quickshell);
    let mut patched = String::new();
    for line in text.lines() {
        if line.starts_with("Exec=") {
            patched.push_str(&format!("Exec={canonical}\n"));
        } else {
            patched.push_str(line);
            patched.push('\n');
        }
    }

    let applications = home.join(".local").join("share").join("applications");
    let _ = fs::create_dir_all(&applications);
    let _ = fs::write(applications.join("org.quickshell.desktop"), patched);
    let _ = process::succeeds("kbuildsycoca6", &[], None);
    println!("  [OK]  Window preview interface requested.");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn launcher(bin: &str, qml: &str, lib: &str, config: &str, quickshell: &str) -> String {
        AUTOSTART_TEMPLATE
            .replace("__BIN_DIR__", bin)
            .replace("__QML_IMPORT_PATH__", qml)
            .replace("__LIB_DIR__", lib)
            .replace("__SHELL_CONFIG__", config)
            .replace("__QUICKSHELL_PATH__", quickshell)
    }

    #[test]
    fn the_launcher_names_this_installs_paths() {
        let script = launcher(
            "/usr/bin",
            "/usr/lib/qt6/qml:/etc/xdg",
            "/usr/lib/caelestia",
            "/etc/xdg/shell.qml",
            "/usr/bin/quickshell",
        );

        assert!(
            script.contains(r#"export PATH="/usr/bin:$PATH""#),
            "{script}"
        );
        assert!(script.contains(r#"export QML2_IMPORT_PATH="/usr/lib/qt6/qml:/etc/xdg""#));
        assert!(script.contains(r#"export CAELESTIA_LIB_DIR="/usr/lib/caelestia""#));
        assert!(
            script.contains(r#"exec "/usr/bin/quickshell" -n -p "/etc/xdg/shell.qml""#),
            "{script}"
        );
        assert!(!script.contains("__"), "every placeholder is filled in");
    }

    #[test]
    fn the_launcher_keeps_the_session_variables_it_is_given() {
        let script = launcher("/bin", "/qml", "/lib", "/shell.qml", "/qs");

        assert!(script.contains(r#""${HYPRLAND_INSTANCE_SIGNATURE:-}""#));
        assert!(script.contains(r#"export QS_DISABLE_CRASH_HANDLER=1"#));
        assert!(
            script.contains("exec "),
            "the shell is the last thing it does"
        );
        assert!(
            !script
                .lines()
                .any(|line| line.trim_start().starts_with("exec ") && line.contains("--daemonize")),
            "the unit supervises the process; detaching would send its output to /dev/null"
        );
    }

    #[test]
    fn the_unit_supervises_the_launcher() {
        assert!(SHELL_UNIT.contains("ExecStart=%h/.local/bin/caelestia-autostart.sh"));
        assert!(SHELL_UNIT.contains("Restart=on-failure"));
        assert!(SHELL_UNIT.contains("RestartSec=5s"));
        assert!(SHELL_UNIT.contains("WantedBy=graphical-session.target"));
    }
}
