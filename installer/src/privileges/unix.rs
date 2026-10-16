use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const HELPER: &str = "askpass.sh";
const PIPE: &str = "askpass.fifo";
const WRAPPER: &str = "sudo";

// How long a verification may take before the installer stops waiting for sudo, how often that
// wait is looked at, and how long the helper waits for the pipe before sudo gives up on it.
const VERIFY_TIMEOUT: Duration = Duration::from_secs(30);
const VERIFY_TICK: Duration = Duration::from_millis(25);
const SECRET_TIMEOUT: Duration = Duration::from_secs(15);
// A pause before offering the pipe again after an open that failed for any other reason.
const SERVE_PAUSE: Duration = Duration::from_millis(50);

pub struct Credential {
    dir: PathBuf,
    stop: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
}

impl Credential {
    pub fn install(secret: &str, exe: &Path) -> Result<Self, String> {
        let dir = private_dir()?;
        let pipe = dir.join(PIPE);
        make_fifo(&pipe)?;

        let helper = dir.join(HELPER);
        write_private(
            &helper,
            &format!(
                "#!/bin/bash\nexec {} --askpass {}\n",
                shell_quote(exe),
                shell_quote(&pipe)
            ),
        )?;

        let wrapper = dir.join(WRAPPER);
        write_private(
            &wrapper,
            &format!(
                "#!/bin/bash\nexport SUDO_ASKPASS={}\nexec /usr/bin/sudo -A \"$@\"\n",
                shell_quote(&helper)
            ),
        )?;

        let stop = Arc::new(AtomicBool::new(false));
        let worker = serve(pipe, secret.to_string(), Arc::clone(&stop));

        Ok(Self {
            dir,
            stop,
            worker: Some(worker),
        })
    }

    pub fn environment(&self) -> Vec<(&'static str, String)> {
        let path = match std::env::var("PATH") {
            Ok(existing) => format!("{}:{existing}", self.dir.display()),
            Err(_) => self.dir.display().to_string(),
        };
        vec![
            ("SUDO_ASKPASS", self.dir.join(HELPER).display().to_string()),
            ("PATH", path),
        ]
    }
}

/// Whether sudo takes the password. `sudo -S` reads one line and gets end of file for any retry,
/// so a wrong password costs one PAM exchange instead of three, with no helper process and no pipe
/// to lose. Bounded, so a sudo that never answers cannot hold the installer.
pub fn accepts(secret: &str) -> bool {
    match sudo_binary() {
        Some(sudo) => sudo_accepts_with(&sudo, secret, VERIFY_TIMEOUT),
        None => true,
    }
}

// A refused password costs the account an entry in the PAM stack's tally, and once enough are
// spent the stack stops taking the right password for a while. The tally and the rule that set it
// are readable without root, so the installer uses the budget the machine actually has.
const DEFAULT_DENY: usize = 3;
const FAILLOCK_CONF: &str = "/etc/security/faillock.conf";

/// Whether the system has already locked this account out, read without root: the tally lives in
/// `faillock --user`, the rule in faillock.conf.
pub fn locked_out() -> bool {
    let (counted, deny) = lockout();
    counted >= deny
}

/// Whether one more refused entry would lock the account.
pub fn on_the_last_entry() -> bool {
    let (counted, deny) = lockout();
    counted + 1 >= deny
}

fn lockout() -> (usize, usize) {
    let deny =
        deny_in(&fs::read_to_string(FAILLOCK_CONF).unwrap_or_default()).unwrap_or(DEFAULT_DENY);
    (counted_in(&faillock_table()), deny)
}

fn deny_in(conf: &str) -> Option<usize> {
    conf.lines()
        .map(str::trim)
        .filter(|line| !line.starts_with('#'))
        .filter_map(|line| line.split_once('='))
        .find(|(key, _)| key.trim() == "deny")
        .and_then(|(_, value)| value.trim().parse().ok())
}

/// The rows of `faillock --user <user>` that are entries rather than its heading.
fn counted_in(table: &str) -> usize {
    table
        .lines()
        .skip_while(|line| !line.contains("When"))
        .skip(1)
        .filter(|line| !line.trim().is_empty())
        .count()
}

