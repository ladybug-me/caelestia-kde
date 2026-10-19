use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use crate::install_kind;
use crate::output;
use crate::paths;
use crate::process;
use crate::report::{Report, Row};
use crate::steps::{self, Context, Failure};
use crate::theme::Role;
use crate::update_state;

const ANSWERS: &str = ".config/caelestia-kde/install.env";

const LOCK: &str = "caelestia-update.lock";

const CHANNELS: [&str; 2] = ["main", "dev"];
const DEFAULT_CHANNEL: &str = "main";

/// What an update rebuilds, in order, with what the user is told before each one and whether a
/// failure stops the update. The policy is the table; the loop below only carries it out.
struct Repair {
    id: &'static str,
    announce: &'static str,
    required: bool,
}

const STEPS: [Repair; 3] = [
    Repair {
        id: "03-deploy-configs",
        announce: "",
        required: true,
    },
    Repair {
        id: "08-build-shell",
        announce: "Building the Caelestia shell UI...",
        required: true,
    },
    Repair {
        id: "09-system-tweaks",
        announce: "Re-applying system tweaks...",
        required: false,
    },
];

/// The steps an update runs, for the shell updater that used to keep its own copy of the list.
pub fn step_ids() -> Vec<&'static str> {
    STEPS.iter().map(|repair| repair.id).collect()
}

pub fn run(bundle: &Path, requested: Option<String>) -> Result<(), Failure> {
    let Some(_lock) = take_lock()? else {
        return Err("Another Caelestia update is already running.".into());
    };

    let report = Report::for_terminal();
    let channel = choose_channel(bundle, requested);
    let installed = update_state::installed(&config_dir()).or_else(|| published_version(bundle));
    let available = available(bundle, &channel);
    report.panel("update", &channel, &revision_rows(&installed, &available), &[
        "The deployed configuration is replaced, the shell is rebuilt and the system tweaks are \
         applied again. Your own settings are kept."
            .to_string(),
        "Packages are not touched: those come from your package manager."
            .to_string(),
    ]);

    if let (Some(installed), Some(available)) = (&installed, &available)
        && installed.commit == available.1
        && installed.commit.len() >= 7
    {
        report.panel(
            "update",
            "nothing to do",
            &[Row::new(
                "installed",
                format!(
                    "{} \u{00b7} {} \u{00b7} latest",
                    installed.version,
                    short(&installed.commit)
                ),
                Role::Ok,
            )],
            &[format!(
                "{} is the newest revision on {channel}.",
                installed.version
            )],
        );
        return Ok(());
    }

    report.section("Fetching the source");
    check_dependencies()?;
    update_checkout(bundle, &channel)?;

    report.section("Rebuilding what the update changed");
    load_answers(&paths::home());

    for repair in &STEPS {
        if !repair.announce.is_empty() {
            output::info(repair.announce);
        }
        if let Err(problem) = run_step(bundle, repair.id) {
            if repair.required {
                return Err(problem);
            }
            output::warn(&format!("{} reported errors (non-fatal).", repair.id));
        }
    }

    let now = update_state::installed(&config_dir());
    report.panel(
        "update",
        "done",
        &revision_rows(&now, &available),
        &[
            "The shell and bridges are rebuilt, and the system tweaks are back in sync."
                .to_string(),
            "Restarting the shell to pick them up.".to_string(),
        ],
    );
    restart_shell();
    Ok(())
}

pub fn published_version(bundle: &Path) -> Option<update_state::Installed> {
    let published = std::fs::read_to_string(bundle.join(".github").join("version.env")).ok()?;
    Some(update_state::Installed {
        version: version_of(&published),
        commit: String::new(),
        branch: String::new(),
    })
}

pub fn config_dir() -> PathBuf {
    install_kind::shell_config_dir()
}

fn revision_rows(
    installed: &Option<update_state::Installed>,
    available: &Option<(String, String)>,
) -> Vec<Row> {
    let installed = match installed {
        Some(installed) => {
            let mut value = installed.version.clone();
            if !installed.commit.is_empty() {
                value.push_str(&format!(" \u{00b7} {}", short(&installed.commit)));
            }
            if !installed.branch.is_empty() {
                value.push_str(&format!(" \u{00b7} {}", installed.branch));
            }
            Row::new("installed", value, Role::Foreground)
        }
        None => Row::new("installed", "version not recorded", Role::Muted),
    };
    let available = match available {
        Some((version, commit)) => Row::new(
            "available",
            format!("{version} \u{00b7} {}", short(commit)),
            Role::Ok,
        ),
        None => Row::new(
            "available",
            "not a git checkout: update comes from the package or the release",
            Role::Muted,
        ),
    };
    vec![installed, available]
}

