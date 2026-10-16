use std::fs;
use std::path::{Path, PathBuf};

#[cfg(unix)]
use std::io::Write;
#[cfg(unix)]
use std::process::Stdio;

use crate::install_kind;
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};

const UINPUT_RULE: &str = "70-uinput.rules";
const LEGACY_UINPUT_RULE: &str = "80-uinput.rules";
#[cfg(unix)]
const UINPUT_RULE_LINE: &str =
    r#"KERNEL=="uinput", MODE="0600", OPTIONS+="static_node=uinput", TAG+="uaccess""#;
const RULES_DIR: &str = "/etc/udev/rules.d";

const WRAPPER: &str = r#"#!/bin/bash
# ydotoold-wrapper  starts ydotoold with uinput access (the active session gets it from the udev rule)
SOCKET="${YDOTOOL_SOCKET:-/run/user/$(id -u)/.ydotool_socket}"
if [ -S "$SOCKET" ] && pidof ydotoold > /dev/null 2>&1; then
    exit 0
fi
exec /usr/bin/ydotoold \
    --socket-path="$SOCKET" \
    --socket-perm=0660
"#;

const UNIT: &str = r#"[Unit]
Description=ydotoold key injection daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/ydotoold-wrapper
Restart=on-failure
Environment=YDOTOOL_SOCKET=/run/user/%U/.ydotool_socket

[Install]
WantedBy=graphical-session.target
"#;

#[cfg(unix)]
const SYSTEM_SCRIPT: &str = r#"TARGET_USER="$1"
UINPUT_RULE="$2"
LEGACY_UINPUT_RULE="$3"
UINPUT_RULE_LINE="$4"
RULE_CHANGED=""

if systemctl is-enabled --quiet keyd.service 2>/dev/null || \
   systemctl is-active --quiet keyd.service 2>/dev/null; then
    echo "  Disabling legacy keyd service..."
    systemctl disable --now keyd.service 2>/dev/null || true
fi

echo "  Setting up ydotoold (OSK key injection daemon)..."

if [ -f "$LEGACY_UINPUT_RULE" ]; then
    rm -f "$LEGACY_UINPUT_RULE"
    RULE_CHANGED=1
    if id -nG "$TARGET_USER" | grep -qw input; then
        if gpasswd -d "$TARGET_USER" input >/dev/null 2>&1; then
            echo "  Removed $TARGET_USER from the 'input' group (takes effect on next login)."
        else
            echo "  Could not remove $TARGET_USER from the 'input' group; run: sudo gpasswd -d $TARGET_USER input"
        fi
    fi
fi

if [ ! -f "$UINPUT_RULE" ]; then
    printf '%s\n' "$UINPUT_RULE_LINE" > "$UINPUT_RULE"
    RULE_CHANGED=1
    echo "  udev rule for uinput created (active session only, no group membership)."
fi

if [ -n "$RULE_CHANGED" ]; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --sysname-match=uinput 2>/dev/null || true
fi

if [ ! -e /dev/uinput ]; then
    echo "  /dev/uinput is not present yet; the on-screen keyboard needs it. Load it with: modprobe uinput"
fi
"#;

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    output::info("Configuring services and KWin");
    println!();

    disable_legacy_bridge();
    clear_legacy_shortcuts();
    let _ = process::succeeds(
        "kwriteconfig6",
        &[
            "--file",
            "kwinrc",
            "--group",
            "Plugins",
            "--key",
            "quickshell-kde-bridgeEnabled",
            "false",
        ],
        None,
    );

    super::ensure_five_desktops(context)?;

    let rules = rules_dir(context);
    if system_setup_needed(&read_system_state(&rules)) {
        println!("  Applying system-level configurations (requires root)...");
        apply_system_level(&rules)?;
    } else if install_kind::is_packaged() {
        output::skip("System-level configuration belongs to the package.");
    } else {
        output::skip("System-level configuration already in place.");
    }

    write_ydotoold(&paths::home())?;
    configure_quick_share(context);

    output::ok("Services configured.");
    Ok(())
}

