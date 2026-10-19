use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::layout::Rect;

use crate::env::Env;
use crate::exit::Outcome;
use crate::glyphs::Glyphs;
use crate::logline::LogLine;
use crate::menu::{self, Answers, Entry};
use crate::privileges::{self, Credential, Inhibitor};
use crate::runner::Running;
use crate::signals;
use crate::steps::{self, STEPS, Status};
use crate::theme::Theme;
use crate::ui::{self, Key};

const FAILURE_TAIL: usize = 6;

pub fn log_path() -> PathBuf {
    std::env::var_os("CAELESTIA_INSTALL_LOG")
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("caelestia-install.log"))
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Action {
    Install,
    Update,
    Uninstall,
}

impl Action {
    pub const ALL: [Action; 3] = [Action::Install, Action::Update, Action::Uninstall];

    pub fn title(self) -> &'static str {
        match self {
            Action::Install => "Install Caelestia",
            Action::Update => "Update this install",
            Action::Uninstall => "Uninstall Caelestia",
        }
    }

    pub fn header(self) -> &'static str {
        match self {
            Action::Install => "install",
            Action::Update => "update",
            Action::Uninstall => "uninstall",
        }
    }

    pub fn unavailable(self) -> &'static str {
        match self {
            Action::Update | Action::Uninstall => "Install Caelestia first",
            Action::Install => "Caelestia is already installed",
        }
    }

    fn handoff(self) -> Option<Handoff> {
        match self {
            Action::Install => None,
            Action::Update => Some(Handoff::Update),
            Action::Uninstall => Some(Handoff::Uninstall),
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Stage {
    Home,
    Detect,
    Options,
    Auth,
    Privilege,
    Run,
    Done,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Overlay {
    Keys,
    Log,
    Failure,
    Confirm,
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Confirm {
    Handoff(Action),
    Install,
    Quit,
    LogOut,
}

impl Confirm {
    pub fn buttons(self) -> &'static [&'static str] {
        match self {
            Confirm::Handoff(Action::Update) => &["Update now", "Cancel"],
            Confirm::Handoff(Action::Uninstall) => &["Uninstall now", "Cancel"],
            Confirm::Handoff(Action::Install) | Confirm::Install => &["Install", "Cancel"],
            Confirm::Quit => &["Stop", "Keep going"],
            Confirm::LogOut => &["Log out", "Not now"],
        }
    }

    pub fn focus(self) -> usize {
        match self {
            Confirm::Quit | Confirm::LogOut => 1,
            _ => 0,
        }
    }

    pub fn shortcut(self, letter: char) -> Option<usize> {
        match letter {
            'y' | 'Y' => Some(0),
            'n' | 'N' => Some(self.buttons().len() - 1),
            _ => None,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum AuthMethod {
    Fingerprint,
    Password,
}

impl AuthMethod {
    pub fn title(self) -> &'static str {
        match self {
            AuthMethod::Fingerprint => "Touch the fingerprint reader",
            AuthMethod::Password => "Type your password here",
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Handoff {
    Update,
    Uninstall,
    LogOut,
}

pub struct Session {
    pub outcome: Outcome,
    pub handoff: Option<Handoff>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Detection {
    pub distro: crate::distro::Distro,
    pub kind: crate::install_kind::Kind,
    pub installed: bool,
    pub package_manager: Option<&'static str>,
    pub quickshell: bool,
    pub git: bool,
}

impl Detection {
    pub fn read() -> Self {
        let distro = crate::distro::detect();
        let package_manager = match distro {
            crate::distro::Distro::Arch => Some("pacman"),
            crate::distro::Distro::Fedora => Some("dnf"),
            crate::distro::Distro::Debian => Some("apt"),
            crate::distro::Distro::Unknown => None,
        }
        .filter(|name| crate::process::available(name));
        Self {
            distro,
            kind: crate::install_kind::kind(),
            installed: crate::install_kind::shell_config().exists(),
            package_manager,
            quickshell: crate::process::available("quickshell"),
            git: crate::process::available("git"),
        }
    }

    pub fn distro_label(&self) -> &'static str {
        self.distro.label()
    }

    pub fn kind_label(&self) -> &'static str {
        self.kind.label()
    }

    pub fn blockers(&self) -> Vec<&'static str> {
        let mut blockers = Vec::new();
        if self.distro == crate::distro::Distro::Unknown {
            blockers.push("This distribution is not one the installer knows how to install on.");
            return blockers;
        }
        if self.package_manager.is_none() {
            blockers.push("No supported package manager was found on PATH.");
        }
        if !self.git && self.kind == crate::install_kind::Kind::Source {
            blockers.push("git is missing, and a source install needs it.");
        }
        blockers
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Flow {
    Continue,
    Done(Outcome),
}

pub struct Choice {
    pub key: char,
    pub label: &'static str,
    pub help: &'static str,
}

pub struct FailureCard {
    pub step: &'static str,
    pub detail: Vec<LogLine>,
    pub choice: usize,
    id: &'static str,
}

impl FailureCard {
    pub const CHOICES: [Choice; 4] = [
        Choice {
            key: 'r',
            label: "Retry",
            help: "",
        },
        Choice {
            key: 's',
            label: "Skip",
            help: "record it as switched off, and continue",
        },
        Choice {
            key: 'i',
            label: "Ignore",
            help: "continue, and report the install as failed",
        },
        Choice {
            key: 'q',
            label: "Stop",
            help: "",
        },
    ];

    pub fn new(step: &'static steps::Step, log: &[LogLine]) -> Self {
        let detail = log.iter().rev().take(FAILURE_TAIL).rev().cloned().collect();
        Self {
            step: step.name,
            id: step.id,
            detail,
            choice: 0,
        }
    }

    pub fn reproduction(&self) -> String {
        format!("caelestia-install step {}", self.id)
    }
}

pub struct App {
    pub bundle: PathBuf,
    pub log_path: PathBuf,
    pub env: Env,
    pub theme: Theme,
    pub glyphs: Glyphs,
    pub apps: crate::apps::Apps,
    pub fingerprint: bool,
    pub needs_password: bool,
    pub detection: Detection,
    pub reinstall_acknowledged: bool,
    pub installed_when_started: bool,
    pub unfinished: Vec<(String, Status)>,
    pub stage: Stage,
    pub overlay: Option<Overlay>,
    pub confirm: Option<Confirm>,
    pub action: Action,
    pub home: usize,
    pub answers: Answers,
    baseline: Answers,
    pub question: usize,
    pub cursor: usize,
    pub auth: Option<AuthMethod>,
    pub password: String,
    pub(crate) checking: Option<std::sync::mpsc::Receiver<bool>>,
    pub pretend: bool,
    pub attempts: usize,
    pub fingerprint_spent: bool,
    pub problem: Option<String>,
    pub notice: Option<String>,
    pub failure: Option<FailureCard>,
    pub paused: bool,
    pub statuses: Vec<Status>,
    pub current: usize,
    pub log: Vec<LogLine>,
    pub log_follow: bool,
    pub log_scroll: usize,
    pub log_loud_only: bool,
    pub log_problem: Option<usize>,
    pub confirm_focus: usize,
    pub area: Rect,
    pub spinner: usize,
    durations: Vec<Option<Duration>>,
    running_since: Option<Instant>,
    leaving: Option<Outcome>,
    handoff: Option<Handoff>,
    credential: Option<Credential>,
    inhibitor: Option<Inhibitor>,
    running: Option<Running>,
    pub repaint: bool,
    pub landed: Option<Landed>,
}

pub struct Landed {
    pub version: Option<String>,
    pub commit: Option<String>,
    pub branch: Option<String>,
    pub shell: PathBuf,
    pub configs: PathBuf,
    pub backup: Option<PathBuf>,
}

impl Landed {
    pub fn read(bundle: &Path) -> Self {
        let shell = crate::update::config_dir();
        let installed = crate::update_state::installed(&shell)
            .or_else(|| crate::update::published_version(bundle));
        let (version, commit, branch) = match installed {
            Some(installed) => (
                Some(installed.version),
                Some(installed.commit).filter(|commit| !commit.is_empty()),
                Some(installed.branch).filter(|branch| !branch.is_empty()),
            ),
            None => (None, None, None),
        };
        Self {
            version,
            commit,
            branch,
            shell,
            configs: crate::paths::home().join(".config").join("caelestia"),
            backup: crate::steps::recorded_backup_dir(bundle),
        }
    }
}

impl App {
    pub fn new(bundle: PathBuf, log_path: PathBuf, env: Env) -> Self {
        let mut answers = Answers::new();
        menu::seed_answers(&menu::QUESTIONS, &mut answers);
        let apps = crate::apps::Apps::here();
        for (id, answer) in apps.answers() {
            answers.insert(id, answer.to_string());
        }
        let baseline = answers.clone();
        let fingerprint = privileges::fingerprint_ready();
        Self {
            bundle,
            log_path,
            theme: Theme::resolve(&env),
            glyphs: Glyphs::resolve(&env),
            apps,
            fingerprint,
            needs_password: needs_password(),
            env,
            detection: Detection::read(),
            reinstall_acknowledged: false,
            installed_when_started: crate::install_kind::shell_config().exists(),
            unfinished: crate::journal::unfinished(),
            stage: Stage::Home,
            overlay: None,
            confirm: None,
            action: Action::Install,
            home: 0,
            answers,
            baseline,
            question: 0,
            cursor: 0,
            auth: None,
            password: String::new(),
            checking: None,
            pretend: false,
            attempts: 0,
            fingerprint_spent: false,
            problem: None,
            notice: None,
            failure: None,
            paused: false,
            statuses: vec![Status::Pending; STEPS.len()],
            current: 0,
            log: Vec::new(),
            log_follow: true,
            log_scroll: 0,
            log_loud_only: false,
            log_problem: None,
            confirm_focus: 0,
            area: Rect::new(0, 0, 0, 0),
            spinner: 0,
            durations: vec![None; STEPS.len()],
            running_since: None,
            leaving: None,
            handoff: None,
            credential: None,
            inhibitor: None,
            running: None,
            repaint: false,
            landed: None,
        }
    }

    #[cfg(test)]
    pub fn with_apps(mut self, apps: crate::apps::Apps) -> Self {
        let seeded: Vec<(&'static str, &'static str)> = apps.answers().collect();
        self.apps = apps;
        for (id, answer) in seeded {
            self.answers.insert(id, answer.to_string());
        }
        self.baseline = self.answers.clone();
        self
    }

    #[cfg(test)]
    pub fn with_fingerprint(mut self, ready: bool) -> Self {
        self.fingerprint = ready;
        self
    }

    #[cfg(test)]
    pub fn with_password_gate(mut self, needed: bool) -> Self {
        self.needs_password = needed;
        self
    }

    pub fn apply_settings(&mut self, settings: &[(&'static str, String)]) {
        menu::apply_set(settings, &mut self.answers);
        self.baseline = self.answers.clone();
    }

    pub fn header(&self) -> ui::Header {
        ui::Header {
            left: match self.stage {
                Stage::Home => "installer".to_string(),
                _ => self.action.header().to_string(),
            },
            right: format!(
                "{} · {} install",
                self.detection.distro_label(),
                self.detection.kind_label()
            ),
        }
    }

    pub fn counter(&self) -> Option<String> {
        match self.stage {
            Stage::Run => Some(format!("step {}/{}", self.finished(), STEPS.len())),
            Stage::Options => Some(format!(
                "question {}/{}",
                self.question + 1,
                menu::question_count()
            )),
            _ => None,
        }
    }

    pub fn finished(&self) -> usize {
        self.statuses
            .iter()
            .filter(|status| !matches!(status, Status::Pending | Status::Running))
            .count()
    }

    pub fn total_elapsed(&self) -> Duration {
        self.durations.iter().flatten().sum::<Duration>()
            + self
                .running_since
                .map(|since| since.elapsed())
                .unwrap_or_default()
    }

    pub fn running_step(&self) -> Option<usize> {
        self.statuses
            .iter()
            .position(|status| *status == Status::Running)
    }

    pub fn tally(&self) -> Tally {
        let count = |status: Status| self.statuses.iter().filter(|each| **each == status).count();
        Tally {
            warn: count(Status::Warn),
            failed: count(Status::Failed),
            ignored: count(Status::Ignored),
        }
    }

    pub fn current_entries(&self) -> Vec<&'static Entry> {
        menu::items_of(self.question).iter().collect()
    }

    pub fn selected(&self) -> Option<&'static Entry> {
        self.current_entries().into_iter().nth(self.cursor)
    }

    pub fn is_changed(&self, entry: &Entry) -> bool {
        menu::is_changed(entry, &self.answers, &self.baseline)
    }

    pub fn action_enabled(&self, action: Action) -> bool {
        match action {
            Action::Install => true,
            Action::Update | Action::Uninstall => self.installed(),
        }
    }

    pub fn installed(&self) -> bool {
        self.detection.installed
    }

    pub fn refresh_detection(&mut self) {
        if self.pretend {
            return;
        }
        self.detection = Detection::read();
        self.unfinished = crate::journal::unfinished();
        self.problem = None;
    }

    pub fn question_changed(&self, question: usize) -> bool {
        menu::items_of(question)
            .iter()
            .any(|entry| menu::holds_an_answer(entry) && self.is_changed(entry))
    }

    pub fn changed_answers(&self) -> usize {
        menu::every_entry()
            .into_iter()
            .filter(|entry| menu::holds_an_answer(entry) && self.is_changed(entry))
            .count()
    }

    pub fn visible_log(&self) -> Vec<&LogLine> {
        self.log
            .iter()
            .filter(|line| !self.log_loud_only || line.is_loud())
            .collect()
    }

    pub fn log_rows(&self) -> usize {
        ui::log_rows(self.run_layout().log).max(1) as usize
    }

    pub fn problem_rows(&self) -> Vec<usize> {
        self.visible_log()
            .iter()
            .enumerate()
            .filter(|(_, line)| line.is_loud())
            .map(|(row, _)| row)
            .collect()
    }

    fn jump_to_problem(&mut self, forward: bool, rows: usize) {
        let problems = self.problem_rows();
        let (Some(&first), Some(&last)) = (problems.first(), problems.last()) else {
            self.notice = Some("nothing in the log went wrong".to_string());
            return;
        };
        let from = self.log_problem.unwrap_or_else(|| {
            if self.log_follow {
                usize::MAX
            } else {
                self.log_window_for(rows).0
            }
        });
        let target = if forward {
            problems
                .iter()
                .copied()
                .find(|row| *row > from)
                .unwrap_or(first)
        } else {
            problems
                .iter()
                .copied()
                .rev()
                .find(|row| *row < from)
                .unwrap_or(last)
        };
        let at = problems.iter().position(|row| *row == target).unwrap_or(0);

        self.log_follow = false;
        self.log_scroll = target.saturating_sub(rows / 3);
        self.scroll_log(0, rows);
        self.log_problem = Some(target);
        self.notice = Some(format!("problem {} of {}", at + 1, problems.len()));
    }

    pub fn run_layout(&self) -> ui::RunLayout {
        ui::run_layout(ui::body(self.area))
    }

    pub fn next_step(&self) -> Option<usize> {
        self.statuses
            .iter()
            .position(|status| *status == Status::Pending)
    }

    pub fn log_window_for(&self, rows: usize) -> (usize, usize) {
        let rows = rows.max(1);
        let lines = self.visible_log();
        let start = if self.log_follow {
            lines.len().saturating_sub(rows)
        } else {
            self.log_scroll.min(lines.len().saturating_sub(rows))
        };
        (start, rows)
    }

    pub fn leaving(&self) -> Option<Outcome> {
        self.leaving
    }

    pub fn session(&self, outcome: Outcome) -> Session {
        Session {
            outcome,
            handoff: self.handoff,
        }
    }

    fn leave(&mut self, outcome: Outcome) {
        self.leaving = Some(outcome);
    }

    fn interrupt(&mut self) -> Flow {
        if self.overlay == Some(Overlay::Confirm) {
            return self.stop_and_leave();
        }
        if self.busy() {
            self.ask(Confirm::Quit);
            return Flow::Continue;
        }
        Flow::Done(Outcome::Interrupted)
    }

    fn busy(&self) -> bool {
        self.running.is_some() || self.running_step().is_some()
    }

    fn stop_and_leave(&mut self) -> Flow {
        self.stop_running();
        Flow::Done(Outcome::Interrupted)
    }

    fn stop_running(&mut self) {
        if let Some(mut running) = self.running.take() {
            running.stop();
        }
        self.running_since = None;
    }

    pub fn tick(&mut self) {
        if signals::terminated() {
            self.stop_running();
            self.leave(Outcome::Interrupted);
            return;
        }
        self.spinner = self.spinner.wrapping_add(1);
        if self.stage == Stage::Privilege {
            self.check_password();
        }
        if self.stage == Stage::Run && self.running.is_some() {
            self.progress();
        }
    }

    pub fn key(&mut self, key: KeyEvent) -> Flow {
        self.notice = None;

        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return self.interrupt();
        }
        if let Some(overlay) = self.overlay {
            return self.overlay_key(overlay, key);
        }
        if key.code == KeyCode::Char('t') && self.stage != Stage::Privilege {
            self.theme.cycle();
            self.notice = Some(format!("{} theme", self.theme.mode.name()));
            return Flow::Continue;
        }
        match self.stage {
            Stage::Home => self.home_key(key),
            Stage::Detect => self.detect_key(key),
            Stage::Options => self.options_key(key),
            Stage::Auth => self.auth_key(key),
            Stage::Privilege => self.privilege_key(key),
            Stage::Run => self.run_key(key),
            Stage::Done => self.done_key(key),
        }
    }

    pub fn keys(&self) -> Vec<Key> {
        let glyphs = self.glyphs;
        match self.overlay {
            Some(Overlay::Keys) => vec![ui::key(glyphs.escape(), "close")],
            Some(Overlay::Log) => {
                let mut keys = vec![
                    ui::key(glyphs.up_down(), "scroll"),
                    ui::key("w", "loud only"),
                    ui::key("f", "follow"),
                ];
                if !self.problem_rows().is_empty() {
                    keys.push(ui::key("n", "next problem"));
                    keys.push(ui::key("p", "previous"));
                }
                keys.push(ui::key(glyphs.escape(), "close"));
                keys
            }
            Some(Overlay::Failure) => vec![
                ui::key("r", "retry"),
                ui::key("s", "skip"),
                ui::key("i", "ignore"),
                ui::key("q", "stop"),
                ui::key(glyphs.escape(), "decide later"),
            ],
            Some(Overlay::Confirm) => vec![
                ui::key(glyphs.up_down(), "move"),
                ui::key(glyphs.enter(), "choose"),
            ],
            None => match self.stage {
                Stage::Home => vec![
                    ui::key(glyphs.up_down(), "choose"),
                    ui::key(glyphs.enter(), "run"),
                    ui::key("t", "theme"),
                    ui::key("?", "keys"),
                    ui::key("q", "quit"),
                ],
                Stage::Detect => {
                    let mut keys = vec![
                        ui::key(glyphs.enter(), "continue"),
                        ui::key(glyphs.escape(), "back"),
                    ];
                    if self.installed() {
                        keys.insert(1, ui::key("u", "update instead"));
                    }
                    keys
                }
                Stage::Auth => vec![
                    ui::key(glyphs.up_down(), "move"),
                    ui::key(glyphs.enter(), "choose"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Privilege if self.checking.is_some() => Vec::new(),
                Stage::Privilege if self.auth == Some(AuthMethod::Fingerprint) => {
                    vec![ui::key(glyphs.escape(), "back")]
                }
                Stage::Privilege if self.attempts > 0 => vec![
                    ui::key(glyphs.enter(), "continue"),
                    ui::key("r", "try again"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Privilege => vec![
                    ui::key(glyphs.enter(), "continue"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Options => vec![
                    ui::key(glyphs.enter(), "continue"),
                    ui::key(glyphs.up_down(), "move"),
                    ui::key(glyphs.left_right(), "change"),
                    ui::key(glyphs.escape(), "back"),
                    ui::key("r", "reset"),
                    ui::key("R", "reset all"),
                ],
                Stage::Run if self.paused => vec![
                    ui::key(glyphs.enter(), "the failure"),
                    ui::key("l", "log"),
                    ui::key("q", "quit"),
                ],
                Stage::Run => {
                    let mut keys = vec![
                        ui::key(glyphs.up_down(), "scroll"),
                        ui::key("f", "follow"),
                        ui::key("w", "loud only"),
                    ];
                    if !self.problem_rows().is_empty() {
                        keys.push(ui::key("n", "next problem"));
                        keys.push(ui::key("p", "previous"));
                    }
                    keys.push(ui::key("l", "log"));
                    keys.push(ui::key("q", "quit"));
                    keys
                }
                Stage::Done => {
                    let mut keys = Vec::new();
                    if self.tally().unresolved() > 0 {
                        keys.push(ui::key("r", "retry failed"));
                    }
                    keys.push(ui::key("l", "log"));
                    keys.push(ui::key(glyphs.enter(), "finish"));
                    keys.push(ui::key("q", "quit"));
                    keys
                }
            },
        }
    }

    fn home_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => self.home = self.step_action(-1),
            KeyCode::Down | KeyCode::Char('j') => self.home = self.step_action(1),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Enter | KeyCode::Char(' ') => return self.choose_action(),
            KeyCode::Esc | KeyCode::Char('q') => return Flow::Done(Outcome::Canceled),
            _ => {}
        }
        Flow::Continue
    }

    fn step_action(&self, direction: isize) -> usize {
        let count = Action::ALL.len() as isize;
        let mut index = self.home as isize;
        for _ in 0..count {
            index = (index + direction).rem_euclid(count);
            if self.action_enabled(Action::ALL[index as usize]) {
                return index as usize;
            }
        }
        self.home
    }

    fn choose_action(&mut self) -> Flow {
        let action = Action::ALL[self.home];
        if !self.action_enabled(action) {
            self.notice = Some(Action::unavailable(action).to_string());
            return Flow::Continue;
        }
        self.action = action;
        match action {
            Action::Install => {
                self.show_detection();
                self.stage = Stage::Detect;
            }
            Action::Update | Action::Uninstall => {
                self.ask(Confirm::Handoff(action));
            }
        }
        Flow::Continue
    }

    fn show_detection(&mut self) {
        self.refresh_detection();
        self.reinstall_acknowledged = false;
    }

    fn detect_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Enter | KeyCode::Char(' ') => {
                if !self.detection.blockers().is_empty() {
                    self.problem = Some("Sort out the above first.".to_string());
                    return Flow::Continue;
                }
                if self.installed() {
                    self.reinstall_acknowledged = true;
                }
                self.problem = None;
                self.question = 0;
                self.cursor = 0;
                self.stage = Stage::Options;
            }
            KeyCode::Char('u') if self.installed() => {
                self.home = Action::ALL
                    .iter()
                    .position(|action| *action == Action::Update)
                    .unwrap_or(self.home);
                self.action = Action::Update;
                self.ask(Confirm::Handoff(Action::Update));
            }
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Esc => {
                self.problem = None;
                self.stage = Stage::Home;
            }
            _ => {}
        }
        Flow::Continue
    }

    fn privilege_key(&mut self, key: KeyEvent) -> Flow {
        if self.checking.is_some() {
            return Flow::Continue;
        }
        if self.auth == Some(AuthMethod::Fingerprint) {
            match key.code {
                KeyCode::Enter | KeyCode::Char(' ') => {
                    self.start_check();
                    Flow::Continue
                }
                KeyCode::Esc => {
                    self.leave_the_gate();
                    Flow::Continue
                }
                _ => Flow::Continue,
            }
        } else {
            self.password_key(key)
        }
    }

    fn password_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Enter => {
                self.start_check();
                Flow::Continue
            }
            KeyCode::Char('r') if self.attempts > 0 => {
                self.start_check();
                Flow::Continue
            }
            KeyCode::Backspace => {
                self.password.pop();
                Flow::Continue
            }
            KeyCode::Esc => {
                self.leave_the_gate();
                Flow::Continue
            }
            KeyCode::Char(character) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                if !character.is_control() {
                    self.password.push(character);
                }
                Flow::Continue
            }
            _ => Flow::Continue,
        }
    }

    fn start_check(&mut self) {
        if self.checking.is_some() {
            return;
        }
        let fingerprint = self.auth == Some(AuthMethod::Fingerprint);
        if !fingerprint {
            if self.password.is_empty() {
                self.problem = Some("Type the password first.".to_string());
                return;
            }
            if !self.pretend && privileges::locked_out() {
                self.problem =
                    Some("Locked out for a few minutes after too many tries.".to_string());
                return;
            }
        }
        let (sender, receiver) = std::sync::mpsc::channel();
        if self.pretend {
            let _ = sender.send(true);
        } else {
            let secret = self.password.clone();
            thread::spawn(move || {
                let accepted = if fingerprint {
                    privileges::accepts_fingerprint()
                } else {
                    privileges::accepts(&secret)
                };
                let _ = sender.send(accepted);
            });
        }
        self.checking = Some(receiver);
        self.problem = None;
    }

    fn check_password(&mut self) {
        let Some(receiver) = self.checking.as_ref() else {
            return;
        };
        match receiver.try_recv() {
            Ok(true) => {
                self.checking = None;
                self.accept_password();
            }
            Ok(false) => {
                self.checking = None;
                self.password.clear();
                if self.auth == Some(AuthMethod::Fingerprint) {
                    let problem = self.refusal();
                    self.fingerprint_spent = true;
                    self.cursor = 0;
                    self.problem = Some(problem);
                    self.gate();
                    return;
                }
                self.attempts += 1;
                self.problem = Some(self.refusal());
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => {}
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                self.checking = None;
                self.problem = Some("The password could not be checked.".to_string());
            }
        }
    }

    fn refusal(&self) -> String {
        if self.auth == Some(AuthMethod::Fingerprint) {
            return "No finger was recognized. Type your password instead.".to_string();
        }
        if !self.pretend && privileges::on_the_last_entry() {
            "Not accepted. A wrong entry now locks the account.".to_string()
        } else {
            "That password was not accepted.".to_string()
        }
    }

    fn accept_password(&mut self) {
        if !self.pretend {
            let credential = if self.auth == Some(AuthMethod::Fingerprint) {
                Credential::fingerprint()
            } else {
                let exe =
                    std::env::current_exe().unwrap_or_else(|_| PathBuf::from("caelestia-install"));
                Credential::install(&self.password, &exe)
            };
            match credential {
                Ok(credential) => self.credential = Some(credential),
                Err(problem) => {
                    eprintln!("caelestia-install: {problem}");
                    self.problem = Some(problem);
                    self.leave(Outcome::Internal);
                    return;
                }
            }
        }
        self.password.clear();
        self.attempts = 0;
        self.problem = None;
        self.begin_install();
    }

    fn need_auth(&mut self) {
        if !self.needs_password {
            self.begin_install();
            return;
        }
        self.problem = None;
        self.cursor = 0;
        self.attempts = 0;
        self.gate();
    }

    fn gate(&mut self) {
        if self.auth_methods() == [AuthMethod::Password] {
            self.auth = Some(AuthMethod::Password);
            self.stage = Stage::Privilege;
        } else {
            self.auth = None;
            self.stage = Stage::Auth;
        }
    }

    fn leave_the_gate(&mut self) {
        self.password.clear();
        self.problem = None;
        self.attempts = 0;
        if self.auth_methods() == [AuthMethod::Password] {
            self.auth = None;
            self.stage = Stage::Options;
        } else {
            self.gate();
        }
    }

    pub fn auth_methods(&self) -> Vec<AuthMethod> {
        let mut methods = Vec::new();
        if self.fingerprint && !self.fingerprint_spent {
            methods.push(AuthMethod::Fingerprint);
        }
        methods.push(AuthMethod::Password);
        methods
    }

    fn auth_key(&mut self, key: KeyEvent) -> Flow {
        let methods = self.auth_methods();
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.cursor = if self.cursor == 0 {
                    methods.len() - 1
                } else {
                    self.cursor - 1
                };
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.cursor = (self.cursor + 1) % methods.len().max(1);
            }
            KeyCode::Enter | KeyCode::Char(' ') => {
                let Some(method) = methods.get(self.cursor).copied() else {
                    return Flow::Continue;
                };
                self.auth = Some(method);
                self.problem = None;
                self.attempts = 0;
                match method {
                    AuthMethod::Fingerprint => {
                        self.stage = Stage::Privilege;
                        self.start_check();
                    }
                    AuthMethod::Password => self.stage = Stage::Privilege,
                }
            }
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Esc => {
                self.problem = None;
                self.stage = Stage::Options;
            }
            _ => {}
        }
        Flow::Continue
    }

    fn options_key(&mut self, key: KeyEvent) -> Flow {
        let entries = self.current_entries();
        let rows = entries.len() + 1;
        self.cursor = self.cursor.min(rows - 1);
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.cursor = if self.cursor == 0 {
                    rows - 1
                } else {
                    self.cursor - 1
                };
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.cursor = (self.cursor + 1) % rows;
            }
            KeyCode::Char('r') => self.reset_highlighted(),
            KeyCode::Char('R') => self.reset_all(),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Char(' ') | KeyCode::Right | KeyCode::Char('l') => match self.selected() {
                Some(entry) => {
                    menu::change(entry, &mut self.answers);
                }
                None => self.next_question(),
            },
            KeyCode::Left | KeyCode::Char('h') => {
                if let Some(entry) = self.selected() {
                    menu::change(entry, &mut self.answers);
                }
            }
            KeyCode::Enter => self.next_question(),
            KeyCode::Esc => self.previous_question(),
            _ => {}
        }
        Flow::Continue
    }

    pub fn on_continue(&self) -> bool {
        self.cursor >= self.current_entries().len()
    }

    pub fn next_question(&mut self) {
        if self.question + 1 < menu::question_count() {
            self.question += 1;
            self.cursor = 0;
        } else {
            self.ask(Confirm::Install);
        }
    }

    pub fn previous_question(&mut self) {
        if self.question == 0 {
            self.stage = Stage::Detect;
        } else {
            self.question -= 1;
            self.cursor = 0;
        }
    }

    fn reset_highlighted(&mut self) {
        let Some(entry) = self.selected() else {
            return;
        };
        if menu::reset(entry, &mut self.answers, &self.baseline) {
            self.notice = Some(format!("{} reset", entry.title()));
        }
    }

    fn reset_all(&mut self) {
        self.answers = self.baseline.clone();
        self.notice = Some("every option is back at its default".to_string());
    }

    fn run_key(&mut self, key: KeyEvent) -> Flow {
        if self.paused && matches!(key.code, KeyCode::Enter | KeyCode::Char(' ')) {
            self.overlay = Some(Overlay::Failure);
            return Flow::Continue;
        }
        let rows = self.log_rows();
        match key.code {
            KeyCode::Up => self.scroll_log(-1, rows),
            KeyCode::Down => self.scroll_log(1, rows),
            KeyCode::PageUp => self.scroll_log(-(rows as isize), rows),
            KeyCode::PageDown => self.scroll_log(rows as isize, rows),
            KeyCode::Home | KeyCode::Char('g') => {
                self.log_follow = false;
                self.log_scroll = 0;
                self.log_problem = None;
            }
            KeyCode::End => {
                self.log_follow = true;
                self.log_problem = None;
            }
            KeyCode::Char('f') => {
                self.log_follow = !self.log_follow;
                self.log_problem = None;
                self.notice = Some(if self.log_follow {
                    "following the log".to_string()
                } else {
                    "log paused".to_string()
                });
            }
            KeyCode::Char('w') => self.toggle_loud_only(),
            KeyCode::Char('n') => self.jump_to_problem(true, rows),
            KeyCode::Char('p') => self.jump_to_problem(false, rows),
            KeyCode::Char('l') => self.overlay = Some(Overlay::Log),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Char('q') => self.ask(Confirm::Quit),
            _ => {}
        }
        Flow::Continue
    }

    fn scroll_log(&mut self, step: isize, rows: usize) {
        self.log_follow = false;
        self.log_problem = None;
        let furthest = self.visible_log().len().saturating_sub(rows) as isize;
        self.log_scroll = (self.log_scroll as isize + step).clamp(0, furthest) as usize;
    }

    fn toggle_loud_only(&mut self) {
        self.log_loud_only = !self.log_loud_only;
        self.log_scroll = 0;
        self.log_problem = None;
        self.notice = Some(if self.log_loud_only {
            "showing warnings and errors only".to_string()
        } else {
            "showing every line".to_string()
        });
    }

    fn done_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Char('r') => self.retry_failed(),
            KeyCode::Char('l') => self.overlay = Some(Overlay::Log),
            KeyCode::Char('o') if self.can_log_out() => self.ask(Confirm::LogOut),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Enter | KeyCode::Char(' ') | KeyCode::Esc | KeyCode::Char('q') => {
                return self.finish();
            }
            _ => {}
        }
        Flow::Continue
    }

    pub fn can_log_out(&self) -> bool {
        self.tally().unresolved() == 0
    }

    pub fn finish(&mut self) -> Flow {
        if self.tally().unresolved() > 0 {
            Flow::Done(Outcome::Failed)
        } else {
            Flow::Done(Outcome::Ok)
        }
    }

    fn overlay_key(&mut self, overlay: Overlay, key: KeyEvent) -> Flow {
        match overlay {
            Overlay::Keys => {
                if matches!(
                    key.code,
                    KeyCode::Esc | KeyCode::Enter | KeyCode::Char(' ') | KeyCode::Char('?')
                ) {
                    self.overlay = None;
                }
                Flow::Continue
            }
            Overlay::Log => self.log_overlay_key(key),
            Overlay::Failure => self.failure_key(key),
            Overlay::Confirm => self.confirm_key(key),
        }
    }

    fn log_overlay_key(&mut self, key: KeyEvent) -> Flow {
        let rows = ui::log_overlay_rows(self.area).max(1) as usize;
        match key.code {
            KeyCode::Esc | KeyCode::Char('l') => self.overlay = None,
            KeyCode::Up => self.scroll_log(-1, rows),
            KeyCode::Down => self.scroll_log(1, rows),
            KeyCode::PageUp => self.scroll_log(-(rows as isize), rows),
            KeyCode::PageDown => self.scroll_log(rows as isize, rows),
            KeyCode::Home | KeyCode::Char('g') => {
                self.log_follow = false;
                self.log_scroll = 0;
                self.log_problem = None;
            }
            KeyCode::End | KeyCode::Char('G') => {
                self.log_follow = true;
                self.log_problem = None;
            }
            KeyCode::Char('f') => {
                self.log_follow = !self.log_follow;
                self.log_problem = None;
            }
            KeyCode::Char('w') => self.toggle_loud_only(),
            KeyCode::Char('n') => self.jump_to_problem(true, rows),
            KeyCode::Char('p') => self.jump_to_problem(false, rows),
            _ => {}
        }
        Flow::Continue
    }

    fn failure_key(&mut self, key: KeyEvent) -> Flow {
        if self.failure.is_none() {
            self.overlay = None;
            return Flow::Continue;
        }
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                if let Some(card) = self.failure.as_mut() {
                    card.choice = card.choice.saturating_sub(1);
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                if let Some(card) = self.failure.as_mut() {
                    card.choice = (card.choice + 1).min(FailureCard::CHOICES.len() - 1);
                }
            }
            KeyCode::Char('r') => return self.resolve_failure(0),
            KeyCode::Char('s') => return self.resolve_failure(1),
            KeyCode::Char('i') => return self.resolve_failure(2),
            KeyCode::Char('q') => return self.resolve_failure(3),
            KeyCode::Enter | KeyCode::Char(' ') => {
                let choice = self.failure.as_ref().map_or(0, |card| card.choice);
                return self.resolve_failure(choice);
            }
            KeyCode::Esc => {
                self.overlay = None;
                self.paused = true;
            }
            _ => {}
        }
        Flow::Continue
    }

    fn resolve_failure(&mut self, choice: usize) -> Flow {
        self.overlay = None;
        self.paused = false;
        match choice {
            0 => {
                self.statuses[self.current] = Status::Pending;
                self.durations[self.current] = None;
                self.start_next();
            }
            1 => {
                self.statuses[self.current] = Status::Skipped;
                self.current += 1;
                self.start_next();
            }
            2 => {
                self.statuses[self.current] = Status::Ignored;
                self.current += 1;
                self.start_next();
            }
            _ => {
                self.statuses[self.current] = Status::Failed;
                return Flow::Done(Outcome::Failed);
            }
        }
        Flow::Continue
    }

    fn confirm_key(&mut self, key: KeyEvent) -> Flow {
        let Some(confirm) = self.confirm else {
            self.overlay = None;
            return Flow::Continue;
        };
        let buttons = confirm.buttons().len();
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.confirm_focus = if self.confirm_focus == 0 {
                    buttons - 1
                } else {
                    self.confirm_focus - 1
                };
                return Flow::Continue;
            }
            KeyCode::Down | KeyCode::Char('j') | KeyCode::Tab => {
                self.confirm_focus = (self.confirm_focus + 1) % buttons;
                return Flow::Continue;
            }
            KeyCode::Enter | KeyCode::Char(' ') => {}
            KeyCode::Char(letter) => match confirm.shortcut(letter) {
                Some(index) => self.confirm_focus = index,
                None => return Flow::Continue,
            },
            KeyCode::Esc => {
                self.confirm = None;
                self.overlay = None;
                return Flow::Continue;
            }
            _ => return Flow::Continue,
        }
        let chosen = self.confirm_focus.min(buttons - 1);
        self.confirm = None;
        self.overlay = None;
        if chosen != 0 {
            return Flow::Continue;
        }
        match confirm {
            Confirm::Quit => self.stop_and_leave(),
            Confirm::Handoff(action) => {
                self.stop_running();
                self.handoff = action.handoff();
                Flow::Done(Outcome::Ok)
            }
            Confirm::Install => self.confirm_install(),
            Confirm::LogOut => {
                self.handoff = Some(Handoff::LogOut);
                self.finish()
            }
        }
    }

    pub(crate) fn ask(&mut self, confirm: Confirm) {
        self.confirm = Some(confirm);
        self.confirm_focus = confirm.focus();
        self.overlay = Some(Overlay::Confirm);
    }

    fn confirm_install(&mut self) -> Flow {
        self.refresh_detection();
        if self.detection.installed && !self.reinstall_acknowledged {
            self.problem = Some(if self.installed_when_started {
                "Caelestia is already installed on this machine.".to_string()
            } else {
                "Caelestia was installed while the wizard was open. Read this screen, then \
                 continue."
                    .to_string()
            });
            self.stage = Stage::Detect;
            return Flow::Continue;
        }
        if let Some(blocker) = self.detection.blockers().first() {
            self.problem = Some((*blocker).to_string());
            self.stage = Stage::Detect;
            return Flow::Continue;
        }
        self.need_auth();
        Flow::Continue
    }

    pub fn begin_install(&mut self) {
        if !self.pretend && self.inhibitor.is_none() {
            self.inhibitor = Some(Inhibitor::acquire());
        }
        self.stage = Stage::Run;
        self.statuses = vec![Status::Pending; STEPS.len()];
        self.durations = vec![None; STEPS.len()];
        self.current = 0;
        self.log.clear();
        self.log_scroll = 0;
        self.log_follow = true;
        self.log_problem = None;
        self.failure = None;
        self.paused = false;
        self.start_next();
    }

    pub fn retry_failed(&mut self) {
        let failed: Vec<usize> = self
            .statuses
            .iter()
            .enumerate()
            .filter(|(_, status)| matches!(status, Status::Failed | Status::Ignored))
            .map(|(index, _)| index)
            .collect();
        if failed.is_empty() {
            self.notice = Some("no step needs retrying".to_string());
            return;
        }
        for index in &failed {
            self.statuses[*index] = Status::Pending;
            self.durations[*index] = None;
        }
        self.current = failed[0];
        self.stage = Stage::Run;
        self.failure = None;
        self.paused = false;
        self.log_follow = true;
        self.log_problem = None;
        self.start_next();
    }

    pub fn start_next(&mut self) {
        while self.current < STEPS.len() {
            let index = self.current;
            if self.statuses[index] != Status::Pending {
                self.current += 1;
                continue;
            }
            if steps::is_skipped(&STEPS[index], &self.answers) {
                self.statuses[index] = Status::Skipped;
                self.durations[index] = Some(Duration::ZERO);
                self.log.push(LogLine::skip(format!(
                    "{} is switched off in the options",
                    STEPS[index].name
                )));
                self.current += 1;
                continue;
            }
            if self.pretend {
                self.statuses[index] = Status::Ok;
                self.durations[index] = Some(Duration::from_secs(2));
                self.log
                    .push(LogLine::ok(format!("{} finished", STEPS[index].name)));
                self.current += 1;
                continue;
            }
            self.statuses[index] = Status::Running;
            self.running_since = Some(Instant::now());
            let env = self.step_environment();
            let step = &STEPS[index];
            match Running::spawn_native(&self.bundle, step.id, &self.log_path, &env) {
                Ok(running) => {
                    self.running = Some(running);
                    return;
                }
                Err(problem) => {
                    self.statuses[index] = Status::Failed;
                    self.log.push(LogLine::error(problem));
                    self.failure = Some(FailureCard::new(step, &self.log));
                    self.paused = true;
                    return;
                }
            }
        }
        self.stage = Stage::Done;
        self.landed = Some(Landed::read(&self.bundle));
        self.credential = None;
        self.inhibitor = None;
    }

    pub fn step_environment(&self) -> Vec<(&'static str, String)> {
        let mut env = steps::environment(&self.answers, &self.bundle);
        if let Some(credential) = &self.credential {
            env.extend(credential.environment());
        }
        env
    }

    fn progress(&mut self) {
        let Some(mut running) = self.running.take() else {
            return;
        };
        let mut fresh: Vec<String> = Vec::new();
        running.drain(&mut fresh);
        self.log
            .extend(fresh.iter().map(|line| LogLine::parse(line)));
        match running.poll() {
            Ok(Some(status)) => {
                let outcome = running.outcome(status);
                self.statuses[self.current] = outcome;
                self.durations[self.current] = Some(
                    self.running_since
                        .take()
                        .map(|since| since.elapsed())
                        .unwrap_or_default(),
                );
                self.repaint = true;
                if outcome.is_failure() {
                    self.failure = Some(FailureCard::new(&STEPS[self.current], &self.log));
                    self.paused = true;
                } else {
                    self.current += 1;
                    self.start_next();
                }
            }
            Ok(None) => self.running = Some(running),
            Err(problem) => {
                self.statuses[self.current] = Status::Failed;
                self.repaint = true;
                self.durations[self.current] =
                    self.running_since.take().map(|since| since.elapsed());
                self.log.push(LogLine::error(problem));
                self.failure = Some(FailureCard::new(&STEPS[self.current], &self.log));
                self.paused = true;
            }
        }
    }
}

