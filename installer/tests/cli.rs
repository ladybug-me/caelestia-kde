use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

const BINARY: &str = env!("CARGO_BIN_EXE_caelestia-install");
const VERSION_MARKER: &str = include_str!("../data/tui.version");

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct Bundle {
    root: PathBuf,
}

impl Bundle {
    fn new(label: &str) -> Self {
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "caelestia-install-test-{}-{label}-{unique}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("a temporary directory");
        Self { root: path }
    }

    fn path(&self) -> &Path {
        &self.root
    }

    // A step no longer runs a script, but a bundle still owes its scripts/ directory: that is
    // where setup.sh, the update helper and the step libraries are installed from.
    fn with_scripts_dir(self) -> Self {
        fs::create_dir_all(self.root.join("scripts")).expect("a scripts directory");
        self
    }
}

impl Drop for Bundle {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn run(args: &[&str]) -> Output {
    Command::new(BINARY)
        .args(args)
        .output()
        .expect("the installer runs")
}

fn code(output: &Output) -> i32 {
    output.status.code().expect("an exit status, not a signal")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn version_is_the_marker_the_launcher_compares() {
    let output = run(&["--version"]);
    assert_eq!(code(&output), 0);
    assert_eq!(stdout(&output).trim(), VERSION_MARKER.trim());
}

#[test]
fn help_lists_the_exit_codes_and_succeeds() {
    let output = run(&["--help"]);
    assert_eq!(code(&output), 0);
    assert!(
        stdout(&output).contains("Exit codes"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn an_unknown_option_is_a_usage_error() {
    let output = run(&["--bogus"]);
    assert_eq!(code(&output), 2);
    assert!(stderr(&output).contains("--bogus"), "{}", stderr(&output));
}

#[test]
fn help_names_the_flag_that_answers_an_option_without_being_asked() {
    let output = run(&["--help"]);
    assert_eq!(code(&output), 0);
    assert!(
        stdout(&output).contains("--set ID=value"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_set_that_the_menu_cannot_answer_is_refused_before_anything_runs() {
    // Refused at the command line, not silently dropped half way through an install: there is no
    // bundle here, and the usage error still comes first.
    let unknown = run(&["--set", "INSTALL_WIDGET=true"]);
    assert_eq!(code(&unknown), 2, "{}", stderr(&unknown));
    assert!(
        stderr(&unknown).contains("INSTALL_WIDGET"),
        "{}",
        stderr(&unknown)
    );

    let impossible = run(&["--set", "DEFAULT_SHELL=tcsh"]);
    assert_eq!(code(&impossible), 2, "{}", stderr(&impossible));
    assert!(
        stderr(&impossible).contains("fish"),
        "the options it does take: {}",
        stderr(&impossible)
    );

    let shapeless = run(&["--set", "INSTALL_SDDM"]);
    assert_eq!(code(&shapeless), 2, "{}", stderr(&shapeless));
    assert!(
        stderr(&shapeless).contains("ID=value"),
        "{}",
        stderr(&shapeless)
    );
}

#[test]
fn a_bundle_without_step_scripts_is_reported_as_the_environment() {
    let bundle = Bundle::new("bare");
    let output = run(&[&bundle.path().to_string_lossy()]);
    assert_eq!(code(&output), 4);
    assert!(
        stderr(&output).contains("step scripts not found"),
        "{}",
        stderr(&output)
    );
}

#[test]
fn the_wizard_refuses_to_start_without_a_terminal() {
    let bundle = Bundle::new("with-scripts").with_scripts_dir();
    let output = run(&[&bundle.path().to_string_lossy()]);
    assert_eq!(code(&output), 4);
    assert!(
        stderr(&output).contains("needs a terminal"),
        "{}",
        stderr(&output)
    );
}

#[cfg(unix)]
#[test]
fn canceling_the_uninstall_leaves_the_install_alone() {
    use std::io::Write;
    use std::process::Stdio;

    let bundle = Bundle::new("cancel-uninstall").with_scripts_dir();
    let home = bundle.path().join("home");
    let config = home.join(".config/caelestia");
    fs::create_dir_all(&config).expect("a configuration directory");
    fs::write(config.join("shell.json"), "{}\n").expect("a file the uninstall would remove");

    let mut child = Command::new(BINARY)
        .args([bundle.path().to_string_lossy().as_ref(), "--uninstall"])
        .env("HOME", &home)
        .env("BASE_DISTRO", "arch")
        .env("CAELESTIA_SUDO_PRIMED", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the installer runs");
    child
        .stdin
        .take()
        .expect("a pipe to answer on")
        .write_all(b"n\n")
        .expect("the answer");

    let output = child.wait_with_output().expect("the installer finishes");
    assert_eq!(code(&output), 1, "{}", stdout(&output));
    assert!(
        stderr(&output).contains("Uninstall canceled."),
        "{}",
        stderr(&output)
    );
    assert!(
        config.join("shell.json").is_file(),
        "nothing may be removed before the confirmation"
    );
}

#[test]
fn the_phase_trace_only_appears_when_asked_for() {
    let bundle = Bundle::new("trace").with_scripts_dir();
    let path = bundle.path().to_string_lossy().into_owned();

    let quiet = run(&[&path]);
    assert!(
        !stderr(&quiet).contains("[installer]"),
        "{}",
        stderr(&quiet)
    );

    let traced = run(&[&path, "--debug"]);
    assert!(
        stderr(&traced).contains("[installer] bundle dir:"),
        "{}",
        stderr(&traced)
    );
}

#[cfg(unix)]
#[test]
fn an_update_runs_in_the_installer_and_says_what_it_needs() {
    // The update is native now, so what the binary does with --update is its own flow. A
    // bundle whose PATH carries no build tools is the cheapest place to see that: the flow
    // starts, refuses to go on, and names the command it is missing.
    let bundle = Bundle::new("update").with_scripts_dir();
    let path = bundle.path().to_string_lossy().into_owned();
    let empty = bundle.path().join("no-tools");
    fs::create_dir_all(&empty).expect("an empty directory");

    let output = Command::new(BINARY)
        .args([&path, "--update"])
        .env("PATH", &empty)
        .env("XDG_RUNTIME_DIR", bundle.path())
        .output()
        .expect("the installer runs");

    assert_eq!(code(&output), 1, "{}", stderr(&output));
    assert!(
        stdout(&output).contains("Checking dependencies..."),
        "{}",
        stdout(&output)
    );
    assert!(
        stderr(&output).contains("'git' is missing")
            || stderr(&output).contains("'cmake' is missing"),
        "{}",
        stderr(&output)
    );
}

#[cfg(unix)]
#[test]
fn an_uninstall_with_nothing_to_remove_says_so_and_finishes() {
    use std::io::Write;
    use std::process::Stdio;

    // Answering the confirmation, then declining packages and the cache: a machine that never
    // had Caelestia installed should still walk the whole flow and end cleanly.
    let bundle = Bundle::new("empty-uninstall").with_scripts_dir();
    let home = bundle.path().join("home");
    let bin = bundle.path().join("bin");
    fs::create_dir_all(&home).expect("a home");
    fs::create_dir_all(&bin).expect("a directory for the stub");

    // Nothing is on PATH, and the one thing that would ask for root answers yes without doing
    // anything: the flow runs in full without touching the machine it runs on.
    let sudo = bin.join("sudo");
    fs::write(&sudo, "#!/bin/sh\nexit 0\n").expect("a sudo stub");
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&sudo, fs::Permissions::from_mode(0o755)).expect("an executable stub");
    }

    let mut child = Command::new(BINARY)
        .args([bundle.path().to_string_lossy().as_ref(), "--uninstall"])
        .env("HOME", &home)
        .env("BASE_DISTRO", "arch")
        .env("CAELESTIA_SUDO_PRIMED", "1")
        .env("CAELESTIA_SUDO_BIN", &sudo)
        .env("PATH", "/nonexistent")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the installer runs");
    child
        .stdin
        .take()
        .expect("a pipe to answer on")
        .write_all(b"y\nn\n")
        .expect("the answers");

    let output = child.wait_with_output().expect("the installer finishes");
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    assert!(
        stdout(&output).contains("Step 1 - Stop and Disable Services"),
        "{}",
        stdout(&output)
    );
    assert!(
        stdout(&output).contains("Caelestia has been uninstalled."),
        "{}",
        stdout(&output)
    );
}
