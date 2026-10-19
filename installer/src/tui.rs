#[cfg(unix)]
use std::fs::{File, OpenOptions};
use std::io::{self, Stdout, Write};
use std::path::Path;
#[cfg(unix)]
use std::sync::atomic::{AtomicI32, Ordering};

use ratatui::Frame;
use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};

pub struct Screen(Handle);

enum Handle {
    #[cfg(unix)]
    Terminal(File),
    Stdout(Stdout),
}

impl Screen {
    fn take() -> Self {
        #[cfg(unix)]
        {
            use std::os::fd::FromRawFd;

            let handle = unsafe { libc::dup(libc::STDOUT_FILENO) };
            if handle >= 0 {
                return Self(Handle::Terminal(unsafe { File::from_raw_fd(handle) }));
            }
        }
        Self(Handle::Stdout(io::stdout()))
    }
}

impl Write for Screen {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        match &mut self.0 {
            #[cfg(unix)]
            Handle::Terminal(file) => file.write(buffer),
            Handle::Stdout(stdout) => stdout.write(buffer),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match &mut self.0 {
            #[cfg(unix)]
            Handle::Terminal(file) => file.flush(),
            Handle::Stdout(stdout) => stdout.flush(),
        }
    }
}

#[cfg(unix)]
static LISTENING_OUT: AtomicI32 = AtomicI32::new(-1);
#[cfg(unix)]
static LISTENING_ERR: AtomicI32 = AtomicI32::new(-1);

#[cfg(unix)]
fn hand_over(log: &Path) {
    use std::os::fd::AsRawFd;

    let Ok(sink) = OpenOptions::new().create(true).append(true).open(log) else {
        return;
    };
    if LISTENING_OUT.load(Ordering::SeqCst) >= 0 {
        return;
    }
    let out = unsafe { libc::dup(libc::STDOUT_FILENO) };
    let err = unsafe { libc::dup(libc::STDERR_FILENO) };
    if out < 0 || err < 0 {
        return;
    }
    LISTENING_OUT.store(out, Ordering::SeqCst);
    LISTENING_ERR.store(err, Ordering::SeqCst);
    unsafe {
        libc::dup2(sink.as_raw_fd(), libc::STDOUT_FILENO);
        libc::dup2(sink.as_raw_fd(), libc::STDERR_FILENO);
    }
}

#[cfg(unix)]
fn give_back() {
    let out = LISTENING_OUT.swap(-1, Ordering::SeqCst);
    let err = LISTENING_ERR.swap(-1, Ordering::SeqCst);
    if out >= 0 {
        unsafe {
            libc::dup2(out, libc::STDOUT_FILENO);
            libc::close(out);
        }
    }
    if err >= 0 {
        unsafe {
            libc::dup2(err, libc::STDERR_FILENO);
            libc::close(err);
        }
    }
}

#[cfg(not(unix))]
fn hand_over(_log: &Path) {}

#[cfg(not(unix))]
fn give_back() {}

fn keep_the_terminal() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        give_back();
        let _ = disable_raw_mode();
        let mut terminal = io::stdout();
        let _ = terminal.write_all(b"\x1b[?25h\x1b[?1049l");
        let _ = terminal.flush();
        previous(info);
    }));
}

pub struct Tui {
    terminal: ratatui::Terminal<CrosstermBackend<Screen>>,
}

impl Tui {
    pub fn start(log: &Path) -> io::Result<Self> {
        let mut screen = Screen::take();
        enable_raw_mode()?;
        execute!(screen, EnterAlternateScreen)?;
        let terminal = ratatui::Terminal::new(CrosstermBackend::new(screen))?;
        hand_over(log);
        keep_the_terminal();
        Ok(Self { terminal })
    }

    pub fn draw<F>(&mut self, render: F) -> io::Result<()>
    where
        F: FnOnce(&mut Frame),
    {
        self.terminal.draw(render).map(|_| ())
    }

    pub fn repaint(&mut self) {
        let _ = self.terminal.clear();
    }

    pub fn finish(mut self) {
        let _ = self.terminal.show_cursor();
        let _ = execute!(self.terminal.backend_mut(), LeaveAlternateScreen);
        let _ = disable_raw_mode();
        give_back();
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::io::Write;
    use std::os::fd::FromRawFd;
    use std::sync::{Mutex, OnceLock};

    use super::*;

    fn one_at_a_time() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn write_to_inherited_output(line: &str) -> io::Result<()> {
        let mut inherited = unsafe { File::from_raw_fd(libc::dup(libc::STDOUT_FILENO)) };
        inherited.write_all(line.as_bytes())?;
        inherited.flush()
    }

    #[test]
    fn what_a_step_started_writes_lands_in_the_log_rather_than_on_the_screen() {
        let _turn = one_at_a_time();
        let directory = crate::tmp::TempDir::new("caelestia-tui-test").expect("a temporary dir");
        let log = directory.path().join("install.log");

        hand_over(&log);
        let written = write_to_inherited_output("Detected locale \"C\"\n");
        give_back();

        assert!(written.is_ok(), "the inherited output is writable");
        let logged = std::fs::read_to_string(&log).expect("the log was written");
        assert!(logged.contains("Detected locale"), "{logged}");
    }

    #[test]
    fn the_output_is_handed_back_so_what_prints_next_is_not_a_log_line() {
        let _turn = one_at_a_time();
        let directory =
            crate::tmp::TempDir::new("caelestia-tui-give-back").expect("a temporary dir");
        let log = directory.path().join("install.log");

        hand_over(&log);
        hand_over(&log);
        give_back();
        let written = write_to_inherited_output("this line belongs on the screen\n");

        assert!(written.is_ok(), "the terminal is back: {written:?}");
        let logged = std::fs::read_to_string(&log).unwrap_or_default();
        assert!(
            !logged.contains("this line belongs on the screen"),
            "the output is still going to the log after giving it back: {logged}"
        );
    }

    #[test]
    fn the_screen_the_wizard_draws_on_outlives_the_output_being_handed_over() {
        let _turn = one_at_a_time();
        let directory = crate::tmp::TempDir::new("caelestia-tui-screen").expect("a temp dir");
        let log = directory.path().join("install.log");

        let mut screen = Screen::take();
        hand_over(&log);
        let drawn = screen.write_all(b"the frame");
        give_back();

        assert!(drawn.is_ok(), "the wizard keeps its own handle: {drawn:?}");
    }
}