fn disable_legacy_bridge() {
    let enabled = process::succeeds(
        "systemctl",
        &["--user", "is-enabled", "--quiet", "qs-kwin-bridge.service"],
        None,
    );
    let active = process::succeeds(
        "systemctl",
        &["--user", "is-active", "--quiet", "qs-kwin-bridge.service"],
        None,
    );
    if enabled || active {
        println!("  Disabling legacy qs-kwin-bridge service...");
        let _ = process::succeeds(
            "systemctl",
            &["--user", "disable", "--now", "qs-kwin-bridge.service"],
            None,
        );
    }
}

fn clear_legacy_shortcuts() {
    println!("  Clearing legacy KWin workspace shortcuts to avoid QML conflicts...");
    for index in 1..=10 {
        for (key, value) in [
            (
                format!("Switch to Desktop {index}"),
                format!("none,none,Switch to Desktop {index}"),
            ),
            (
                format!("Window to Desktop {index}"),
                format!("none,none,Move Window to Desktop {index}"),
            ),
        ] {
            let _ = process::succeeds(
                "kwriteconfig6",
                &[
                    "--file",
                    "kglobalshortcutsrc",
                    "--group",
                    "kwin",
                    "--key",
                    &key,
                    &value,
                ],
                None,
            );
        }
    }
}

struct SystemState {
    packaged: bool,
    keyd: bool,
    rule: bool,
    legacy_rule: bool,
}

fn read_system_state(rules: &Path) -> SystemState {
    let keyd = process::succeeds(
        "systemctl",
        &["is-enabled", "--quiet", "keyd.service"],
        None,
    ) || process::succeeds("systemctl", &["is-active", "--quiet", "keyd.service"], None);

    SystemState {
        packaged: install_kind::is_packaged(),
        keyd,
        rule: rule_is_current(&rules.join(UINPUT_RULE)),
        legacy_rule: rules.join(LEGACY_UINPUT_RULE).exists(),
    }
}

fn system_setup_needed(state: &SystemState) -> bool {
    if state.packaged {
        return false;
    }
    state.keyd || !state.rule || state.legacy_rule
}