fn faillock_table() -> String {
    let user = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_default();
    if user.is_empty() {
        return String::new();
    }
    std::process::Command::new("faillock")
        .args(["--user", &user])
        .output()
        .map(|output| String::from_utf8_lossy(&output.stdout).to_string())
        .unwrap_or_default()
}

fn sudo_accepts_with(sudo: &Path, secret: &str, timeout: Duration) -> bool {
    let mut command = std::process::Command::new(sudo);
    command
        .arg("-S")
        .arg("-v")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    // Its own process group, so a check that has to be killed takes everything it started with it,
    // but the same session as the installer: the authorization obtained here is the one the steps
    // then use, and a machine that keys that to the terminal will not hand it to a session of its
    // own.
    detach(&mut command);

    let Ok(mut child) = command.spawn() else {
        return false;
    };
    if let Some(mut input) = child.stdin.take() {
        let _ = input.write_all(secret.as_bytes());
        let _ = input.write_all(b"\n");
        // Dropping the handle closes the pipe: sudo reads the one line, and anything it does
        // for a second try finds nothing rather than waiting on a terminal nobody is at.
    }
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.success(),
            Ok(None) => {}
            Err(_) => return false,
        }
        if Instant::now() >= deadline {
            end_group(&mut child);
            return false;
        }
        thread::sleep(VERIFY_TICK);
    }
}

impl Drop for Credential {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        self.worker.take();
        let _ = fs::remove_dir_all(&self.dir);
    }
}

pub fn sudo_path() -> Option<PathBuf> {
    ["/usr/bin/sudo", "/bin/sudo"]
        .iter()
        .map(PathBuf::from)
        .find(|candidate| candidate.is_file())
}

// sudo reads the password from the helper, but questions it cannot answer through the helper -
// "Sorry, try again." - it writes to /dev/tty, which is the terminal the installer is drawing the
// frame on. A session of its own leaves it with no controlling terminal to reach.
//
// This is for the askpass route; the password route does not need a new session, because `-S`
// reports on stderr and staying in the installer's session keeps the authorization usable.
fn detach(command: &mut std::process::Command) {
    use std::os::unix::process::CommandExt;
    command.process_group(0);
}

// One signal to the group reaches sudo and the askpass helper it started; leaving the helper
// behind would leave it waiting on a pipe that nobody feeds any more.
fn end_group(child: &mut std::process::Child) {
    let group = child.id() as libc::pid_t;
    unsafe { libc::kill(-group, libc::SIGKILL) };
    let _ = child.kill();
    let _ = child.wait();
}

pub fn is_root() -> bool {
    unsafe { libc::getuid() == 0 }
}