fn short(commit: &str) -> String {
    commit.chars().take(7).collect()
}

fn available(bundle: &Path, channel: &str) -> Option<(String, String)> {
    if !bundle.join(".git").is_dir() {
        return None;
    }
    if !process::succeeds(
        "git",
        &["fetch", "--quiet", "origin", channel],
        Some(bundle),
    ) {
        return None;
    }
    let commit = process::capture_in(
        "git",
        &["rev-parse", &format!("origin/{channel}")],
        Some(bundle),
    )?;
    let published = process::capture_in(
        "git",
        &["show", &format!("origin/{channel}:.github/version.env")],
        Some(bundle),
    )?;
    Some((version_of(&published), commit))
}

fn version_of(published: &str) -> String {
    published
        .lines()
        .find_map(|line| line.trim().strip_prefix("VERSION="))
        .map(|version| version.trim().to_string())
        .unwrap_or_else(|| "unknown version".to_string())
}

fn take_lock() -> Result<Option<std::fs::File>, Failure> {
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "/tmp".to_string());
    let path = PathBuf::from(runtime).join(LOCK);

    let Ok(file) = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&path)
    else {
        return Err(format!("Could not open {} to take the update lock.", path.display()).into());
    };

    if try_lock(&file) {
        Ok(Some(file))
    } else {
        Ok(None)
    }
}

#[cfg(unix)]
fn try_lock(file: &std::fs::File) -> bool {
    use std::os::unix::io::AsRawFd;

    // SAFETY: flock only reads the file descriptor, which the File owns for as long as this
    // process runs.
    unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) == 0 }
}

#[cfg(not(unix))]
fn try_lock(_file: &std::fs::File) -> bool {
    true
}

fn check_dependencies() -> Result<(), Failure> {
    output::info("Checking dependencies...");
    for command in ["git", "cmake", "make"] {
        if !process::available(command) {
            return Err(format!(
                "Required command '{command}' is missing. Please install it first."
            )
            .into());
        }
    }
    Ok(())
}

fn update_checkout(bundle: &Path, channel: &str) -> Result<(), Failure> {
    if !bundle.join(".git").is_dir() {
        output::warn("Not a git repository. Skipping source code update.");
        return Ok(());
    }

    output::info("Fetching remote branches...");
    if !process::succeeds("git", &["fetch", "origin"], Some(bundle)) {
        output::warn("Failed to fetch from origin. Network issue?");
    }

    let stashed = if process::succeeds(
        "git",
        &["diff-index", "--quiet", "HEAD", "--"],
        Some(bundle),
    ) {
        false
    } else {
        output::warn("You have uncommitted changes in the repository.");
        output::info("Stashing your local changes...");
        if !process::succeeds(
            "git",
            &["stash", "-m", "Auto-stash before Caelestia update"],
            Some(bundle),
        ) {
            return Err("Failed to stash changes.".into());
        }
        true
    };

    output::info(&format!("Checking out {channel}..."));
    if !process::succeeds("git", &["checkout", channel], Some(bundle)) {
        return Err(format!("Failed to checkout {channel}").into());
    }

    output::info(&format!("Pulling latest changes for {channel}..."));
    if !process::succeeds("git", &["pull", "origin", channel], Some(bundle)) {
        return Err(format!("Failed to pull from origin/{channel}").into());
    }

    run_step(bundle, "02a-submodules")?;

    if stashed {
        println!();
        output::warn(
            "Your local uncommitted changes were backed up to the git stash to allow a clean update.",
        );
        output::warn("If you need to recover them, you can manually run 'git stash pop' later.");
    }
    Ok(())
}

