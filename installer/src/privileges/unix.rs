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

const SUDO_PAM: &str = "/etc/pam.d/sudo";
const PAM_DIRECTORY: &str = "/etc/pam.d";
const FINGERPRINT_MODULE: &str = "pam_fprintd.so";
const PAM_DEPTH: usize = 4;

const VERIFY_TIMEOUT: Duration = Duration::from_secs(30);
const FINGERPRINT_TIMEOUT: Duration = Duration::from_secs(60);
const VERIFY_TICK: Duration = Duration::from_millis(25);
const SECRET_TIMEOUT: Duration = Duration::from_secs(15);
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

        publish(
            &dir,
            &format!(
                "#!/bin/bash\nexec {} --askpass {}\n",
                shell_quote(exe),
                shell_quote(&pipe)
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

    pub fn fingerprint() -> Result<Self, String> {
        let dir = private_dir()?;
        publish(&dir, "#!/bin/bash\nexit 1\n")?;
        Ok(Self {
            dir,
            stop: Arc::new(AtomicBool::new(false)),
            worker: None,
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

    fn helper_path(&self) -> PathBuf {
        self.dir.join(HELPER)
    }
}

fn publish(dir: &Path, helper: &str) -> Result<(), String> {
    let helper_path = dir.join(HELPER);
    write_private(&helper_path, helper)?;
    write_private(
        &dir.join(WRAPPER),
        &format!(
            "#!/bin/bash\nexport SUDO_ASKPASS={}\nexec /usr/bin/sudo -A \"$@\"\n",
            shell_quote(&helper_path)
        ),
    )
}

pub fn accepts(secret: &str) -> bool {
    match sudo_binary() {
        Some(sudo) => sudo_accepts_with(&sudo, secret, VERIFY_TIMEOUT),
        None => true,
    }
}

pub fn accepts_fingerprint() -> bool {
    let Ok(credential) = Credential::fingerprint() else {
        return false;
    };
    let Some(sudo) = sudo_binary() else {
        return false;
    };
    let mut command = std::process::Command::new(sudo);
    command
        .arg("-A")
        .arg("-v")
        .env("SUDO_ASKPASS", credential.helper_path())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    detach(&mut command);

    command
        .spawn()
        .map(|child| wait_for_exit(child, FINGERPRINT_TIMEOUT))
        .unwrap_or(false)
}

fn wait_for_exit(mut child: std::process::Child, timeout: Duration) -> bool {
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

const DEFAULT_DENY: usize = 3;
const FAILLOCK_CONF: &str = "/etc/security/faillock.conf";

pub fn locked_out() -> bool {
    let (counted, deny) = lockout();
    counted >= deny
}

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
    detach(&mut command);

    let Ok(mut child) = command.spawn() else {
        return false;
    };
    if let Some(mut input) = child.stdin.take() {
        let _ = input.write_all(secret.as_bytes());
        let _ = input.write_all(b"\n");
    }
    wait_for_exit(child, timeout)
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

fn detach(command: &mut std::process::Command) {
    use std::os::unix::process::CommandExt;
    command.process_group(0);
}

fn end_group(child: &mut std::process::Child) {
    let group = child.id() as libc::pid_t;
    unsafe { libc::kill(-group, libc::SIGKILL) };
    let _ = child.kill();
    let _ = child.wait();
}

pub fn is_root() -> bool {
    unsafe { libc::getuid() == 0 }
}

fn cached_probe_args() -> [&'static str; 2] {
    ["-n", "true"]
}

pub fn sudo_cached() -> bool {
    let Some(sudo) = sudo_binary() else {
        return false;
    };
    std::process::Command::new(sudo)
        .args(cached_probe_args())
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

pub fn fingerprint_ready() -> bool {
    static READY: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *READY.get_or_init(|| fingerprint_configured() && reader_present() && finger_enrolled())
}

pub fn finger_enrolled() -> bool {
    if !crate::process::available("fprintd-list") {
        return false;
    }
    let user = std::env::var("SUDO_USER")
        .ok()
        .filter(|name| !name.is_empty())
        .or_else(|| crate::process::capture("id", &["-un"]))
        .unwrap_or_default();
    if user.is_empty() {
        return false;
    }
    std::process::Command::new("fprintd-list")
        .arg(&user)
        .stdin(std::process::Stdio::null())
        .output()
        .map(|output| prints_listed(&String::from_utf8_lossy(&output.stdout)))
        .unwrap_or(false)
}

fn prints_listed(answer: &str) -> bool {
    answer
        .lines()
        .any(|line| line.trim_start().starts_with("- #"))
}

pub fn fingerprint_configured() -> bool {
    let Ok(text) = fs::read_to_string(SUDO_PAM) else {
        return false;
    };
    pam_stack_has_fingerprint(&text, PAM_DEPTH, &|name| {
        let path = if name.starts_with('/') {
            PathBuf::from(name)
        } else {
            Path::new(PAM_DIRECTORY).join(name)
        };
        fs::read_to_string(path).ok()
    })
}

fn pam_stack_has_fingerprint(
    text: &str,
    depth: usize,
    read: &dyn Fn(&str) -> Option<String>,
) -> bool {
    if depth == 0 {
        return false;
    }
    for line in text.lines() {
        let fields: Vec<&str> = line
            .split('#')
            .next()
            .unwrap_or_default()
            .split_whitespace()
            .collect();
        if fields.contains(&FINGERPRINT_MODULE) {
            return true;
        }
        let included = match fields.as_slice() {
            [directive, file, ..] if matches!(*directive, "@include" | "@substack") => Some(*file),
            [_kind, directive, file, ..] if matches!(*directive, "include" | "substack") => {
                Some(*file)
            }
            _ => None,
        };
        if let Some(file) = included
            && read(file).is_some_and(|text| pam_stack_has_fingerprint(&text, depth - 1, read))
        {
            return true;
        }
    }
    false
}

fn reader_present() -> bool {
    if !crate::process::available("busctl") {
        return false;
    }
    std::process::Command::new("busctl")
        .args([
            "--system",
            "call",
            "net.reactivated.Fprint",
            "/net/reactivated/Fprint/Manager",
            "net.reactivated.Fprint.Manager",
            "GetDevices",
        ])
        .stdin(std::process::Stdio::null())
        .output()
        .map(|output| readers_listed(&String::from_utf8_lossy(&output.stdout)))
        .unwrap_or(false)
}

fn readers_listed(answer: &str) -> bool {
    answer.contains("/net/reactivated/Fprint/Device/")
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
    if let Some(explicit) = std::env::var("CAELESTIA_SUDO_BIN")
        .ok()
        .filter(|explicit| !explicit.is_empty())
    {
        return Some(PathBuf::from(explicit));
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
    fn a_warm_ticket_is_probed_with_a_command_and_not_with_a_validation() {
        assert_eq!(cached_probe_args(), ["-n", "true"]);
    }

    #[test]
    fn paths_are_quoted_so_a_generated_script_cannot_be_escaped_out_of() {
        assert_eq!(shell_quote(Path::new("/tmp/plain")), "'/tmp/plain'");
        assert_eq!(shell_quote(Path::new("/tmp/it's")), "'/tmp/it'\\''s'");
    }

    fn read_stack(files: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let owned: Vec<(String, String)> = files
            .iter()
            .map(|(name, text)| ((*name).to_string(), (*text).to_string()))
            .collect();
        move |name: &str| {
            owned
                .iter()
                .find(|(candidate, _)| candidate == name)
                .map(|(_, text)| text.clone())
        }
    }

    #[test]
    fn a_fingerprint_module_in_the_stacks_own_file_is_found() {
        let stack = "auth sufficient pam_fprintd.so # chwd-fprintd\nauth include system-auth\n";
        let read = read_stack(&[("system-auth", "auth required pam_unix.so\n")]);
        assert!(pam_stack_has_fingerprint(stack, PAM_DEPTH, &read));
    }

    #[test]
    fn a_fingerprint_module_reached_through_an_include_is_found() {
        let stack = "@include common-auth\n@include common-account\n";
        let read = read_stack(&[
            ("common-auth", "auth sufficient pam_fprintd.so\n"),
            ("common-account", "account required pam_unix.so\n"),
        ]);
        assert!(pam_stack_has_fingerprint(stack, PAM_DEPTH, &read));
    }

    #[test]
    fn a_stack_without_a_reader_is_a_stack_without_a_reader() {
        let stack = "auth include system-auth\naccount include system-auth\n";
        let read = read_stack(&[(
            "system-auth",
            "auth required pam_faillock.so preauth\nauth required pam_unix.so\n",
        )]);
        assert!(!pam_stack_has_fingerprint(stack, PAM_DEPTH, &read));

        assert!(!pam_stack_has_fingerprint(
            stack,
            PAM_DEPTH,
            &read_stack(&[])
        ));
    }

    #[test]
    fn a_stack_that_includes_itself_ends_rather_than_hanging() {
        let read = read_stack(&[("loop", "auth include loop\n")]);
        assert!(!pam_stack_has_fingerprint(
            "auth include loop\n",
            PAM_DEPTH,
            &read
        ));
    }

    #[test]
    fn only_a_listed_reader_counts_as_a_reader() {
        assert!(readers_listed(
            "ao 1 \"/net/reactivated/Fprint/Device/0\"\n"
        ));
        assert!(!readers_listed("ao 0\n"));
        assert!(!readers_listed(""));
        assert!(!readers_listed(
            "Failed to call method: The name net.reactivated.Fprint was not provided\n"
        ));
    }

    #[test]
    fn only_a_listed_print_counts_as_an_enrolled_finger() {
        assert!(prints_listed(
            "User camus has 2 fingerprints enrolled:\n - #0: right-index-finger\n - #1: left-thumb\n"
        ));
        assert!(!prints_listed("User camus has no fingerprints enrolled.\n"));
        assert!(!prints_listed(""));
        assert!(!prints_listed(
            "Failed to list fingerprints: Not Authorized\n"
        ));
    }

    #[test]
    fn the_fingerprint_credential_publishes_a_helper_that_refuses() {
        let credential = Credential::fingerprint().expect("a credential");
        let helper = credential.helper_path();
        assert!(helper.is_file(), "{}", helper.display());

        let status = std::process::Command::new(&helper)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .expect("the helper runs");
        assert!(!status.success(), "the helper must not answer");

        let wrapper = fs::read_to_string(credential.dir.join(WRAPPER)).expect("the wrapper");
        assert!(wrapper.contains(&helper.display().to_string()), "{wrapper}");
        let environment = credential.environment();
        assert!(
            environment.iter().any(
                |(key, value)| *key == "SUDO_ASKPASS" && value == &helper.display().to_string()
            )
        );
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
        let sudo = fake_sudo(work.path(), "sudo", "exec sleep 60");

        let started = Instant::now();
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
        let credential = a_credential();
        let pipe = credential.dir.join(PIPE);
        for attempt in 1..=5 {
            let served = read_secret_within(&pipe, Duration::from_secs(20));
            assert_eq!(served.ok().as_deref(), Some("hunter2"), "attempt {attempt}");
        }
    }
}