pub fn sudo_cached() -> bool {
    let Some(sudo) = sudo_binary() else {
        return false;
    };
    std::process::Command::new(sudo)
        .arg("-n")
        .arg("-v")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

#[derive(Copy, Clone, PartialEq, Eq)]
pub enum Method {
    Root,
    Cached,
    Askpass,
    Terminal,
    Pkexec,
}

pub fn escalation_method() -> Option<Method> {
    if is_root() {
        return Some(Method::Root);
    }
    if sudo_cached() {
        return Some(Method::Cached);
    }
    if have_askpass() {
        return Some(Method::Askpass);
    }
    if unsafe { libc::isatty(0) } == 1 {
        return Some(Method::Terminal);
    }
    if crate::process::available("pkexec") {
        return Some(Method::Pkexec);
    }
    None
}

fn have_askpass() -> bool {
    std::env::var("SUDO_ASKPASS")
        .ok()
        .filter(|helper| !helper.is_empty())
        .map(PathBuf::from)
        .filter(|helper| crate::process::is_executable(helper))
        .is_some()
}

fn sudo_binary() -> Option<PathBuf> {
    // CAELESTIA_SUDO_BIN names the sudo to escalate through, the same override the shell
    // resolver next to this honors.
    if let Ok(explicit) = std::env::var("CAELESTIA_SUDO_BIN") {
        let explicit = PathBuf::from(explicit);
        if crate::process::is_executable(&explicit) {
            return Some(explicit);
        }
    }
    sudo_path().or_else(|| crate::process::locate("sudo"))
}

pub fn elevated_command(
    program: &str,
    args: &[&str],
    directory: Option<&Path>,
) -> Result<std::process::Command, String> {
    let method = escalation_method()
        .ok_or_else(|| "this installer has no way to become root here".to_string())?;

    let mut command = match method {
        Method::Root => {
            let mut command = std::process::Command::new(program);
            command.args(args);
            command
        }
        Method::Cached => {
            let mut command = std::process::Command::new(sudo_binary().ok_or("sudo is missing")?);
            command.arg("-n").arg(program).args(args);
            command
        }
        Method::Askpass => {
            let mut command = std::process::Command::new(sudo_binary().ok_or("sudo is missing")?);
            command.arg("-A").arg(program).args(args);
            command
        }
        Method::Terminal => {
            let mut command = std::process::Command::new(sudo_binary().ok_or("sudo is missing")?);
            command.arg(program).args(args);
            command
        }
        Method::Pkexec => {
            let mut command = std::process::Command::new(
                crate::process::locate("pkexec").ok_or("pkexec is missing")?,
            );
            command.arg(program).args(args);
            command
        }
    };

    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    Ok(command)
}

pub fn elevated(program: &str, args: &[&str], directory: Option<&Path>) -> Result<i32, String> {
    let mut command = elevated_command(program, args, directory)?;
    command
        .status()
        .map(|status| status.code().unwrap_or(1))
        .map_err(|error| format!("could not run {program}: {error}"))
}

// The same route, with the child's own complaint kept out of the installer's output: the
// caller reports what it could not do instead of relaying a tool's message about it.
pub fn elevated_quietly(
    program: &str,
    args: &[&str],
    directory: Option<&Path>,
) -> Result<i32, String> {
    let mut command = elevated_command(program, args, directory)?;
    command
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.code().unwrap_or(1))
        .map_err(|error| format!("could not run {program}: {error}"))
}

// Escalate only where no password can be needed: a terminal or pkexec route would ask, and
// a step nobody is watching must not stall on a prompt. The caller warns and carries on.
pub fn quiet(program: &str, args: &[&str], directory: Option<&Path>) -> Result<i32, String> {
    let method = escalation_method()
        .ok_or_else(|| "this installer has no way to become root here".to_string())?;
    let mut command = match method {
        Method::Root => {
            let mut command = std::process::Command::new(program);
            command.args(args);
            command
        }
        Method::Cached | Method::Askpass => {
            let mut command = std::process::Command::new(sudo_binary().ok_or("sudo is missing")?);
            command
                .arg(if method == Method::Cached { "-n" } else { "-A" })
                .arg(program)
                .args(args);
            command
        }
        Method::Terminal | Method::Pkexec => {
            return Err("escalating here would have to ask for a password".to_string());
        }
    };
    if let Some(directory) = directory {
        command.current_dir(directory);
    }
    command
        .status()
        .map(|status| status.code().unwrap_or(1))
        .map_err(|error| format!("could not run {program}: {error}"))
}

pub fn read_secret(pipe: &Path) -> Result<String, String> {
    read_secret_within(pipe, SECRET_TIMEOUT)
}

// sudo waits for this helper to finish before it goes on, so a helper that waited forever would
// hang the installer waiting for sudo. The thread left blocked in the open below ends with this
// process, which exits as soon as this wait is over.
fn read_secret_within(pipe: &Path, timeout: Duration) -> Result<String, String> {
    let (sender, receiver) = std::sync::mpsc::channel();
    let path = pipe.to_path_buf();
    thread::spawn(move || {
        let _ = sender.send(read_one_line(&path));
    });
    receiver.recv_timeout(timeout).unwrap_or_else(|_| {
        Err(format!(
            "the installer did not offer a password within {timeout:?}"
        ))
    })
}

