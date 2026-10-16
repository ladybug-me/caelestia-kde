//! The uninstall, driven the way a user drives it: a sandboxed home, a PATH of stubs, and the
//! answers piped in. The checks are about what is left on disk afterwards, which is the whole
//! question an uninstall answers.

#![cfg(unix)]

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

mod common;

const BINARY: &str = env!("CARGO_BIN_EXE_caelestia-install");

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct Sandbox {
    root: PathBuf,
    home: PathBuf,
    bin: PathBuf,
    calls: PathBuf,
}

impl Sandbox {
    fn new(label: &str) -> Self {
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "caelestia-uninstall-test-{}-{label}-{unique}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let sandbox = Self {
            home: root.join("home"),
            bin: root.join("bin"),
            calls: root.join("calls.log"),
            root,
        };
        fs::create_dir_all(&sandbox.bin).expect("a directory for the stubs");
        fs::write(&sandbox.calls, "").expect("a call log");

        // Every external tool this flow reaches for answers "nothing to do", which keeps the
        // test away from the machine it runs on.
        for name in [
            "systemctl",
            "pkill",
            "kwriteconfig6",
            "kreadconfig6",
            "kpackagetool6",
            "qdbus6",
            "qdbus",
            "kbuildsycoca6",
            "update-desktop-database",
            "lookandfeeltool",
            "gpasswd",
            "udevadm",
            "pgrep",
            "yay",
            "pacman",
            "dnf",
            "apt-get",
            "rpm",
            "dpkg",
            "fc-cache",
            "update-mime-database",
            "xdg-desktop-menu",
            "uv",
            "chsh",
            "pip3",
        ] {
            sandbox.stub(name, "exit 0");
        }
        sandbox.stub(
            "getent",
            "printf '%s\\n' 'tester:x:1000:1000::/home/tester:/usr/bin/fish'",
        );
        sandbox.stub("groups", "printf '%s\\n' 'tester'");
        sandbox.sudo_stub();

        // The tree the uninstall is pointed at, which is what names the bridge scripts it
        // removes from the user's own bin directory.
        for name in ["caelestia", "caelestia-shell-ipc", "caelestia-update"] {
            let script = sandbox.root.join("src/bin").join(name);
            fs::create_dir_all(script.parent().expect("a parent")).expect("the bundle layout");
            fs::write(script, "#!/bin/sh\n").expect("a bridge script");
        }
        sandbox
    }

    fn stub(&self, name: &str, body: &str) {
        let path = self.bin.join(name);
        fs::write(&path, format!("#!/bin/sh\n{body}\n")).expect("a stub");
        executable(&path);
    }

    // A credential that never asks for one: everything that would be escalated runs for real
    // (the stub hands it back), so the file removals the flow asks for are actually checked.
    fn sudo_stub(&self) {
        let log = self.calls.display();
        self.stub(
            "sudo",
            &format!(
                r#"printf 'sudo %s\n' "$*" >> '{log}'
args=""
for arg in "$@"; do
    case "$arg" in
        -n|-A|-S|-v|--non-interactive) ;;
        -*) ;;
        *) args="$args $arg" ;;
    esac