fn choose_channel(bundle: &Path, requested: Option<String>) -> String {
    if !bundle.join(".git").is_dir() {
        return DEFAULT_CHANNEL.to_string();
    }
    let mut channel = match requested {
        Some(requested) => {
            output::info(&format!("Using provided branch: {requested}"));
            requested
        }
        None => match ask_for_channel() {
            Some(chosen) => chosen,
            None => {
                let current = process::capture_in(
                    "git",
                    &["rev-parse", "--abbrev-ref", "HEAD"],
                    Some(bundle),
                )
                .unwrap_or_default();
                if current.is_empty() || current == "HEAD" {
                    DEFAULT_CHANNEL.to_string()
                } else {
                    output::info(&format!("Auto-detected branch: {current} (GUI Mode)"));
                    current
                }
            }
        },
    };

    if !CHANNELS.contains(&channel.as_str()) {
        output::warn(&format!(
            "Branch '{channel}' is not allowed. Falling back to {DEFAULT_CHANNEL}."
        ));
        channel = DEFAULT_CHANNEL.to_string();
    } else if !remote_has(bundle, &channel) {
        output::warn(&format!(
            "Remote branch '{channel}' not found. Falling back to {DEFAULT_CHANNEL}."
        ));
        channel = DEFAULT_CHANNEL.to_string();
    }

    channel
}

fn remote_has(bundle: &Path, channel: &str) -> bool {
    process::succeeds(
        "git",
        &["ls-remote", "--exit-code", "--heads", "origin", channel],
        Some(bundle),
    )
}

fn ask_for_channel() -> Option<String> {
    if !std::io::stdout().is_terminal() || !std::io::stdin().is_terminal() {
        return None;
    }

    println!();
    output::info("Available remote branches (default: main):");
    println!("1) main");
    println!("2) dev");

    let mut answer = String::new();
    if std::io::stdin().read_line(&mut answer).is_err() {
        return None;
    }

    match answer.trim() {
        "" => Some(DEFAULT_CHANNEL.to_string()),
        "1" => Some("main".to_string()),
        "2" => Some("dev".to_string()),
        other => {
            output::warn(&format!(
                "'{other}' is not a selection. Please enter a valid number or press Enter for main."
            ));
            Some(DEFAULT_CHANNEL.to_string())
        }
    }
}

fn load_answers(home: &Path) {
    let file = home.join(ANSWERS);
    let Ok(text) = std::fs::read_to_string(&file) else {
        return;
    };

    for (name, value) in parse_answers(&text) {
        // SAFETY: the update is single-threaded here - nothing else is running in this process
        // while the steps read these back through the environment.
        unsafe { std::env::set_var(name, value) };
    }
}