fn read_one_line(pipe: &Path) -> Result<String, String> {
    let file =
        File::open(pipe).map_err(|error| format!("cannot read {}: {error}", pipe.display()))?;
    let mut secret = String::new();
    BufReader::new(file)
        .read_line(&mut secret)
        .map_err(|error| format!("cannot read {}: {error}", pipe.display()))?;
    Ok(secret.trim_end_matches('\n').to_string())
}

fn make_fifo(pipe: &Path) -> Result<(), String> {
    let pipe_c = std::ffi::CString::new(pipe.as_os_str().as_encoded_bytes())
        .map_err(|_| "the pipe path is not usable".to_string())?;
    if unsafe { libc::mkfifo(pipe_c.as_ptr(), 0o600) } != 0 {
        return Err(format!(
            "cannot create {}: {}",
            pipe.display(),
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

// One helper reads one secret, and sudo asks again for each attempt, so the loop waits for the
// next helper to appear on the pipe. A failed round is a round nobody asked for: leaving the loop
// would strand the next helper on a pipe nothing feeds - which is how one wrong password used to
// hang the installer for good.
fn serve(pipe: PathBuf, secret: String, stop: Arc<AtomicBool>) -> JoinHandle<()> {
    thread::spawn(move || {
        while !stop.load(Ordering::Relaxed) {
            match OpenOptions::new().write(true).open(&pipe) {
                Ok(mut writer) => {
                    let _ = writer.write_all(secret.as_bytes());
                    let _ = writer.write_all(b"\n");
                }
                Err(error) if error.raw_os_error() == Some(libc::EINTR) => {}
                Err(_) => thread::sleep(SERVE_PAUSE),
            }
        }
    })
}

fn private_dir() -> Result<PathBuf, String> {
    let uid = unsafe { libc::getuid() };
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Some(runtime) = std::env::var_os("XDG_RUNTIME_DIR") {
        let runtime = PathBuf::from(runtime);
        if owned_by(&runtime, uid) {
            roots.push(runtime);
        }
    }
    roots.push(std::env::temp_dir());

    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos())
        .unwrap_or(0);
    for root in roots {
        let dir = root.join(format!("caelestia-install-{}-{unique}", std::process::id()));
        match fs::create_dir(&dir) {
            Ok(()) => {
                fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))
                    .map_err(|error| format!("cannot protect {}: {error}", dir.display()))?;
                return Ok(dir);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("cannot create {}: {error}", dir.display())),
        }
    }
    Err("nowhere private to put the askpass helper".to_string())
}

fn owned_by(path: &Path, uid: u32) -> bool {
    use std::os::unix::fs::MetadataExt;
    fs::metadata(path)
        .map(|meta| meta.is_dir() && meta.uid() == uid)
        .unwrap_or(false)
}

fn write_private(path: &Path, body: &str) -> Result<(), String> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| format!("cannot write {}: {error}", path.display()))?;
    file.write_all(body.as_bytes())
        .map_err(|error| error.to_string())?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        .map_err(|error| format!("cannot protect {}: {error}", path.display()))
}

fn shell_quote(value: &Path) -> String {
    let text = value.to_string_lossy();
    format!("'{}'", text.replace('\'', "'\\''"))
}

pub struct Inhibitor {
    pid: Option<libc::pid_t>,
    cookie: Option<String>,
}

impl Inhibitor {
    pub fn acquire() -> Self {
        let state = state_dir();
        let pid_file = state.join("inhibit.pid");
        let cookie_file = state.join("kde_inhibit.cookie");

        reap_previous(&pid_file);
        let _ = fs::remove_file(&cookie_file);

        let pid = spawn_inhibitor();
        if let Some(pid) = pid {
            let _ = fs::write(&pid_file, format!("{pid}\n"));
        }
        let cookie = inhibit_screensaver(&cookie_file);
        Self { pid, cookie }
    }
}

impl Drop for Inhibitor {
    fn drop(&mut self) {
        if let Some(pid) = self.pid {
            unsafe { libc::kill(pid, libc::SIGKILL) };
        }
        if let Some(cookie) = self.cookie.take() {
            let _ = std::process::Command::new("qdbus6")
                .args([
                    "org.freedesktop.ScreenSaver",
                    "/ScreenSaver",
                    "org.freedesktop.ScreenSaver.UnInhibit",
                    &cookie,
                ])
                .status();
        }
        let state = state_dir();
        let _ = fs::remove_file(state.join("inhibit.pid"));
        let _ = fs::remove_file(state.join("kde_inhibit.cookie"));
    }
}