done
set -- $args
[ $# -gt 0 ] || exit 0
exec "$@""#
            ),
        );
    }

    // The footprint an install leaves in the user's own directories.
    fn install_footprint(self) -> Self {
        for directory in [
            ".config/quickshell/caelestia",
            ".config/caelestia",
            ".config/systemd/user",
            ".config/environment.d",
            ".config/plasma-workspace/env",
            ".local/bin",
            ".local/lib/caelestia",
            ".local/lib/qt6/qml/Caelestia",
            ".local/lib/qt6/qml/M3Shapes",
            ".local/share/caelestia",
            ".local/share/applications",
            ".local/share/kwin/scripts/quickshell-kde-bridge",
            ".cache/caelestia-shell",
            ".local/state/caelestia",
        ] {
            fs::create_dir_all(self.home.join(directory)).expect("a directory of the install");
        }

        for (path, body) in [
            (".config/caelestia/shell.json", "{}\n"),
            (".config/caelestia/stolen-shortcuts.json", "{}\n"),
            (".config/caelestia/stolen-screen-edges.json", "{}\n"),
            (
                ".config/autostart/caelestiashell.desktop",
                "[Desktop Entry]\n",
            ),
            (
                ".local/share/applications/quickshell.desktop",
                "[Desktop Entry]\nX-KDE-Wayland-Interfaces=x\n",
            ),
            (".local/bin/caelestia", "#!/bin/sh\n"),
            (".config/environment.d/caelestia.conf", "# caelestia\n"),
            (".config/plasma-workspace/env/caelestia.sh", "#!/bin/sh\n"),
            (
                ".local/share/kwin/scripts/quickshell-kde-bridge/metadata.json",
                "{\n}\n",
            ),
            (".cache/caelestia-shell/qmlcache", "cache\n"),
        ] {
            let target = self.home.join(path);
            fs::create_dir_all(target.parent().expect("a parent")).expect("a parent directory");
            fs::write(target, body).expect("a file of the install");
        }

        // A config the user shares with the rest of their desktop, which has to survive.
        fs::create_dir_all(self.home.join(".config/btop")).expect("a shared config");
        fs::write(self.home.join(".config/btop/btop.conf"), "mine\n").expect("a shared file");
        self
    }

    fn run(&self, answers: &[&str]) -> (i32, String, String) {
        self.run_with(answers, &[])
    }

    /// The two config tools, so the flow's own reads and writes are exercised against a real
    /// file rather than answered from a fixture.
    fn use_config_tools(&self) -> common::ConfigTools {
        common::config_tools(&self.root, &self.bin)
    }

    fn run_with_config_tools(
        &self,
        answers: &[&str],
        tools: &common::ConfigTools,
    ) -> (i32, String, String) {
        let environment = common::config_tools_environment(tools);
        let borrowed: Vec<(&str, &str)> = environment
            .iter()
            .map(|(name, value)| (name.as_str(), value.as_str()))
            .collect();
        self.run_with(answers, &borrowed)
    }

    fn run_with(&self, answers: &[&str], environment: &[(&str, &str)]) -> (i32, String, String) {
        let mut command = Command::new(BINARY);
        command
            .args([self.root.to_string_lossy().as_ref(), "--uninstall"])
            .env("HOME", &self.home)
            .env("XDG_STATE_HOME", self.home.join(".local/state"))
            .env("XDG_CACHE_HOME", self.home.join(".cache"))
            .env("BASE_DISTRO", "arch")
            .env("CAELESTIA_SUDO_PRIMED", "1")
            .env("CAELESTIA_SUDO_BIN", self.bin.join("sudo"))
            .env("USER", "tester")
            .env("PATH", format!("{}:/usr/bin:/bin", self.bin.display()))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for (name, value) in environment {
            command.env(name, value);
        }

        let mut child = command.spawn().expect("the installer runs");
        if let Some(stdin) = child.stdin.take() {
            let mut stdin = stdin;
            let _ = stdin.write_all(format!("{}\n", answers.join("\n")).as_bytes());
        }

        let output = child.wait_with_output().expect("the installer finishes");
        (
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stdout).to_string(),
            String::from_utf8_lossy(&output.stderr).to_string(),
        )
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn executable(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).expect("an executable");
}

// The confirmation, then "no" to packages and "no" to the cache.
const ANSWERS: [&str; 3] = ["y", "n", "n"];

#[test]
fn the_installed_footprint_is_removed() {
    let sandbox = Sandbox::new("footprint").install_footprint();
    let (status, stdout, stderr) = sandbox.run(&ANSWERS);
    assert_eq!(status, 0, "stdout: {stdout}\nstderr: {stderr}");

    for gone in [
        ".config/quickshell/caelestia",
        ".local/lib/caelestia",
        ".local/lib/qt6/qml/Caelestia",
        ".local/lib/qt6/qml/M3Shapes",
        ".local/share/caelestia",
        ".local/bin/caelestia",
        ".config/environment.d/caelestia.conf",
        ".config/plasma-workspace/env/caelestia.sh",
        ".local/share/kwin/scripts/quickshell-kde-bridge",
        ".cache/caelestia-shell",
        ".local/state/caelestia",
    ] {
        assert!(
            !sandbox.home.join(gone).exists(),
            "{gone} should have been removed"
        );
    }

    // The shell's own settings are the user's, not the install's: they stay.
    assert!(
        sandbox.home.join(".config/caelestia/shell.json").is_file(),
        "the user's shell settings are not the installer's to remove"
    );

    assert!(
        stdout.contains("Caelestia has been uninstalled."),
        "{stdout}"
    );
}

#[test]
fn the_stranded_recovery_files_go_with_it() {
    let sandbox = Sandbox::new("stranded").install_footprint();
    let (status, stdout, _) = sandbox.run(&ANSWERS);
    assert_eq!(status, 0, "{stdout}");

    assert!(
        !sandbox
            .home
            .join(".config/caelestia/stolen-shortcuts.json")
            .exists()
    );
    assert!(
        !sandbox
            .home
            .join(".config/caelestia/stolen-screen-edges.json")
            .exists()
    );
    assert!(
        stdout.contains("Removed stranded recovery file"),
        "{stdout}"
    );
}

