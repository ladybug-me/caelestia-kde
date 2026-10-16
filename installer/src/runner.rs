use std::fs::OpenOptions;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::time::Duration;

use crate::steps::Status;

const WARN_MARKER: &str = "[WARN]";

pub struct Running {
    child: Child,
    log: PathBuf,
    offset: u64,
    warned: bool,
}

impl Running {
    // Every step is native now, so the installer itself only ever launches the binary. The
    // tests below drive a script instead: a step run through the binary would be the test
    // binary, which is not the installer.
    #[cfg(test)]
    pub fn spawn(
        bundle: &Path,
        script: &str,
        log: &Path,
        env: &[(&'static str, String)],
    ) -> Result<Self, String> {
        let script_path = bundle.join(script);
        if !script_path.is_file() {
            return Err(format!("missing step script: {}", script_path.display()));
        }

        let mut streamed = Command::new("stdbuf");
        streamed.args(["-oL", "-eL", "bash"]).arg(&script_path);
        if let Ok(running) = Self::launch(bundle, log, env, &mut streamed, script) {
            return Ok(running);
        }

        let mut plain = Command::new("bash");
        plain.arg(&script_path);
        Self::launch(bundle, log, env, &mut plain, script)
    }

    pub fn spawn_native(
        bundle: &Path,
        id: &str,
        log: &Path,
        env: &[(&'static str, String)],
    ) -> Result<Self, String> {
        let exe = std::env::current_exe()
            .map_err(|error| format!("cannot locate the installer binary: {error}"))?;
        let mut command = Command::new(exe);
        command.arg("step").arg(id);
        Self::launch(bundle, log, env, &mut command, id)
    }

    fn launch(
        bundle: &Path,
        log: &Path,
        env: &[(&'static str, String)],
        command: &mut Command,
        label: &str,
    ) -> Result<Self, String> {
        let out = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log)
            .map_err(|error| format!("cannot open the install log: {error}"))?;
        let err = out.try_clone().map_err(|error| error.to_string())?;

        let offset = std::fs::metadata(log).map(|meta| meta.len()).unwrap_or(0);

        // Its own process group, so stopping the step stops everything it started rather than
        // just the first process. It also keeps the terminal's own ctrl+c away from it: the
        // installer decides when a step ends.
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }

        let child = command
            .current_dir(bundle)
            .envs(env.iter().map(|(key, value)| (*key, value.clone())))
            .stdin(Stdio::null())
            .stdout(Stdio::from(out))
            .stderr(Stdio::from(err))
            .spawn()
            .map_err(|error| format!("cannot run {label}: {error}"))?;

        Ok(Self {
            child,
            log: log.to_path_buf(),
            offset,
            warned: false,
        })
    }

    /// Stop the step and everything it started: a term first so a package manager can put its
    /// lock back, and a kill only if it will not go.
    pub fn stop(&mut self) {
        if matches!(self.child.try_wait(), Ok(Some(_))) {
            return;
        }
        #[cfg(unix)]
        let group = self.child.id() as i32;
        #[cfg(unix)]
        unsafe {
            libc::kill(-group, libc::SIGTERM);
        }
        for _ in 0..20 {
            if matches!(self.child.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        #[cfg(unix)]
        unsafe {
            libc::kill(-group, libc::SIGKILL);
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    pub fn poll(&mut self) -> Result<Option<ExitStatus>, String> {
        self.child
            .try_wait()
            .map_err(|error| format!("cannot wait for the step: {error}"))
    }

    pub fn drain(&mut self, into: &mut Vec<String>) -> usize {
        let mut fresh = Vec::new();
        if tail_lines(&self.log, &mut self.offset, &mut fresh).is_err() {
            return 0;
        }
        let added = fresh.len();
        self.warned |= fresh.iter().any(|line| line.contains(WARN_MARKER));
        into.extend(fresh);
        added
    }

    pub fn outcome(&self, status: ExitStatus) -> Status {
        if !status.success() {
            Status::Failed
        } else if self.warned {
            Status::Warn
        } else {
            Status::Ok
        }
    }
}

/// A step that is dropped while it is still going is a step nobody stopped: quitting the TUI must
/// not leave a package manager running behind it.
impl Drop for Running {
    fn drop(&mut self) {
        self.stop();
    }
}

pub fn tail_lines(log: &Path, from: &mut u64, into: &mut Vec<String>) -> io::Result<()> {
    let mut file = OpenOptions::new().read(true).open(log)?;
    let length = file.metadata()?.len();
    if length <= *from {
        return Ok(());
    }
    file.seek(SeekFrom::Start(*from))?;
    let mut raw = String::new();
    file.read_to_string(&mut raw)?;

    let complete = match raw.rfind('\n') {
        Some(end) => end + 1,
        None => return Ok(()),
    };
    for line in raw[..complete].split_terminator('\n') {
        into.push(strip_ansi(line));
    }
    *from += complete as u64;
    Ok(())
}

pub fn strip_ansi(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch != '\u{1b}' {
            out.push(ch);
            continue;
        }
        match chars.peek() {
            Some('[') => {
                chars.next();
                for next in chars.by_ref() {
                    if ('\u{40}'..='\u{7e}').contains(&next) {
                        break;
                    }
                }
            }
            Some(']') => {
                chars.next();
                while let Some(next) = chars.next() {
                    if next == '\u{7}' {
                        break;
                    }
                    if next == '\u{1b}' && chars.peek() == Some(&'\\') {
                        chars.next();
                        break;
                    }
                }
            }
            Some(_) => {
                chars.next();
            }
            None => {}
        }
    }
    out.trim_end_matches('\r').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ansi_escapes_are_removed_and_text_is_kept() {
        assert_eq!(
            strip_ansi("\u{1b}[38;2;1;2;3mhello\u{1b}[0m world"),
            "hello world"
        );
        assert_eq!(strip_ansi("\u{1b}]0;title\u{7}text"), "text");
        assert_eq!(strip_ansi("plain"), "plain");
    }

    #[test]
    fn carriage_returns_do_not_reach_the_view() {
        assert_eq!(strip_ansi("progress\r"), "progress");
    }

    #[test]
    fn an_empty_escape_is_not_a_panic() {
        assert_eq!(strip_ansi("\u{1b}"), "");
        assert_eq!(strip_ansi("\u{1b}["), "");
    }

    #[test]
    fn missing_logs_and_fresh_logs_are_not_errors() {
        let mut from = 0;
        let mut lines = Vec::new();
        assert!(tail_lines(Path::new("/nonexistent/install.log"), &mut from, &mut lines).is_err());
        assert!(lines.is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn a_partial_line_waits_for_its_newline() {
        let dir = std::env::temp_dir().join(format!("caelestia-tail-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let log = dir.join("install.log");
        std::fs::write(&log, "one\ntwo").expect("the log is writable");

        let mut from = 0;
        let mut lines = Vec::new();
        tail_lines(&log, &mut from, &mut lines).expect("the log is readable");
        assert_eq!(
            lines,
            vec!["one".to_string()],
            "the unfinished line is held back"
        );

        std::fs::write(&log, "one\ntwo\nthree\n").expect("the log is writable");
        let mut more = Vec::new();
        tail_lines(&log, &mut from, &mut more).expect("the log is readable");
        assert_eq!(more, vec!["two".to_string(), "three".to_string()]);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_step_is_spawned_written_to_the_log_and_judged_by_its_status() {
        let dir = std::env::temp_dir().join(format!("caelestia-run-{}", std::process::id()));
        let scripts = dir.join("scripts");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&scripts).expect("a scripts directory");
        std::fs::write(
            scripts.join("00a-system-update.sh"),
            "#!/bin/bash\necho hello\necho '[WARN] careful'\nexit 0\n",
        )
        .expect("a step script");
        let log = dir.join("install.log");

        let mut running =
            Running::spawn(&dir, "scripts/00a-system-update.sh", &log, &[]).expect("spawn");
        let status = loop {
            if let Some(status) = running.poll().expect("poll") {
                break status;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        };
        let mut lines = Vec::new();
        running.drain(&mut lines);
        assert_eq!(
            running.outcome(status),
            Status::Warn,
            "a warning in the log is a warning"
        );
        assert!(lines.iter().any(|line| line.contains("hello")), "{lines:?}");
    }

    #[cfg(unix)]
    #[test]
    fn stopping_a_step_ends_it_rather_than_leaving_it_to_finish() {
        let dir = std::env::temp_dir().join(format!("caelestia-stop-{}", std::process::id()));
        let scripts = dir.join("scripts");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&scripts).expect("a scripts directory");
        std::fs::write(
            scripts.join("slow.sh"),
            "#!/bin/bash\nsleep 30\necho 'should never be reached'\n",
        )
        .expect("a slow step script");
        let log = dir.join("install.log");

        let mut running = Running::spawn(&dir, "scripts/slow.sh", &log, &[]).expect("spawn");
        std::thread::sleep(Duration::from_millis(300));
        assert!(
            running.poll().expect("poll").is_none(),
            "the step is still running"
        );

        running.stop();
        assert!(
            running.poll().expect("poll").is_some(),
            "the step was still going after being stopped"
        );
        let text = std::fs::read_to_string(&log).unwrap_or_default();
        assert!(
            !text.contains("should never be reached"),
            "the step carried on after being stopped: {text}"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_step_that_fails_is_a_failure() {
        let dir = std::env::temp_dir().join(format!("caelestia-run-fail-{}", std::process::id()));
        let scripts = dir.join("scripts");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&scripts).expect("a scripts directory");
        std::fs::write(
            scripts.join("00a-system-update.sh"),
            "#!/bin/bash\nexit 3\n",
        )
        .expect("a step script");
        let log = dir.join("install.log");

        let mut running =
            Running::spawn(&dir, "scripts/00a-system-update.sh", &log, &[]).expect("spawn");
        let status = loop {
            if let Some(status) = running.poll().expect("poll") {
                break status;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        };
        assert_eq!(running.outcome(status), Status::Failed);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_step_can_be_given_environment_the_scripts_read() {
        let dir = std::env::temp_dir().join(format!("caelestia-run-env-{}", std::process::id()));
        let scripts = dir.join("scripts");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&scripts).expect("a scripts directory");
        std::fs::write(
            scripts.join("00a-system-update.sh"),
            "#!/bin/bash\necho \"$CAELESTIA_TEST\"\n",
        )
        .expect("a step script");
        let log = dir.join("install.log");
        let env = [("CAELESTIA_TEST", "from-the-environment".to_string())];

        let mut running =
            Running::spawn(&dir, "scripts/00a-system-update.sh", &log, &env).expect("spawn");
        let status = loop {
            if let Some(status) = running.poll().expect("poll") {
                break status;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        };
        let mut lines = Vec::new();
        running.drain(&mut lines);
        assert_eq!(running.outcome(status), Status::Ok);
        assert!(
            lines
                .iter()
                .any(|line| line.contains("from-the-environment")),
            "the answers reach the step scripts: {lines:?}"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_missing_script_is_reported_rather_than_spawned() {
        let error = match Running::spawn(
            Path::new("/nonexistent"),
            "scripts/00a-system-update.sh",
            Path::new("/nonexistent/install.log"),
            &[],
        ) {
            Ok(_) => panic!("a missing script must not spawn"),
            Err(error) => error,
        };
        assert!(error.contains("missing step script"), "{error}");
    }
}