fn state_dir() -> PathBuf {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .or_else(|| std::env::var_os("XDG_STATE_HOME"))
        .or_else(|| {
            std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state").into())
        })
        .unwrap_or_else(|| std::env::temp_dir().into());
    let dir = PathBuf::from(base).join("caelestia");
    let _ = fs::create_dir_all(&dir);
    let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
    dir
}

fn reap_previous(pid_file: &Path) {
    let Ok(contents) = fs::read_to_string(pid_file) else {
        return;
    };
    let Ok(pid) = contents.trim().parse::<libc::pid_t>() else {
        return;
    };
    if pid <= 0 || pid == unsafe { libc::getpid() } || pid == unsafe { libc::getppid() } {
        return;
    }
    let Ok(cmdline) = fs::read_to_string(format!("/proc/{pid}/cmdline")) else {
        return;
    };
    if cmdline.contains("systemd-inhibit") {
        unsafe { libc::kill(pid, libc::SIGKILL) };
    }
}

fn spawn_inhibitor() -> Option<libc::pid_t> {
    std::process::Command::new("systemd-inhibit")
        .arg(format!("--what={}", inhibit_what()))
        .args([
            "--who=Caelestia installer",
            "--why=Installation in progress",
            "bash",
            "-c",
            "while :; do sleep 600; done",
        ])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()
        .map(|child| child.id() as libc::pid_t)
}

// Blocking sleep is a polkit action, and a client polkit cannot tie to an active session is
// asked to authenticate for it. That question goes to whatever is holding the desktop - on a
// Caelestia desktop, the shell the user is looking at - so sleep is only asked for where it is
// already allowed and nothing will be raised. Idle inhibition needs no authorization and is
// what keeps an install from being suspended out from under it.
fn inhibit_what() -> &'static str {
    if may_block_sleep() {
        "idle:sleep"
    } else {
        "idle"
    }
}