fn rule_is_current(rule: &Path) -> bool {
    fs::read_to_string(rule)
        .map(|contents| contents.contains(r#"TAG+="uaccess""#))
        .unwrap_or(false)
}

fn rules_dir(context: &Context) -> PathBuf {
    // The system directory is the one that matters; a test points this at a tree it owns,
    // because the branch below writes to it.
    context
        .variable("CAELESTIA_UDEV_RULES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(RULES_DIR))
}

#[cfg(unix)]
fn apply_system_level(rules: &Path) -> Result<(), Failure> {
    let user = process::capture("id", &["-un"]).unwrap_or_default();
    let rule = rules.join(UINPUT_RULE);
    let legacy = rules.join(LEGACY_UINPUT_RULE);
    let arguments = [
        "-s",
        "--",
        user.as_str(),
        &rule.to_string_lossy(),
        &legacy.to_string_lossy(),
        UINPUT_RULE_LINE,
    ];

    let mut command = privileges::elevated_command("bash", &arguments, None)?;
    command.stdin(Stdio::piped());
    let mut child = command
        .spawn()
        .map_err(|error| format!("could not run the system setup: {error}"))?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(SYSTEM_SCRIPT.as_bytes())
            .map_err(|error| format!("could not hand the system setup its script: {error}"))?;
    }

    let status = child
        .wait()
        .map_err(|error| format!("the system setup did not finish: {error}"))?;
    if !status.success() {
        return Err(format!(
            "the system-level configuration failed with status {}",
            status.code().unwrap_or(1)
        )
        .into());
    }
    Ok(())
}

#[cfg(not(unix))]
fn apply_system_level(_rules: &Path) -> Result<(), Failure> {
    Err("the system-level configuration needs Linux".into())
}

fn write_ydotoold(home: &Path) -> Result<(), Failure> {
    let bin = home.join(".local").join("bin");
    fs::create_dir_all(&bin).map_err(|error| format!("cannot use {}: {error}", bin.display()))?;
    let wrapper = bin.join("ydotoold-wrapper");
    fs::write(&wrapper, WRAPPER)
        .map_err(|error| format!("cannot write {}: {error}", wrapper.display()))?;
    paths::make_executable(&wrapper);
    output::ok("ydotoold-wrapper deployed to ~/.local/bin.");

    let units = home.join(".config").join("systemd").join("user");
    fs::create_dir_all(&units)
        .map_err(|error| format!("cannot use {}: {error}", units.display()))?;
    let unit = units.join("ydotoold.service");
    fs::write(&unit, UNIT).map_err(|error| format!("cannot write {}: {error}", unit.display()))?;

    let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
    let _ = process::succeeds("systemctl", &["--user", "enable", "ydotoold.service"], None);
    if process::succeeds("systemctl", &["--user", "start", "ydotoold.service"], None) {
        output::ok("ydotoold started.");
    } else {
        output::info("ydotoold will start on next login.");
    }
    output::ok("ydotoold service configured.");
    Ok(())
}

// The listener the plugin build binds and the rule that opens it read the same manifest, so
// the port is read here rather than stated a second time.
fn configure_quick_share(context: &Context) {
    if install_kind::is_packaged() {
        output::skip("Quick Share's setup is the shell's own prompt on a packaged install.");
        return;
    }

    let setup = context
        .bundle
        .join("shell")
        .join("scripts")
        .join("quickshare_setup.sh");
    let port_file = context
        .bundle
        .join("shell")
        .join("scripts")
        .join("quickshare-port");

    if !setup.is_file() {
        output::warn(&format!(
            "Quick Share's setup helper is missing from {}; it may not be able to receive.",
            setup.display()
        ));
        return;
    }

    let Some(port) = fs::read_to_string(&port_file)
        .ok()
        .map(|port| port.trim().to_string())
    else {
        output::warn(&format!(
            "Quick Share's transfer port is missing from {}; it may not be able to receive.",
            port_file.display()
        ));
        return;
    };

    if port.is_empty() || !port.chars().all(|digit| digit.is_ascii_digit()) {
        output::warn(&format!(
            "Quick Share's transfer port in {} is not a port number; it may not be able to receive.",
            port_file.display()
        ));
        return;
    }

    let setup = setup.to_string_lossy().to_string();
    let status =
        process::capture("bash", &[&setup, "--status", "--port", &port]).unwrap_or_default();
    if !status.contains("SETUP=needed") {
        output::skip("Quick Share already has the access it needs.");
        return;
    }

    match privileges::elevated("bash", &[&setup, "--port", &port], None) {
        Ok(0) => output::ok(&format!(
            "Quick Share can receive: Avahi is running and port {port} is open."
        )),
        _ => output::warn(
            "Quick Share setup did not finish; retry from Settings -> Services -> Quick Share.",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state(packaged: bool, keyd: bool, rule: bool, legacy_rule: bool) -> SystemState {
        SystemState {
            packaged,
            keyd,
            rule,
            legacy_rule,
        }
    }

    #[test]
    fn a_packaged_install_never_touches_the_system() {
        assert!(!system_setup_needed(&state(true, true, false, true)));
        assert!(!system_setup_needed(&state(true, false, false, false)));
    }

    #[test]
    fn a_machine_that_already_has_the_rule_is_left_alone() {
        assert!(!system_setup_needed(&state(false, false, true, false)));
    }

    #[test]
    fn a_missing_rule_an_old_rule_or_keyd_still_needs_the_system_step() {
        assert!(system_setup_needed(&state(false, false, false, false)));
        assert!(system_setup_needed(&state(false, false, true, true)));
        assert!(system_setup_needed(&state(false, true, true, false)));
    }

    #[cfg(unix)]
    #[test]
    fn only_a_rule_that_grants_uaccess_counts_as_current() {
        let work = crate::tmp::TempDir::new("caelestia-services-test").expect("a directory");

        assert!(!rule_is_current(&work.path().join(UINPUT_RULE)));

        fs::write(work.path().join(UINPUT_RULE), UINPUT_RULE_LINE).expect("the rule");
        assert!(rule_is_current(&work.path().join(UINPUT_RULE)));

        fs::write(
            work.path().join(UINPUT_RULE),
            r#"KERNEL=="uinput", MODE="0600""#,
        )
        .expect("the rule");
        assert!(!rule_is_current(&work.path().join(UINPUT_RULE)));
    }
}