#[test]
fn a_shared_config_directory_is_left_where_it_is() {
    let sandbox = Sandbox::new("shared").install_footprint();
    let (status, stdout, _) = sandbox.run(&ANSWERS);
    assert_eq!(status, 0, "{stdout}");

    assert!(
        sandbox.home.join(".config/btop/btop.conf").is_file(),
        "a config the user shares must survive an uninstall with no backup"
    );
    assert!(
        stdout.contains("left in place"),
        "and the run should say so: {stdout}"
    );
}

#[test]
fn an_unrelated_qml_import_path_is_left_alone() {
    let sandbox = Sandbox::new("qml").install_footprint();
    let other = sandbox.home.join(".local/lib/qt6/qml/Other");
    fs::create_dir_all(&other).expect("another module");
    fs::write(other.join("qmldir"), "module Other\n").expect("its own file");

    let (status, stdout, _) = sandbox.run(&ANSWERS);
    assert_eq!(status, 0, "{stdout}");
    assert!(other.join("qmldir").is_file(), "another user's QML module");
}

#[test]
fn the_asking_happens_before_anything_is_removed() {
    let sandbox = Sandbox::new("cancel").install_footprint();
    let (status, _, stderr) = sandbox.run(&["n"]);
    assert_eq!(status, 1);
    assert!(stderr.contains("Uninstall canceled."), "{stderr}");
    assert!(
        sandbox.home.join(".config/caelestia/shell.json").is_file(),
        "the answer comes first"
    );
}

// kwinrulesrc as the installer leaves it: the index it wrote, and the user's own rule sitting
// in the same list.
const RULES: &str = r#"[General]
rules=user-rule,caelestia-opacity,caelestia-dialogs,caelestia-pip
count=4

[user-rule]
Description=Keep this window put
wmclass=keepme
wmclassmatch=1

[caelestia-opacity]
Description=Caelestia: window opacity
types=33

[caelestia-dialogs]
Description=Caelestia: center dialogs
types=32

[caelestia-pip]
Description=Caelestia: pin picture-in-picture
titlematch=3
"#;

// The index holds nothing but our three groups, in the order the installer writes them.
const OUR_RULES: &str = r#"[General]
rules=caelestia-opacity,caelestia-dialogs,caelestia-pip
count=3

[caelestia-opacity]
Description=Caelestia: window opacity
types=33

[caelestia-dialogs]
Description=Caelestia: center dialogs
types=32

[caelestia-pip]
Description=Caelestia: pin picture-in-picture
titlematch=3
"#;

fn ini_value(file: &Path, group: &str, key: &str) -> Option<String> {
    let text = fs::read_to_string(file).ok()?;
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == format!("[{group}]");
            continue;
        }
        if inside && let Some(value) = line.strip_prefix(&format!("{key}=")) {
            return Some(value.to_string());
        }
    }
    None
}

// The list of names is the user's, so deleting one that is not ours would silently disable a
// rule they wrote.
#[test]
fn the_users_own_window_rule_survives_the_uninstall() {
    let sandbox = Sandbox::new("rules").install_footprint();
    let tools = sandbox.use_config_tools();
    let rules = tools.config.join("kwinrulesrc");
    fs::write(&rules, RULES).expect("the rules file");

    let (status, stdout, stderr) = sandbox.run_with_config_tools(&ANSWERS, &tools);
    assert_eq!(status, 0, "stdout: {stdout}\nstderr: {stderr}");
    assert!(
        stdout.contains("Removed the Caelestia window rules from kwinrulesrc"),
        "{stdout}"
    );

    assert_eq!(
        ini_value(&rules, "General", "rules").as_deref(),
        Some("user-rule"),
        "only our names should leave the list"
    );
    assert_eq!(
        ini_value(&rules, "General", "count").as_deref(),
        Some("1"),
        "and the count follows the names that are left"
    );
    assert_eq!(
        ini_value(&rules, "user-rule", "wmclass").as_deref(),
        Some("keepme"),
        "the user's own rule should survive"
    );

    let written = fs::read_to_string(&rules).expect("the rules file");
    assert!(!written.contains("caelestia-"), "{written}");
}

// With no name left the file has to look like it did before the install: an index that names
// nothing, and a count of nothing, are both absent rather than empty.
#[test]
fn the_window_rule_index_goes_when_none_of_ours_are_left() {
    let sandbox = Sandbox::new("rules-only").install_footprint();
    let tools = sandbox.use_config_tools();
    let rules = tools.config.join("kwinrulesrc");
    fs::write(&rules, OUR_RULES).expect("the rules file");

    let (status, stdout, stderr) = sandbox.run_with_config_tools(&ANSWERS, &tools);
    assert_eq!(status, 0, "stdout: {stdout}\nstderr: {stderr}");

    let written = fs::read_to_string(&rules).expect("the rules file");
    assert!(!written.contains("caelestia-"), "{written}");
    assert!(!written.contains("[General]"), "{written}");
    assert!(!written.contains("rules="), "{written}");
    assert!(!written.contains("count="), "{written}");
}