fn may_block_sleep() -> bool {
    std::process::Command::new("pkcheck")
        .args([
            "--action-id",
            "org.freedesktop.login1.inhibit-block-sleep",
            "--process",
            &std::process::id().to_string(),
        ])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn inhibit_screensaver(cookie_file: &Path) -> Option<String> {
    let output = std::process::Command::new("qdbus6")
        .args([
            "org.freedesktop.ScreenSaver",
            "/ScreenSaver",
            "org.freedesktop.ScreenSaver.Inhibit",
            "Caelestia installer",
            "Installation in progress",
        ])
        .output()
        .ok()?;
    let cookie = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if cookie.is_empty() {
        return None;
    }
    let _ = fs::write(cookie_file, &cookie);
    Some(cookie)
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::time::{Duration, Instant};

    use crate::tmp::TempDir;

    fn a_work_dir() -> TempDir {
        TempDir::new("caelestia-privileges-test").expect("a temporary directory")
    }

    fn a_credential() -> Credential {
        let exe = std::env::current_exe().expect("the test binary has a path");
        Credential::install("hunter2", &exe).expect("a credential")
    }

    // A stand-in for sudo: it announces itself first, then reads the password from stdin the way
    // `sudo -S` does, answers as told, and leaves a note behind about the session it was run in
    // and what it was given. Announcing first is what lets a test about a check that has to be
    // abandoned know the process it is looking for had started, rather than racing a deadline
    // against the machine's scheduling.
    fn fake_sudo(work: &Path, name: &str, answer: &str) -> PathBuf {
        let path = work.join(name);
        let report = work.join(format!("{name}.report"));
        write_private(
            &path,
            &format!(
                "#!/bin/bash\n\
                 echo \"pid=$$\" >> {report}\n\
                 echo \"sid=$(cut -d' ' -f6 /proc/$$/stat)\" >> {report}\n\
                 echo \"pgid=$(cut -d' ' -f5 /proc/$$/stat)\" >> {report}\n\
                 read -r secret\n\
                 echo \"secret=$secret\" >> {report}\n\
                 {answer}\n",
                report = shell_quote(&report),
            ),
        )
        .expect("a stand-in for sudo");
        path
    }

    fn reported_text(report: &Path, key: &str) -> String {
        let text = fs::read_to_string(report).expect("the report sudo left behind");
        text.lines()
            .find_map(|line| line.strip_prefix(key))
            .unwrap_or_else(|| panic!("no {key} in:\n{text}"))
            .to_string()
    }

    fn reported(report: &Path, key: &str) -> i32 {
        reported_text(report, key)
            .trim()
            .parse()
            .unwrap_or_else(|_| panic!("{key} is not a number in {}", report.display()))
    }

    fn gone(pid: i32) -> bool {
        for _ in 0..40 {
            if !Path::new(&format!("/proc/{pid}")).exists() {
                return true;
            }
            thread::sleep(Duration::from_millis(25));
        }
        false
    }

    #[test]
    fn paths_are_quoted_so_a_generated_script_cannot_be_escaped_out_of() {
        assert_eq!(shell_quote(Path::new("/tmp/plain")), "'/tmp/plain'");
        assert_eq!(shell_quote(Path::new("/tmp/it's")), "'/tmp/it'\\''s'");
    }

    #[test]
    fn the_credential_publishes_a_helper_and_never_writes_the_password() {
        let exe = std::env::current_exe().expect("the test binary has a path");
        let credential = Credential::install("hunter2", &exe).expect("a credential");

        let helper = credential.dir.join(HELPER);
        let wrapper = credential.dir.join(WRAPPER);
        let pipe = credential.dir.join(PIPE);
        assert!(helper.is_file(), "the helper is published");
        assert!(wrapper.is_file(), "the sudo shim is published");
        assert!(pipe.exists(), "the pipe exists");

        for entry in fs::read_dir(&credential.dir).expect("the shim directory") {
            let path = entry.expect("an entry").path();
            if path == pipe {
                continue;
            }
            let body = fs::read_to_string(&path).unwrap_or_default();
            assert!(
                !body.contains("hunter2"),
                "{} holds the password",
                path.display()
            );
        }

        for path in [&helper, &wrapper] {
            let mode = fs::metadata(path).expect("metadata").permissions().mode();
            assert_eq!(mode & 0o777, 0o700, "{}", path.display());
        }

        let reader = std::thread::spawn(move || read_secret(&pipe));
        let served = reader
            .join()
            .expect("the reader thread finishes")
            .expect("the pipe is served");
        assert_eq!(served, "hunter2");
    }

    #[test]
    fn a_credential_cleans_up_after_itself() {
        let exe = std::env::current_exe().expect("the test binary has a path");
        let dir = {
            let credential = Credential::install("secret", &exe).expect("a credential");
            let dir = credential.dir.clone();
            assert!(dir.is_dir());
            dir
        };
        assert!(
            !dir.exists(),
            "the shim directory is removed when the credential drops"
        );
    }

    #[test]
    fn the_environment_points_the_scripts_at_the_helper() {
        let exe = std::env::current_exe().expect("the test binary has a path");
        let credential = Credential::install("secret", &exe).expect("a credential");
        let env = credential.environment();
        let askpass = env
            .iter()
            .find(|(key, _)| *key == "SUDO_ASKPASS")
            .expect("SUDO_ASKPASS");
        assert!(askpass.1.ends_with(HELPER), "{}", askpass.1);
        let path = env.iter().find(|(key, _)| *key == "PATH").expect("PATH");
        assert!(
            path.1.starts_with(&credential.dir.display().to_string()),
            "{}",
            path.1
        );
    }

    #[test]
    fn the_lockout_budget_is_read_from_the_system_rather_than_guessed() {
        // The rule and the tally are both readable without root, so the installer can spend
        // exactly what the account was given and never the entry that locks it.
        assert_eq!(deny_in("deny = 5\nunlock_time = 600\n"), Some(5));
        assert_eq!(deny_in("# deny = 2\nunlock_time = 600\n"), None);
        assert_eq!(deny_in(""), None);

        let table = "camus:\n\
                     When                Type  Source        Valid\n\
                     2026-10-15 16:55:29 SVC   sudo            V\n\
                     2026-10-15 16:55:32 SVC   sudo            V\n";
        assert_eq!(counted_in(table), 2);
        assert_eq!(counted_in("camus:\n"), 0);
    }

    #[test]
    fn the_password_reaches_sudo_and_its_answer_is_believed() {
        let work = a_work_dir();
        let right = fake_sudo(work.path(), "sudo-ok", "exit 0");
        assert!(
            sudo_accepts_with(&right, "hunter2", Duration::from_secs(20)),
            "an accepted password was not believed"
        );
        assert_eq!(
            reported_text(&work.path().join("sudo-ok.report"), "secret="),
            "hunter2",
            "sudo was not handed the password"
        );

        let wrong = fake_sudo(work.path(), "sudo-no", "exit 1");
        assert!(
            !sudo_accepts_with(&wrong, "hunter2", Duration::from_secs(20)),
            "a refused password was believed"
        );
    }

    #[test]
    fn sudo_is_run_in_a_group_of_its_own_but_the_installers_session() {
        // A check that has to be killed must take its children with it, so it leads a process
        // group. It must NOT take a session of its own: the authorization it obtains is the one
        // the steps then use, and a machine that keys that to the terminal hands it only to a
        // check that shares the installer's session. It also keeps /dev/tty out of sudo's reach.
        let work = a_work_dir();
        let sudo = fake_sudo(work.path(), "sudo", "exit 0");
        assert!(sudo_accepts_with(&sudo, "hunter2", Duration::from_secs(20)));

        let report = work.path().join("sudo.report");
        let pid = reported(&report, "pid=");
        let session = reported(&report, "sid=");
        let group = reported(&report, "pgid=");
        assert_eq!(group, pid, "sudo leads a process group of its own");
        assert_eq!(
            session,
            unsafe { libc::getsid(0) },
            "and stays in the installer's session, so the authorization is shared"
        );
    }

    #[test]
    fn a_check_that_is_never_answered_gives_up_and_takes_sudo_with_it() {
        let work = a_work_dir();
        // exec, so the process that reported the pid is the one that hangs.
        let sudo = fake_sudo(work.path(), "sudo", "exec sleep 60");

        let started = Instant::now();
        // Long enough that the stand-in has been scheduled and has announced itself, and short
        // enough that a check which actually waited for it to finish would fail the bound below.
        // A deadline much tighter than this measures the machine's scheduling under a loaded
        // test run rather than the check's behavior: killed before its first line, the
        // stand-in never reports and there is nothing to say it was taken with it.
        assert!(!sudo_accepts_with(&sudo, "hunter2", Duration::from_secs(4)));
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "the wait outlived its own deadline by {:?}",
            started.elapsed()
        );

        let pid = reported(&work.path().join("sudo.report"), "pid=");
        assert!(gone(pid), "sudo outlived the check that gave up on it");
    }

    #[test]
    fn a_helper_is_not_left_waiting_forever_for_a_password() {
        // Nothing is serving this pipe, which is what an installer that stopped serving
        // looks like from the helper's side.
        let work = a_work_dir();
        let pipe = work.path().join("unserved.fifo");
        make_fifo(&pipe).expect("a pipe to wait on");

        let started = Instant::now();
        assert!(
            read_secret_within(&pipe, Duration::from_millis(200)).is_err(),
            "a secret came out of a pipe nobody feeds"
        );
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "the helper waited {:?} on a pipe nobody feeds",
            started.elapsed()
        );
    }

    #[test]
    fn the_credential_answers_every_helper_that_asks() {
        // sudo asks once for each attempt it makes, so the pipe has to keep serving after
        // the first reader has taken its secret.
        let credential = a_credential();
        let pipe = credential.dir.join(PIPE);
        for attempt in 1..=5 {
            let served = read_secret_within(&pipe, Duration::from_secs(20));
            assert_eq!(served.ok().as_deref(), Some("hunter2"), "attempt {attempt}");
        }
    }
}
