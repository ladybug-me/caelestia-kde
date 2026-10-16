use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn available(program: &str) -> bool {
    locate(program).is_some()
}

pub fn locate(program: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(program);
        if is_executable(&candidate) {
            return Some(candidate);
        }
        #[cfg(windows)]
        for extension in windows_extensions() {
            let candidate = directory.join(format!("{program}{extension}"));
            if is_executable(&candidate) {
                return Some(candidate);
            }
        }
    }
    None
}

pub fn succeeds(program: &str, args: &[&str], directory: Option<&Path>) -> bool {
    command(program, args, directory)
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

pub fn status(program: &str, args: &[&str], directory: Option<&Path>) -> Option<i32> {
    let mut command = Command::new(program);
    command.args(args).stdin(Stdio::null());
    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    command.status().ok().and_then(|status| status.code())
}

// `timeout <seconds> <program>`: a program that hangs must not hold a step open, so it is
// killed once the deadline passes and reported as having produced no status.
pub fn status_with_timeout(program: &str, args: &[&str], seconds: u64) -> Option<i32> {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(seconds);
    let mut child = command(program, args, None).spawn().ok()?;

    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.code(),
            Ok(None) => {
                if std::time::Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return None;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(_) => return None,
        }
    }
}

pub fn status_quietly(program: &str, args: &[&str], directory: Option<&Path>) -> Option<i32> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null());
    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    command.status().ok().and_then(|status| status.code())
}

// A package manager or a source build prints progress the user is watching, so this one
// leaves the child's own output where it lands. stdin stays closed either way: nothing here
// may block on a prompt.
pub fn run_visible(program: &str, args: &[&str], directory: Option<&Path>) -> Option<i32> {
    let mut command = Command::new(program);
    command.args(args).stdin(Stdio::null());
    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    command.status().ok().and_then(|status| status.code())
}

pub fn capture(program: &str, args: &[&str]) -> Option<String> {
    capture_in(program, args, None)
}

pub fn capture_in(program: &str, args: &[&str], directory: Option<&Path>) -> Option<String> {
    let output = command(program, args, directory)
        .stdout(Stdio::piped())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn command(program: &str, args: &[&str], directory: Option<&Path>) -> Command {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    command
}

#[cfg(unix)]
pub fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;

    path.is_file()
        && path
            .metadata()
            .map(|meta| meta.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

#[cfg(not(unix))]
pub fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(windows)]
fn windows_extensions() -> Vec<String> {
    std::env::var("PATHEXT")
        .unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".to_string())
        .split(';')
        .filter(|extension| !extension.is_empty())
        .map(|extension| extension.to_lowercase())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_program_that_is_running_is_located_on_the_path() {
        assert!(locate("cargo").is_some(), "cargo runs this test");
    }

    #[test]
    fn a_program_that_does_not_exist_is_not_located() {
        assert!(!available("caelestia-definitely-not-a-program"));
    }

    #[test]
    fn a_successful_command_is_reported_as_one() {
        assert!(succeeds("cargo", &["--version"], None));
    }

    #[test]
    fn a_failing_command_is_reported_as_one() {
        assert!(!succeeds("cargo", &["--definitely-not-a-flag"], None));
    }

    #[test]
    fn a_missing_program_is_not_a_success() {
        assert!(!succeeds("caelestia-definitely-not-a-program", &[], None));
    }

    #[test]
    fn output_is_captured_for_a_call_that_succeeds() {
        let version = capture("cargo", &["--version"]).expect("cargo reports its version");
        assert!(version.starts_with("cargo "), "{version}");
    }

    #[test]
    fn output_is_captured_from_the_directory_that_is_asked_for() {
        let here = capture_in(
            "cargo",
            &["locate-project", "--message-format", "plain"],
            Some(Path::new(".")),
        )
        .expect("the manifest is found from the crate root");
        assert!(here.ends_with("Cargo.toml"), "{here}");
        assert!(Path::new(&here).is_absolute(), "{here}");

        let outside =
            crate::tmp::TempDir::new("caelestia-process-test").expect("a temporary directory");
        assert!(
            capture_in(
                "cargo",
                &["locate-project", "--message-format", "plain"],
                Some(outside.path())
            )
            .is_none(),
            "a directory outside the crate has no manifest"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_command_that_outlasts_its_timeout_is_killed_rather_than_waited_for() {
        let started = std::time::Instant::now();
        let status = status_with_timeout("sleep", &["30"], 1);
        let waited = started.elapsed();

        assert!(status.is_none(), "a killed command has no status");
        assert!(
            waited < std::time::Duration::from_secs(10),
            "the deadline ends the wait, not the command: {waited:?}"
        );
    }

    #[test]
    fn a_command_that_finishes_inside_its_timeout_reports_its_status() {
        assert_eq!(status_with_timeout("cargo", &["--version"], 60), Some(0));
    }
}