pub struct Tally {
    pub warn: usize,
    pub failed: usize,
    pub ignored: usize,
}

impl Tally {
    pub fn unresolved(&self) -> usize {
        self.failed + self.ignored
    }
}

fn needs_password() -> bool {
    !privileges::is_root() && !privileges::sudo_cached()
}

pub fn run(
    bundle: PathBuf,
    log_path: PathBuf,
    env: Env,
    settings: &[(&'static str, String)],
) -> Session {
    if !std::io::stdin().is_terminal() || !std::io::stdout().is_terminal() {
        eprintln!("caelestia-install: the installer needs a terminal to run");
        return Session {
            outcome: Outcome::Environment,
            handoff: None,
        };
    }
    signals::install();
    let mut terminal = match crate::tui::Tui::start(&log_path) {
        Ok(terminal) => terminal,
        Err(error) => {
            eprintln!("caelestia-install: cannot open a terminal: {error}");
            return Session {
                outcome: Outcome::Environment,
                handoff: None,
            };
        }
    };
    let mut app = App::new(bundle, log_path, env);
    app.apply_settings(settings);
    let outcome = event_loop(&mut terminal, &mut app);
    terminal.finish();
    app.session(outcome)
}

fn event_loop(terminal: &mut crate::tui::Tui, app: &mut App) -> Outcome {
    loop {
        if let Some(outcome) = app.leaving() {
            return outcome;
        }
        if std::mem::take(&mut app.repaint) {
            terminal.repaint();
        }
        if terminal
            .draw(|frame| crate::screens::draw(frame, app))
            .is_err()
        {
            return Outcome::Environment;
        }
        app.tick();
        if event::poll(Duration::from_millis(120)).unwrap_or(false) {
            match event::read() {
                Ok(Event::Key(key)) if key.kind == KeyEventKind::Press => {
                    if let Flow::Done(outcome) = app.key(key) {
                        return outcome;
                    }
                }
                Ok(_) => {}
                Err(_) => return Outcome::Environment,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::menu;

    fn app() -> App {
        let mut app = App::new(
            PathBuf::from("/tmp/caelestia"),
            PathBuf::from("/tmp/install.log"),
            Env::default(),
        )
        .with_apps(crate::apps::Apps::all())
        .with_fingerprint(false)
        .with_password_gate(true);
        app.unfinished.clear();
        app.area = Rect::new(0, 0, 100, 30);
        app.pretend = true;
        app
    }

    fn press(app: &mut App, code: KeyCode) -> Flow {
        app.key(KeyEvent::new(code, KeyModifiers::NONE))
    }

    fn char_key(app: &mut App, character: char) -> Flow {
        press(app, KeyCode::Char(character))
    }

    fn question_of(id: &str) -> usize {
        (0..menu::question_count())
            .find(|index| menu::items_of(*index).iter().any(|entry| entry.id() == id))
            .unwrap_or_else(|| panic!("{id} is not in a question"))
    }

    fn installable() -> Detection {
        Detection {
            distro: crate::distro::Distro::Arch,
            kind: crate::install_kind::Kind::Source,
            installed: false,
            package_manager: Some("pacman"),
            quickshell: true,
            git: true,
        }
    }

    fn run_with(statuses: &[Status]) -> App {
        let mut app = app();
        app.stage = Stage::Run;
        for (index, status) in statuses.iter().enumerate() {
            app.statuses[index] = *status;
        }
        app
    }

    #[test]
    fn home_offers_the_three_actions_and_moves_only_between_the_ones_that_run() {
        let mut nothing_installed = app();
        nothing_installed.detection = installable();
        assert_eq!(nothing_installed.stage, Stage::Home);
        assert_eq!(Action::ALL[nothing_installed.home], Action::Install);
        press(&mut nothing_installed, KeyCode::Down);
        assert_eq!(
            Action::ALL[nothing_installed.home],
            Action::Install,
            "the only reachable action"
        );
        press(&mut nothing_installed, KeyCode::Up);
        assert_eq!(Action::ALL[nothing_installed.home], Action::Install);

        let mut already_there = app();
        already_there.detection = Detection {
            installed: true,
            ..installable()
        };
        already_there.home = 1;
        let mut seen = Vec::new();
        for _ in 0..3 {
            seen.push(Action::ALL[already_there.home]);
            press(&mut already_there, KeyCode::Down);
        }
        assert_eq!(
            seen,
            vec![Action::Update, Action::Uninstall, Action::Install]
        );
        assert_eq!(
            Action::ALL[already_there.home],
            Action::Update,
            "and it wraps"
        );
    }

    #[test]
    fn choosing_install_reports_this_machine_before_anything_else() {
        let mut app = app();
        app.detection = installable();
        press(&mut app, KeyCode::Enter);
        assert_eq!(
            app.stage,
            Stage::Detect,
            "what is on the machine is read before anything is decided"
        );

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Options, "and then the questions start");
        assert_eq!(app.question, 0);
        assert_eq!(app.cursor, 0);
    }

    #[test]
    fn a_machine_that_cannot_be_installed_on_does_not_start_the_questions() {
        let mut app = app();
        app.detection = Detection {
            package_manager: None,
            ..installable()
        };
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Detect);

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Detect, "it stays where the reason is");
        assert_eq!(
            app.problem.as_deref(),
            Some("Sort out the above first."),
            "the answer to the key, in words the blocker above does not already use"
        );

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Home);
        assert_eq!(app.problem, None, "the screen's message goes with it");
    }

    #[test]
    fn a_bulk_choice_counts_as_the_answers_it_sets_and_not_as_itself() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of(menu::PRESET_THEME_APPS);
        app.cursor = 0;
        assert_eq!(app.changed_answers(), 0);

        char_key(&mut app, ' ');
        assert_eq!(
            app.changed_answers(),
            6,
            "six apps, not seven options: the row is not an answer"
        );

        char_key(&mut app, ' ');
        assert_eq!(app.changed_answers(), 0);
    }

    #[test]
    fn every_route_into_the_install_arrives_at_the_same_place() {
        let mut app = app();
        app.detection = installable();
        app.stage = Stage::Privilege;
        app.password = "hunter2".to_string();
        press(&mut app, KeyCode::Enter);
        app.tick();
        assert!(
            matches!(app.stage, Stage::Run | Stage::Done),
            "the password route starts the install like any other, got {:?}",
            app.stage
        );
    }

    #[test]
    fn an_update_is_not_offered_where_there_is_nothing_to_update() {
        let mut app = app();
        app.detection = installable();
        app.home = 1;
        assert_eq!(Action::ALL[app.home], Action::Update);

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Home, "nothing starts");
        assert_eq!(app.overlay, None, "and nothing is offered to confirm");
        assert_eq!(
            app.notice.as_deref(),
            Some(Action::unavailable(Action::Update)),
            "the answer to the key is what to do about it"
        );

        app.detection.installed = true;
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Handoff(Action::Update)));
    }

    #[test]
    fn the_theme_key_works_on_every_screen_but_the_password_one() {
        for stage in [
            Stage::Home,
            Stage::Detect,
            Stage::Options,
            Stage::Auth,
            Stage::Run,
            Stage::Done,
        ] {
            let mut app = app();
            app.stage = stage;
            let before = app.theme.mode;
            char_key(&mut app, 't');
            assert_ne!(app.theme.mode, before, "{stage:?} should flip the theme");
        }

        let mut app = app();
        app.stage = Stage::Privilege;
        let before = app.theme.mode;
        char_key(&mut app, 't');
        assert_eq!(app.theme.mode, before, "a password may contain a t");
        assert_eq!(app.password, "t", "and it is typed, not swallowed");
    }

    #[test]
    fn the_options_footer_keeps_the_way_on_and_loses_the_resets_first() {
        let mut app = app();
        app.stage = Stage::Options;
        let footer: Vec<&str> = app.keys().iter().map(|key| key.what).collect();
        let at = |needle: &str| {
            footer
                .iter()
                .position(|what| *what == needle)
                .unwrap_or_else(|| panic!("{needle} is missing from {footer:?}"))
        };
        assert!(at("continue") < at("reset"), "{footer:?}");
        assert!(at("back") < at("reset"), "{footer:?}");
        assert_eq!(
            footer.last(),
            Some(&"reset all"),
            "the least important hint is the one a narrow footer drops: {footer:?}"
        );
    }

    #[test]
    fn a_machine_that_already_has_caelestia_says_so_before_it_is_overwritten() {
        let mut app = app();
        app.detection = Detection {
            installed: true,
            ..installable()
        };
        app.detection.installed = true;
        app.installed_when_started = true;

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Detect);
        assert!(
            app.detection.installed,
            "the screen has something to report"
        );
        assert!(
            !app.reinstall_acknowledged,
            "and nothing has been acknowledged yet"
        );

        press(&mut app, KeyCode::Enter);
        assert!(app.reinstall_acknowledged);
        assert_eq!(app.stage, Stage::Options);

        app.ask(Confirm::Install);
        char_key(&mut app, 'y');
        assert_ne!(app.stage, Stage::Detect);
    }

    #[test]
    fn an_install_that_appeared_while_the_wizard_was_open_stops_at_the_confirmation() {
        let mut app = app();
        app.detection = installable();
        app.installed_when_started = false;
        app.ask(Confirm::Install);

        app.detection.installed = true;
        char_key(&mut app, 'y');

        assert_eq!(
            app.stage,
            Stage::Detect,
            "the wizard goes back to what it found rather than carrying on"
        );
        assert!(
            app.problem
                .as_deref()
                .unwrap_or_default()
                .contains("while the wizard was open"),
            "{:?}",
            app.problem
        );
    }

    #[test]
    fn a_machine_the_installer_cannot_install_on_says_why_and_stops() {
        let mut app = app();
        app.detection = Detection {
            package_manager: None,
            ..installable()
        };
        app.ask(Confirm::Install);
        app.reinstall_acknowledged = true;

        char_key(&mut app, 'y');
        assert_eq!(app.stage, Stage::Detect, "it stops rather than starting");
        assert!(
            app.problem
                .as_deref()
                .unwrap_or_default()
                .contains("package manager"),
            "{:?}",
            app.problem
        );
    }

    #[test]
    fn the_detection_screen_offers_the_update_route_when_there_is_one() {
        let mut app = app();
        app.detection = Detection {
            installed: true,
            ..installable()
        };
        app.detection.installed = true;
        app.stage = Stage::Detect;

        char_key(&mut app, 'u');
        assert_eq!(app.action, Action::Update);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Handoff(Action::Update)));
    }

    #[test]
    fn a_machine_with_nothing_installed_is_not_offered_an_update() {
        let mut app = app();
        app.detection = installable();
        app.stage = Stage::Detect;

        char_key(&mut app, 'u');
        assert_eq!(
            app.stage,
            Stage::Detect,
            "nothing to update, nothing to offer"
        );
        assert_eq!(app.overlay, None);
    }

    #[test]
    fn detection_reports_every_precondition_the_install_depends_on() {
        assert!(installable().blockers().is_empty());

        let no_manager = Detection {
            package_manager: None,
            ..installable()
        };
        assert_eq!(no_manager.blockers().len(), 1);

        let no_git = Detection {
            git: false,
            ..installable()
        };
        assert!(
            no_git
                .blockers()
                .iter()
                .any(|blocker| blocker.contains("git")),
            "{:?}",
            no_git.blockers()
        );

        let packaged_without_git = Detection {
            git: false,
            kind: crate::install_kind::Kind::Package,
            ..installable()
        };
        assert!(
            packaged_without_git.blockers().is_empty(),
            "a package install does not need git: {:?}",
            packaged_without_git.blockers()
        );

        let unknown = Detection {
            distro: crate::distro::Distro::Unknown,
            ..installable()
        };
        assert_eq!(unknown.blockers().len(), 1);
    }

    #[test]
    fn the_password_is_asked_for_last_because_it_is_needed_last() {
        let mut app = app();
        app.detection = installable();

        app.stage = Stage::Options;
        app.question = menu::question_count() - 1;
        app.cursor = app.current_entries().len();
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Install));
        assert_eq!(app.stage, Stage::Options, "and nothing has started yet");

        char_key(&mut app, 'y');
        assert_eq!(app.stage, Stage::Privilege);
        assert_eq!(app.auth, Some(AuthMethod::Password));
    }

    #[test]
    fn the_password_screen_is_only_reached_by_picking_the_password_route() {
        let mut app = app();
        app.detection = installable();
        app.stage = Stage::Auth;
        app.cursor = 0;

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.auth, Some(AuthMethod::Password));
        assert_eq!(app.stage, Stage::Privilege);
    }

    #[test]
    fn a_gate_with_one_route_asks_for_the_password_itself() {
        let mut app = app();
        app.need_auth();
        assert_eq!(app.auth, Some(AuthMethod::Password));
        assert_eq!(app.stage, Stage::Privilege);

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Options);
        assert_eq!(app.auth, None);
        assert_eq!(app.leaving(), None);
    }

    #[test]
    fn a_reader_that_is_there_is_offered_first_and_a_machine_without_one_is_not_asked_about_it() {
        let with_reader = app().with_fingerprint(true);
        assert_eq!(
            with_reader.auth_methods(),
            vec![AuthMethod::Fingerprint, AuthMethod::Password],
            "the reader is the only route that needs nothing typed, so it is first"
        );

        let without = app();
        assert_eq!(
            without.auth_methods(),
            vec![AuthMethod::Password],
            "a route that cannot open is not offered"
        );
    }

    #[test]
    fn the_reader_is_asked_as_soon_as_it_is_chosen() {
        let mut app = app().with_fingerprint(true);
        app.detection = installable();
        app.stage = Stage::Auth;
        app.cursor = 0;

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.auth, Some(AuthMethod::Fingerprint));
        assert_eq!(app.stage, Stage::Privilege);
        assert!(
            app.checking.is_some(),
            "choosing the reader is the whole question: the read starts on the key"
        );

        assert_eq!(app.password, "");
        app.tick();
        assert_eq!(
            app.password, "",
            "a finger is not a password and must not become one"
        );
        assert_ne!(
            app.stage,
            Stage::Privilege,
            "an accepted read carries on like any other route"
        );
    }

    #[test]
    fn a_read_that_did_not_happen_hands_the_gate_to_the_password_rather_than_asking_again() {
        let mut app = app().with_fingerprint(true);
        app.stage = Stage::Privilege;
        app.auth = Some(AuthMethod::Fingerprint);

        let (sender, receiver) = std::sync::mpsc::channel();
        sender.send(false).expect("the answer fits");
        app.checking = Some(receiver);
        app.tick();

        assert_eq!(
            app.stage,
            Stage::Privilege,
            "the gate asks for the password"
        );
        assert_eq!(app.auth, Some(AuthMethod::Password));
        assert_eq!(
            app.auth_methods(),
            vec![AuthMethod::Password],
            "the route that cannot open is gone"
        );
        assert!(app.fingerprint_spent);
        assert_eq!(
            app.problem.as_deref(),
            Some("No finger was recognized. Type your password instead."),
            "and says what happened, not what a wrong password means"
        );
        assert_eq!(app.attempts, 0, "the reader is not the password's count");

        assert!(
            !app.auth_methods().contains(&AuthMethod::Fingerprint),
            "and it stays gone"
        );
    }

    #[test]
    fn keys_do_not_go_into_a_reader() {
        let mut app = app().with_fingerprint(true);
        app.stage = Stage::Privilege;
        app.auth = Some(AuthMethod::Fingerprint);

        for character in "hunter2".chars() {
            char_key(&mut app, character);
        }
        press(&mut app, KeyCode::Backspace);
        assert_eq!(app.password, "", "the field is not there to type into");

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Auth);
        assert_eq!(app.auth, None);
    }

    #[test]
    fn update_and_uninstall_confirm_before_handing_the_terminal_over() {
        for (index, action, handoff) in [
            (1, Action::Update, Handoff::Update),
            (2, Action::Uninstall, Handoff::Uninstall),
        ] {
            let mut app = app();
            app.detection.installed = true;
            app.home = index;
            assert_eq!(Action::ALL[app.home], action);

            assert_eq!(press(&mut app, KeyCode::Enter), Flow::Continue);
            assert_eq!(app.overlay, Some(Overlay::Confirm));
            assert_eq!(app.confirm, Some(Confirm::Handoff(action)));

            char_key(&mut app, 'n');
            assert_eq!(app.overlay, None);
            assert_eq!(app.leaving(), None);

            press(&mut app, KeyCode::Enter);
            char_key(&mut app, 'y');
            let session = app.session(Outcome::Ok);
            assert_eq!(session.handoff, Some(handoff));
            assert_eq!(app.leaving(), None, "the handoff is the caller's job");
        }
    }

    #[test]
    fn the_confirmation_is_answered_by_the_button_under_the_highlight() {
        let mut app = app();
        app.detection.installed = true;
        app.home = 2;
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.confirm, Some(Confirm::Handoff(Action::Uninstall)));
        assert_eq!(
            app.confirm_focus, 0,
            "the action is what the user came here to do"
        );

        press(&mut app, KeyCode::Down);
        assert_eq!(app.confirm_focus, 1, "the other button is reachable");
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.overlay, None, "choosing cancel closes the question");
        assert_eq!(app.leaving(), None, "and nothing happened");

        press(&mut app, KeyCode::Enter);
        press(&mut app, KeyCode::Enter);
        assert_eq!(
            app.session(Outcome::Ok).handoff,
            Some(Handoff::Uninstall),
            "the highlighted button is what enter chooses"
        );
    }

    #[test]
    fn stopping_a_run_does_not_put_the_stopping_button_under_the_highlight() {
        let mut app = app();
        app.stage = Stage::Run;
        app.statuses[0] = Status::Running;
        char_key(&mut app, 'q');
        assert_eq!(app.confirm, Some(Confirm::Quit));
        assert_eq!(app.confirm_focus, 1, "the safe answer is the focused one");

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.leaving(), None, "the run carries on");
        assert_eq!(app.overlay, None);
    }

    #[test]
    fn uninstall_is_refused_where_there_is_nothing_installed() {
        let mut app = app();
        app.detection.installed = false;
        app.home = 2;
        char_key(&mut app, ' ');
        assert_eq!(app.stage, Stage::Home);
        assert!(app.notice.is_some(), "and it says why");
        assert_eq!(app.overlay, None);
    }

    #[test]
    fn esc_steps_back_rather_than_leaving() {
        let mut solo = app();
        solo.need_auth();
        assert_eq!(solo.stage, Stage::Privilege);
        char_key(&mut solo, 'x');
        press(&mut solo, KeyCode::Esc);
        assert_eq!(
            solo.stage,
            Stage::Options,
            "the gate hands back to the answers"
        );
        assert_eq!(solo.password, "", "and it forgets the password");
        assert_eq!(solo.leaving(), None);

        let mut with_reader = app().with_fingerprint(true);
        with_reader.auth = Some(AuthMethod::Fingerprint);
        with_reader.stage = Stage::Privilege;
        press(&mut with_reader, KeyCode::Esc);
        assert_eq!(
            with_reader.stage,
            Stage::Auth,
            "the routes are where the choice was made"
        );
        assert_eq!(with_reader.auth, None);

        solo.stage = Stage::Options;
        solo.question = menu::question_count() - 1;
        for expected in (0..menu::question_count() - 1).rev() {
            press(&mut solo, KeyCode::Esc);
            assert_eq!(solo.question, expected);
        }
        press(&mut solo, KeyCode::Esc);
        assert_eq!(solo.stage, Stage::Detect);
        press(&mut solo, KeyCode::Esc);
        assert_eq!(solo.stage, Stage::Home);
        assert_eq!(solo.leaving(), None);
    }

    #[test]
    fn quitting_from_home_is_a_cancel_and_not_an_interruption() {
        let mut app = app();
        assert_eq!(press(&mut app, KeyCode::Esc), Flow::Done(Outcome::Canceled));
        assert_eq!(char_key(&mut app, 'q'), Flow::Done(Outcome::Canceled));
    }

    #[test]
    fn the_steps_are_told_this_run_is_an_install() {
        let env = app().step_environment();
        assert!(
            env.iter()
                .any(|(key, value)| *key == "CAELESTIA_FRESH_INSTALL" && value == "1"),
            "{env:?}"
        );
    }

    #[test]
    fn a_bad_password_is_asked_for_again_and_never_kept() {
        let mut app = app();
        app.stage = Stage::Privilege;
        for character in "hunter2".chars() {
            char_key(&mut app, character);
        }
        assert_eq!(app.password, "hunter2");
        press(&mut app, KeyCode::Backspace);
        assert_eq!(app.password, "hunter");
    }

    #[test]
    fn the_check_runs_off_the_draw_path_and_the_wait_is_visible() {
        let mut app = app();
        app.stage = Stage::Privilege;
        for character in "hunter2".chars() {
            char_key(&mut app, character);
        }
        press(&mut app, KeyCode::Enter);
        assert!(
            app.checking.is_some(),
            "the check has to run somewhere the frame can carry on without it"
        );
        assert_eq!(
            app.password, "hunter2",
            "the password is still needed for the steps"
        );
        assert_eq!(app.stage, Stage::Privilege, "and nothing has moved on yet");
        assert!(
            app.keys().is_empty(),
            "no key does anything while sudo has it"
        );

        press(&mut app, KeyCode::Enter);
        char_key(&mut app, 'x');
        assert_eq!(app.password, "hunter2");

        app.tick();
        assert!(
            matches!(app.stage, Stage::Run | Stage::Done),
            "the password was the last thing asked for, so the work starts, got {:?}",
            app.stage
        );
        assert!(
            app.statuses.iter().any(|status| *status != Status::Pending),
            "and the steps are under way"
        );
        assert_eq!(
            app.password, "",
            "the password leaves the field once it is used"
        );
    }

    #[test]
    fn a_refused_password_is_asked_for_again() {
        let mut app = app();
        app.stage = Stage::Privilege;
        app.password = "wrong".to_string();
        let (sender, receiver) = std::sync::mpsc::channel();
        sender.send(false).expect("the answer fits");
        app.checking = Some(receiver);

        app.tick();
        assert_eq!(app.stage, Stage::Privilege, "a refusal keeps the gate open");
        assert_eq!(app.attempts, 1);
        assert_eq!(app.password, "");
        assert!(
            app.problem
                .as_deref()
                .unwrap_or_default()
                .contains("accepted"),
            "the gate has to say it was refused: {:?}",
            app.problem
        );
    }

    #[test]
    fn a_control_chord_never_becomes_part_of_the_password() {
        let mut app = app();
        app.stage = Stage::Privilege;
        for character in "hunter2".chars() {
            char_key(&mut app, character);
        }
        for code in [
            KeyCode::Char('j'),
            KeyCode::Char('a'),
            KeyCode::Char('u'),
            KeyCode::Char('h'),
        ] {
            app.key(KeyEvent::new(code, KeyModifiers::CONTROL));
        }
        assert_eq!(
            app.password, "hunter2",
            "a chord is not a character of a password"
        );
    }

    #[test]
    fn the_run_screen_names_the_step_it_is_on_and_the_one_that_comes_next() {
        let mut app = run_with(&[Status::Ok, Status::Running]);
        assert_eq!(app.running_step(), Some(1));
        assert_eq!(app.next_step(), Some(2));

        app.statuses[1] = Status::Ok;
        assert_eq!(app.running_step(), None);
        assert_eq!(app.next_step(), Some(2), "the next step is still named");
    }

    #[test]
    fn the_way_on_from_a_failure_is_a_decision_rather_than_a_dismissal() {
        let mut app = run_with(&[Status::Failed]);
        app.current = 0;
        app.failure = Some(FailureCard::new(&STEPS[0], &[]));
        app.paused = true;
        app.overlay = Some(Overlay::Failure);

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.overlay, None);
        assert!(app.paused);
        assert_eq!(app.statuses[0], Status::Failed);
        assert_eq!(app.current, 0, "and nothing advanced past it");

        assert_eq!(press(&mut app, KeyCode::Enter), Flow::Continue);
        assert_eq!(app.overlay, Some(Overlay::Failure));
    }

    #[test]
    fn stopping_at_a_failure_ends_the_session_as_a_failure() {
        let mut app = run_with(&[Status::Failed]);
        app.current = 0;
        app.failure = Some(FailureCard::new(&STEPS[0], &[]));
        app.overlay = Some(Overlay::Failure);
        assert_eq!(char_key(&mut app, 'q'), Flow::Done(Outcome::Failed));
        assert_eq!(app.statuses[0], Status::Failed);
    }

    #[test]
    fn skipping_and_ignoring_both_carry_on_but_only_one_of_them_is_a_failure() {
        for (key, expected) in [('s', Status::Skipped), ('i', Status::Ignored)] {
            let last = STEPS.len() - 1;
            let mut app = run_with(&[Status::Failed]);
            app.current = last;
            app.statuses[last] = Status::Failed;
            app.failure = Some(FailureCard::new(&STEPS[last], &[]));
            app.overlay = Some(Overlay::Failure);

            char_key(&mut app, key);
            assert_eq!(app.statuses[last], expected);
            assert_eq!(app.stage, Stage::Done);
            assert!(!app.paused);
        }
    }

    #[test]
    fn an_ignored_step_is_still_reported_as_a_failure_of_the_session() {
        let mut app = app();
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[2] = Status::Ignored;
        app.stage = Stage::Done;
        assert_eq!(app.tally().unresolved(), 1);
        assert_eq!(press(&mut app, KeyCode::Enter), Flow::Done(Outcome::Failed));
    }

    #[test]
    fn a_clean_install_finishes_with_a_success() {
        let mut app = app();
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[1] = Status::Warn;
        app.stage = Stage::Done;
        assert_eq!(app.tally().unresolved(), 0);
        assert_eq!(press(&mut app, KeyCode::Enter), Flow::Done(Outcome::Ok));
    }

    #[test]
    fn the_whole_install_walks_to_the_summary() {
        let mut app = app();
        app.begin_install();
        assert_eq!(app.stage, Stage::Done);
        assert!(
            app.statuses
                .iter()
                .all(|status| matches!(status, Status::Ok | Status::Skipped)),
            "every step either ran or was switched off: {:?}",
            app.statuses
        );
        assert_eq!(app.finished(), STEPS.len());
        assert!(app.total_elapsed() > Duration::ZERO);
    }

    #[test]
    fn retrying_from_the_summary_goes_back_to_the_run() {
        let mut app = app();
        app.begin_install();
        app.statuses[4] = Status::Ignored;
        app.stage = Stage::Done;

        char_key(&mut app, 'r');
        assert_ne!(app.statuses[4], Status::Ignored, "the step was tried again");
        assert_eq!(app.stage, Stage::Done, "and the walk carried on to the end");
    }

    #[test]
    fn retrying_when_nothing_failed_says_so() {
        let mut app = app();
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.stage = Stage::Done;
        char_key(&mut app, 'r');
        assert_eq!(app.stage, Stage::Done);
        assert!(app.notice.is_some());
    }

    #[test]
    fn logging_out_is_asked_for_before_the_session_ends() {
        let mut app = app();
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.stage = Stage::Done;

        assert_eq!(char_key(&mut app, 'o'), Flow::Continue);
        assert_eq!(
            app.confirm,
            Some(Confirm::LogOut),
            "the session is not ended on one key"
        );
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(
            app.confirm_focus, 1,
            "the highlight starts on the answer that keeps the session"
        );

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.confirm, None);
        assert_eq!(app.stage, Stage::Done);
        assert_eq!(app.handoff, None);

        char_key(&mut app, 'o');
        assert_eq!(char_key(&mut app, 'y'), Flow::Done(Outcome::Ok));
        assert_eq!(app.handoff, Some(Handoff::LogOut));
    }

    #[test]
    fn a_run_that_did_not_finish_is_not_logged_out_of() {
        let mut app = app();
        app.statuses = vec![Status::Ok; STEPS.len()];
        app.statuses[4] = Status::Failed;
        app.stage = Stage::Done;

        assert!(
            !app.can_log_out(),
            "a half-installed desktop is not a session to restart"
        );
        assert_eq!(char_key(&mut app, 'o'), Flow::Continue);
        assert_eq!(app.confirm, None);
        assert_eq!(app.handoff, None);
    }

    #[test]
    fn options_reset_one_row_or_all_of_them() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of(menu::PRESET_THEME_APPS);
        app.cursor = 0;
        assert!(
            matches!(app.selected(), Some(Entry::Preset { .. })),
            "the bulk row is the one under the cursor"
        );

        char_key(&mut app, ' ');
        let preset = app.selected().expect("a row");
        assert!(app.is_changed(preset));

        char_key(&mut app, 'r');
        let preset = app.selected().expect("a row");
        assert!(!app.is_changed(preset));

        app.answers.insert("SKIP_SYSTEM_UPDATE", "true".to_string());
        char_key(&mut app, 'R');
        assert_eq!(
            app.answers.get("SKIP_SYSTEM_UPDATE").map(String::as_str),
            Some("false"),
            "reset all put every question back"
        );
        assert!(app.notice.is_some());
    }

    #[test]
    fn a_question_is_answered_then_left_behind() {
        let mut app = app();
        app.stage = Stage::Options;
        let first = app.selected().map(Entry::id).expect("a row");

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.question, 1);
        assert_eq!(app.cursor, 0);
        assert!(app.stage == Stage::Options);
        assert_eq!(
            app.answers.get(first).map(String::as_str),
            crate::menu::baseline_of(
                menu::items_of(0)
                    .iter()
                    .find(|entry| entry.id() == first)
                    .expect("the first row"),
                &app.answers
            ),
            "walking through the questions leaves the answers alone"
        );

        for _ in 1..menu::question_count() {
            press(&mut app, KeyCode::Enter);
        }
        assert_eq!(
            app.stage,
            Stage::Options,
            "the answers stay where they were"
        );
        assert_eq!(app.overlay, Some(Overlay::Confirm));
    }

    #[test]
    fn a_change_key_changes_whatever_row_is_under_it() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        app.cursor = 0;
        let switch = app.selected().map(Entry::id).expect("a switch");

        char_key(&mut app, ' ');
        assert_eq!(
            app.answers.get(switch).map(String::as_str),
            Some("false"),
            "a switch flips"
        );
        press(&mut app, KeyCode::Right);
        assert_eq!(app.answers.get(switch).map(String::as_str), Some("true"));

        app.question = question_of("DEFAULT_SHELL");
        app.cursor = app
            .current_entries()
            .iter()
            .position(|entry| entry.id() == "DEFAULT_SHELL")
            .expect("the login shell row is in its question");
        let select = app.selected().map(Entry::id).expect("a select");
        assert_eq!(app.answers.get(select).map(String::as_str), Some("fish"));
        char_key(&mut app, ' ');
        assert_eq!(app.answers.get(select).map(String::as_str), Some("zsh"));
    }

    #[test]
    fn the_log_pane_and_the_page_keys_agree_about_how_tall_it_is() {
        let mut app = run_with(&[Status::Running]);
        for line in 0..200 {
            app.log
                .push(LogLine::parse(&format!("  [INFO]  line {line}")));
        }
        let (start, rows) = app.log_window_for(app.log_rows());
        assert_eq!(rows, app.log_rows());
        assert_eq!(start, app.log.len() - rows, "following shows the tail");

        app.log_follow = false;
        app.log_scroll = 0;
        press(&mut app, KeyCode::PageDown);
        assert_eq!(app.log_scroll, rows, "a page is the pane, not a guess");
        press(&mut app, KeyCode::End);
        assert!(app.log_follow, "end goes back to following");
    }

    #[test]
    fn n_and_p_walk_the_lines_that_went_wrong() {
        let mut app = run_with(&[Status::Running]);
        app.log = (0..200)
            .map(|line| match line {
                20 => LogLine::parse("  [WARN]  a slow mirror"),
                120 => LogLine::parse("  [ERR]   a package failed"),
                180 => LogLine::parse("  [WARN]  another slow mirror"),
                _ => LogLine::parse(&format!("  [INFO]  line {line}")),
            })
            .collect();
        app.log_follow = true;

        char_key(&mut app, 'n');
        assert!(!app.log_follow, "a jump is a reason to stop following");
        assert_eq!(app.log_problem, Some(20));
        assert_eq!(app.notice.as_deref(), Some("problem 1 of 3"));
        let (start, rows) = app.log_window_for(app.log_rows());
        assert!((start..start + rows).contains(&20), "the warning is shown");

        char_key(&mut app, 'n');
        assert_eq!(app.log_problem, Some(120));
        assert_eq!(app.notice.as_deref(), Some("problem 2 of 3"));
        char_key(&mut app, 'p');
        assert_eq!(app.log_problem, Some(20));

        char_key(&mut app, 'p');
        assert_eq!(app.log_problem, Some(180));
        assert_eq!(app.notice.as_deref(), Some("problem 3 of 3"));

        press(&mut app, KeyCode::PageUp);
        assert_eq!(app.log_problem, None);
    }

    #[test]
    fn a_log_with_nothing_wrong_in_it_says_so_rather_than_jumping() {
        let mut app = run_with(&[Status::Running]);
        app.log = vec![LogLine::parse("  [INFO]  chatter")];
        char_key(&mut app, 'n');
        assert!(app.log_problem.is_none());
        assert_eq!(app.notice.as_deref(), Some("nothing in the log went wrong"));
    }

    #[test]
    fn the_loud_filter_keeps_warnings_and_errors() {
        let mut app = run_with(&[Status::Running]);
        app.log = vec![
            LogLine::parse("  [INFO]  chatter"),
            LogLine::parse("  [WARN]  slow mirror"),
            LogLine::parse("  [ERR]   a package failed"),
        ];
        assert_eq!(app.visible_log().len(), 3);
        char_key(&mut app, 'w');
        assert_eq!(app.visible_log().len(), 2);
        assert!(app.log_loud_only);
        char_key(&mut app, 'w');
        assert_eq!(app.visible_log().len(), 3);
    }

    #[test]
    fn quitting_while_a_step_is_running_asks_first_and_then_stops_it() {
        let mut app = run_with(&[Status::Running]);
        let ctrl_c = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
        assert_eq!(app.key(ctrl_c), Flow::Continue);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Quit));
        assert_eq!(app.key(ctrl_c), Flow::Done(Outcome::Interrupted));
    }

    #[test]
    fn quitting_when_nothing_is_running_does_not_ask() {
        let mut app = run_with(&[Status::Ok]);
        let ctrl_c = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
        assert_eq!(app.key(ctrl_c), Flow::Done(Outcome::Interrupted));
    }

    #[test]
    fn the_theme_can_be_flipped_from_the_home_screen() {
        let mut app = app();
        let before = app.theme.mode;
        char_key(&mut app, 't');
        assert_ne!(app.theme.mode, before);
        assert!(app.notice.is_some());
        char_key(&mut app, 't');
        assert_eq!(app.theme.mode, before);
    }

    #[test]
    fn a_notice_lasts_until_the_next_key() {
        let mut app = app();
        char_key(&mut app, 't');
        assert!(app.notice.is_some());
        char_key(&mut app, 'j');
        assert_eq!(app.notice, None);
    }

    #[test]
    fn every_screen_offers_a_way_on() {
        let mut app = app();
        let stages = [
            Stage::Home,
            Stage::Privilege,
            Stage::Options,
            Stage::Run,
            Stage::Done,
        ];
        for stage in stages {
            app.stage = stage;
            app.overlay = None;
            assert!(!app.keys().is_empty(), "{stage:?} has no hints");
            for key in app.keys() {
                assert!(!key.keys.is_empty(), "{stage:?} hints an empty key");
                assert!(!key.what.is_empty(), "{stage:?} hints nothing");
            }
        }
        for overlay in [
            Overlay::Keys,
            Overlay::Log,
            Overlay::Failure,
            Overlay::Confirm,
        ] {
            app.overlay = Some(overlay);
            assert!(!app.keys().is_empty(), "{overlay:?} has no hints");
        }
    }

    #[test]
    fn the_keymap_overlay_closes_on_the_keys_a_user_would_try() {
        let mut app = app();
        for code in [KeyCode::Char('?'), KeyCode::Esc, KeyCode::Enter] {
            char_key(&mut app, '?');
            assert_eq!(app.overlay, Some(Overlay::Keys));
            press(&mut app, code);
            assert_eq!(app.overlay, None, "{code:?} did not close it");
        }
    }

    #[test]
    fn the_log_overlay_closes_and_pages_the_way_the_pane_does() {
        let mut app = run_with(&[Status::Running]);
        for line in 0..200 {
            app.log
                .push(LogLine::parse(&format!("  [INFO]  line {line}")));
        }
        char_key(&mut app, 'l');
        assert_eq!(app.overlay, Some(Overlay::Log));

        let rows = crate::ui::log_overlay_rows(app.area) as usize;
        assert!(rows > 3, "the overlay has room of its own");
        app.log_follow = false;
        app.log_scroll = 100;
        press(&mut app, KeyCode::PageUp);
        assert_eq!(app.log_scroll, 100 - rows, "it pages by its own height");
        press(&mut app, KeyCode::Home);
        assert_eq!(app.log_scroll, 0);

        char_key(&mut app, 'l');
        assert_eq!(app.overlay, None);
    }

    #[test]
    fn the_step_environment_carries_the_answers_and_the_bundle() {
        let app = app();
        let env = app.step_environment();
        assert!(env.iter().any(|(key, _)| *key == "BUNDLE_DIR"));
        assert!(
            env.iter()
                .any(|(key, value)| *key == "CONFIRM_ARG" && value == "--noconfirm")
        );
        assert!(env.iter().any(|(key, _)| *key == "INSTALL_FISH"));
    }

    #[test]
    fn a_scripted_answer_is_where_the_wizard_starts_rather_than_a_change() {
        let mut app = app();
        app.apply_settings(&[
            ("SYNC_LOGIN_SCREEN", "false".to_string()),
            ("DEFAULT_SHELL", "zsh".to_string()),
        ]);

        assert_eq!(
            app.answers.get("DEFAULT_SHELL").map(String::as_str),
            Some("zsh")
        );
        assert_eq!(
            app.answers.get("INSTALL_FISH").map(String::as_str),
            Some("false"),
            "a scripted shell still decides fish"
        );
        assert_eq!(
            app.changed_answers(),
            0,
            "the user has not touched anything"
        );

        assert!(
            app.step_environment()
                .iter()
                .any(|(key, value)| *key == "DEFAULT_SHELL" && value == "zsh")
        );

        app.stage = Stage::Options;
        char_key(&mut app, ' ');
        assert!(app.changed_answers() > 0);
        char_key(&mut app, 'R');
        assert_eq!(
            app.answers.get("DEFAULT_SHELL").map(String::as_str),
            Some("zsh")
        );
        assert_eq!(app.changed_answers(), 0);
    }

    #[test]
    fn a_cursor_past_the_end_of_a_question_is_pulled_back_onto_it() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of("SYNC_LOGIN_SCREEN");
        app.cursor = 99;

        press(&mut app, KeyCode::Down);
        assert!(
            app.cursor < app.current_entries().len(),
            "the cursor is on the list"
        );
        assert!(app.selected().is_some());

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Options, "onward still works");
    }

    #[test]
    fn the_last_row_of_a_question_is_the_way_on_and_the_keys_reach_it() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = 0;
        app.cursor = 0;
        assert!(!app.on_continue(), "the first row is an answer");
        let answers = app.current_entries().len();

        for _ in 0..answers {
            press(&mut app, KeyCode::Down);
        }
        assert!(app.on_continue(), "the arrows reach the way on");
        assert!(app.selected().is_none(), "and it is not an answer");
        assert_eq!(app.question, 0);

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.question, 1, "enter goes on from it");

        app.question = 0;
        app.cursor = app.current_entries().len();
        char_key(&mut app, ' ');
        assert_eq!(app.question, 1, "and so does space");
    }

    #[test]
    fn switching_a_row_off_leaves_the_cursor_on_it() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of("SYNC_LOGIN_SCREEN");
        app.cursor = 0;
        let rows = app.current_entries().len();

        char_key(&mut app, ' ');
        assert_eq!(
            app.current_entries().len(),
            rows,
            "the row stays where it can be switched back on"
        );
        assert_eq!(
            app.selected().map(Entry::id),
            Some("SYNC_LOGIN_SCREEN"),
            "the cursor is still on the row that was changed"
        );
        assert!(app.cursor < app.current_entries().len());
    }

    #[test]
    fn the_header_says_which_action_is_running_and_where() {
        let mut app = app();
        assert_eq!(app.header().left, "installer");
        app.stage = Stage::Options;
        app.action = Action::Install;
        assert_eq!(app.header().left, "install");
        assert!(app.header().right.contains("install"));
        assert!(!app.detection.distro_label().is_empty());
        assert!(
            app.header().right.contains(app.detection.distro_label()),
            "the header reports the machine that was read: {}",
            app.header().right
        );
    }
}
