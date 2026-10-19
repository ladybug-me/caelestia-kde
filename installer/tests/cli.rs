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

fn run_with(args: &[&str], env: &[(&str, &str)]) -> Output {
    let mut command = Command::new(BINARY);
    command.args(args);
    for (key, value) in env {
        command.env(key, value);
    }
    command.output().expect("the installer runs")
}

fn is_root() -> bool {
    Command::new("id")
        .arg("-u")
        .output()
        .map(|out| String::from_utf8_lossy(&out.stdout).trim() == "0")
        .unwrap_or(false)
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

    let shapeless = run(&["--set", "SYNC_LOGIN_SCREEN"]);
    assert_eq!(code(&shapeless), 2, "{}", stderr(&shapeless));
    assert!(
        stderr(&shapeless).contains("ID=value"),
        "{}",
        stderr(&shapeless)
    );
}

#[test]
fn the_wizard_refuses_to_start_without_a_terminal() {
    let bundle = Bundle::new("bare");
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

    let bundle = Bundle::new("cancel-uninstall");
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
    let bundle = Bundle::new("trace");
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
    let bundle = Bundle::new("update");
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

    let bundle = Bundle::new("empty-uninstall");
    let home = bundle.path().join("home");
    let bin = bundle.path().join("bin");
    fs::create_dir_all(&home).expect("a home");
    fs::create_dir_all(&bin).expect("a directory for the stub");

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
        stdout(&output).contains("the shell, its configs and its integrations"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_plan_prints_the_steps_and_stops_before_running_them() {
    let bundle = Bundle::new("plan");
    let path = bundle.path().to_str().expect("a utf-8 path");
    let output = run(&["--plan", path]);

    assert_eq!(code(&output), 0);
    let text = stdout(&output);
    assert!(text.contains("steps would run"), "{text}");
    assert!(text.contains("00a-system-update"), "{text}");
}

#[test]
fn a_dry_run_is_the_same_thing_as_a_plan() {
    let bundle = Bundle::new("dry-run");
    let path = bundle.path().to_str().expect("a utf-8 path");

    assert_eq!(
        stdout(&run(&["--dry-run", path])),
        stdout(&run(&["--plan", path]))
    );
}

#[test]
fn a_plan_takes_the_answers_it_is_given() {
    let bundle = Bundle::new("plan-set");
    let path = bundle.path().to_str().expect("a utf-8 path");
    let output = run(&["--plan", "--set", "SKIP_SYSTEM_UPDATE=true", path]);

    assert_eq!(code(&output), 0);
    let text = stdout(&output);
    assert!(text.contains("skip  00a-system-update"), "{text}");
    assert!(!text.contains("nothing switched off"), "{text}");
}

#[test]
fn the_plan_can_be_read_by_a_machine() {
    let bundle = Bundle::new("plan-json");
    let path = bundle.path().to_str().expect("a utf-8 path");
    let output = run(&["--plan", "--json", path]);

    assert_eq!(code(&output), 0);
    let text = stdout(&output);
    assert!(text.trim_start().starts_with('{'), "{text}");
    assert!(text.contains("\"steps_total\""), "{text}");
    assert!(text.contains("\"phase\":\"prepare\""), "{text}");
}

#[test]
fn the_step_lists_are_asked_of_the_installer() {
    let everything = run(&["steps"]);
    assert_eq!(code(&everything), 0, "{}", stderr(&everything));
    assert_eq!(stdout(&everything).lines().count(), 17);
    assert!(stdout(&everything).starts_with("00a-system-update\n"));

    let packaged = run(&["steps", "--for", "packaged"]);
    assert_eq!(code(&packaged), 0, "{}", stderr(&packaged));
    let listed = stdout(&packaged);
    let ids: Vec<&str> = listed.lines().collect();
    assert_eq!(ids.len(), 9, "{listed}");
    assert_eq!(ids.first(), Some(&"03-deploy-configs"));
    assert_eq!(ids.last(), Some(&"10-autostart"));

    let update = run(&["steps", "--for", "update"]);
    assert_eq!(
        stdout(&update).lines().collect::<Vec<_>>(),
        ["03-deploy-configs", "08-build-shell", "09-system-tweaks"]
    );
    let wrong = run(&["steps", "--for", "nonsense"]);
    assert_eq!(code(&wrong), 2, "{}", stderr(&wrong));
    assert!(
        stderr(&wrong).contains("install, packaged or update"),
        "{}",
        stderr(&wrong)
    );
}

#[test]
fn flags_that_cannot_mean_anything_are_refused_rather_than_ignored() {
    let json_alone = run(&["--json"]);
    assert_eq!(code(&json_alone), 2, "{}", stderr(&json_alone));
    assert!(
        stderr(&json_alone).contains("--plan"),
        "{}",
        stderr(&json_alone)
    );

    let plan_with_update = run(&["--plan", "--update"]);
    assert_eq!(code(&plan_with_update), 2, "{}", stderr(&plan_with_update));
}

#[test]
fn an_unattended_run_without_root_says_so_and_stops() {
    if is_root() {
        return;
    }

    let bundle = Bundle::new("yes");
    let path = bundle.path().to_str().expect("a utf-8 path");
    let output = run_with(
        &["--non-interactive", path],
        &[("CAELESTIA_SUDO_BIN", "/nonexistent/sudo")],
    );

    assert_eq!(code(&output), 4, "{}", stderr(&output));
    assert!(stderr(&output).contains("sudo -v"), "{}", stderr(&output));
}

#[test]
fn an_unattended_run_refuses_the_flags_that_only_mean_something_to_the_wizard() {
    for args in [
        vec!["--non-interactive", "--plan"],
        vec!["--non-interactive", "--dark"],
        vec!["--non-interactive", "--update"],
        vec!["--resume"],
    ] {
        let output = run(&args);
        assert_eq!(
            code(&output),
            2,
            "{args:?} should be refused: {}",
            stderr(&output)
        );
    }
}

#[test]
fn the_entry_points_bundle_flag_is_understood_by_the_main_run() {
    let bundle = Bundle::new("bundle-flag");
    let path = bundle.path().to_str().expect("a utf-8 path");

    let plan = run(&["--plan", "--bundle", path]);
    assert_eq!(code(&plan), 0, "{}", stderr(&plan));
    assert!(
        stdout(&plan).contains("steps would run"),
        "{}",
        stdout(&plan)
    );
}

#[test]
fn a_bundle_flag_with_no_directory_is_refused() {
    let output = run(&["--bundle"]);
    assert_eq!(code(&output), 2);
    assert!(stderr(&output).contains("--bundle"), "{}", stderr(&output));
}