fn parse_answers(text: &str) -> Vec<(String, String)> {
    let mut answers = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((name, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim().trim_matches(['"', '\'']);
        answers.push((name.trim().to_string(), value.to_string()));
    }
    answers
}

fn run_step(bundle: &Path, id: &str) -> Result<(), Failure> {
    let Some(step) = steps::find(id) else {
        return Err(format!("no step is called '{id}'").into());
    };

    let context = Context {
        bundle: bundle.to_path_buf(),
    };
    if steps::run(step, &context) == 0 {
        return Ok(());
    }
    Err(format!("the {id} step failed").into())
}

fn restart_shell() {
    stop_shell();
    start_shell();

    let scheme = paths::state_dir().join("caelestia").join("scheme.json");
    if !wait_for_nonempty_file(&scheme, Duration::from_secs(15)) {
        output::warn(&format!(
            "The restarted shell has not written {} yet; the lock screen may fall back to its default colors.",
            scheme.display()
        ));
    }

    println!("Shell restarted successfully!");
    println!();
    println!("If the shell doesn't start, restart it with the same wrapper the shell uses:");
    println!("  bash \"$HOME/.config/quickshell/caelestia/scripts/restart_shell.sh\"");
    println!("Check logs by running: caelestia shell -l");
}

fn stop_shell() {
    if process::succeeds("caelestia", &["shell", "-k"], None) {
        return;
    }

    let ipc = bin_dir().join("caelestia-shell-ipc");
    if process::is_executable(&ipc) && process::succeeds(&ipc.to_string_lossy(), &["quit"], None) {
        return;
    }

    let _ = process::succeeds("pkill", &["-f", "quickshell.*caelestia/shell.qml"], None);
}

fn start_shell() {
    let ipc = bin_dir().join("caelestia-shell-ipc");
    let restart = install_kind::shell_config()
        .parent()
        .map(|config| config.join("scripts").join("restart_shell.sh"));

    if let Some(restart) = &restart
        && process::is_executable(restart)
        && process::run_visible("bash", &[&restart.to_string_lossy()], None) == Some(0)
    {
        return;
    }

    if process::is_executable(&ipc) {
        let _ = std::process::Command::new(&ipc)
            .arg("start")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
        return;
    }

    let quickshell = process::locate("quickshell")
        .or_else(|| process::locate("qs"))
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|| "quickshell".to_string());
    let shell_config = install_kind::shell_config();
    let environment = [
        ("QML2_IMPORT_PATH", install_kind::qml_import_path()),
        (
            "CAELESTIA_LIB_DIR",
            install_kind::lib_dir().to_string_lossy().to_string(),
        ),
        ("QS_NO_RELOAD_POPUP", "1".to_string()),
        ("QS_DROP_EXPENSIVE_FONTS", "1".to_string()),
        ("QS_DISABLE_CRASH_HANDLER", "1".to_string()),
        ("QSG_RENDER_LOOP", "threaded".to_string()),
        ("QT_QUICK_FLICKABLE_WHEEL_DECELERATION", "10000".to_string()),
    ];

    if process::available("systemd-run") {
        let mut command = std::process::Command::new("systemd-run");
        command.args([
            "--user",
            "--quiet",
            "--collect",
            "--unit=caelestia-shell",
            "--description=Caelestia Shell",
        ]);
        for (name, value) in &environment {
            command.arg(format!("--setenv={name}={value}"));
        }
        command
            .arg("--")
            .arg(&quickshell)
            .arg("-n")
            .arg("-p")
            .arg(&shell_config)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        if command.spawn().is_ok() {
            return;
        }
    }

    let mut command = std::process::Command::new(&quickshell);
    for (name, value) in &environment {
        command.env(name, value);
    }
    let _ = command
        .arg("-n")
        .arg("-p")
        .arg(&shell_config)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

fn bin_dir() -> PathBuf {
    install_kind::bin_dir()
}

pub fn wait_for_nonempty_file(path: &Path, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    loop {
        if std::fs::metadata(path).is_ok_and(|meta| meta.len() > 0) {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn the_answers_an_install_recorded_are_read_back_as_pairs() {
        let answers = parse_answers(
            "\
# chosen at install time
INSTALL_FISH=false
INSTALL_DARKLY=true

APPLY_LOCKSCREEN=\"false\"
not an assignment
",
        );

        assert_eq!(
            answers,
            [
                ("INSTALL_FISH".to_string(), "false".to_string()),
                ("INSTALL_DARKLY".to_string(), "true".to_string()),
                ("APPLY_LOCKSCREEN".to_string(), "false".to_string()),
            ]
        );
    }

    #[test]
    fn a_file_that_is_not_answers_is_read_as_none() {
        assert_eq!(parse_answers(""), Vec::<(String, String)>::new());
        assert_eq!(
            parse_answers("# only a comment"),
            Vec::<(String, String)>::new()
        );
    }

    #[test]
    fn a_wait_that_is_already_satisfied_returns_at_once() {
        let work = TempDir::new("caelestia-update-test").expect("a temporary directory");
        let file = work.path().join("scheme.json");
        std::fs::write(&file, b"{}").expect("a file");
        assert!(wait_for_nonempty_file(&file, Duration::from_secs(1)));
    }

    #[test]
    fn a_wait_for_a_file_nothing_writes_gives_up() {
        let work = TempDir::new("caelestia-update-test").expect("a temporary directory");
        let file = work.path().join("absent.json");
        std::fs::write(&file, b"").expect("an empty file");
        assert!(!wait_for_nonempty_file(&file, Duration::from_millis(150)));
    }

    #[test]
    fn the_channels_an_update_follows_are_the_two_it_offers() {
        assert_eq!(CHANNELS, ["main", "dev"]);
        assert!(CHANNELS.contains(&DEFAULT_CHANNEL));
    }

    #[test]
    fn the_steps_an_update_runs_are_the_ones_the_table_names() {
        assert_eq!(
            STEPS.map(|repair| repair.id),
            ["03-deploy-configs", "08-build-shell", "09-system-tweaks"]
        );
        for repair in &STEPS {
            let id = repair.id;
            assert!(steps::find(id).is_some(), "{id} is not a step");
            assert_eq!(
                repair.required,
                id != "09-system-tweaks",
                "{id}: only the tweaks step may fail without stopping the update"
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn only_one_update_can_hold_the_lock_at_a_time() {
        let Some(first) = take_lock().expect("the lock file can be opened") else {
            return;
        };
        assert!(take_lock().expect("the lock file can be opened").is_none());
        drop(first);
        assert!(take_lock().expect("the lock file can be opened").is_some());
    }
}
