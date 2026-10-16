// The app: what the wizard knows, and what a key does to it.
//
// One stage at a time with overlays on top of it, and one meaning per key: `esc` always steps
// back, `q` always leaves, `ctrl+c` always stops.

use std::io::IsTerminal;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::DefaultTerminal;
use ratatui::layout::Rect;

use crate::env::Env;
use crate::exit::Outcome;
use crate::glyphs::Glyphs;
use crate::logline::LogLine;
use crate::menu::{self, Answers, Entry};
use crate::privileges::{self, Credential, Inhibitor};
use crate::runner::Running;
use crate::signals;
use crate::steps::{self, Phase, STEPS, Status};
use crate::theme::Theme;
use crate::ui::{self, Key};

/// How many lines of the failing step's output the failure card shows.
const FAILURE_TAIL: usize = 6;

pub fn log_path() -> PathBuf {
    std::env::var_os("CAELESTIA_INSTALL_LOG")
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("caelestia-install.log"))
}

/// What the wizard is here to do. Update and Uninstall leave the TUI: their own prompts would
/// otherwise fight the TUI for the terminal.
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

    /// One plain line per action, in the voice the installer this is modeled on uses: a short
    /// factual description, no sell.
    pub fn help(self) -> &'static str {
        match self {
            Action::Install => "Installs Caelestia and the packages it needs.",
            Action::Update => "Updates an install that is already on this machine.",
            Action::Uninstall => "Removes Caelestia and restores the configs it backed up.",
        }
    }

    pub fn header(self) -> &'static str {
        match self {
            Action::Install => "install",
            Action::Update => "update",
            Action::Uninstall => "uninstall",
        }
    }

    /// Why an action is not on offer here, said in terms of the action itself. Install is always
    /// on offer - a reinstall is a thing people do - so that arm exists to keep the match total
    /// rather than to be shown.
    pub fn unavailable(self) -> &'static str {
        match self {
            Action::Update => "Caelestia is not installed, so there is nothing to update",
            Action::Uninstall => "Caelestia is not installed, so there is nothing to remove",
            Action::Install => "Caelestia is installed, so there is nothing to install",
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

/// Where the wizard has got to, in the order it works through. Overlays are not stages: closing
/// one returns to the stage it was opened over.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Stage {
    Home,
    Detect,
    Options,
    Review,
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

/// What the confirm overlay is asking about.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Confirm {
    Handoff(Action),
    Install,
    Quit,
}

/// How the wizard will become root: its own helper can ask, or the user can authorize elsewhere.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum AuthMethod {
    /// Ask for the password here and pass it to sudo.
    Password,
    /// Let the user run `sudo -v` in their own terminal.
    External,
}

impl AuthMethod {
    pub fn title(self) -> &'static str {
        match self {
            AuthMethod::Password => "Type your password here",
            AuthMethod::External => "Authorize in another terminal",
        }
    }

    pub fn help(self) -> Option<&'static str> {
        match self {
            AuthMethod::Password => None,
            AuthMethod::External => {
                Some("For when it cannot ask: run `sudo -v` in your own terminal, then continue.")
            }
        }
    }
}

/// The two actions that hand the terminal back to another program.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Handoff {
    Update,
    Uninstall,
}

/// What the TUI leaves behind: an exit code, and work for the caller once the terminal is back.
pub struct Session {
    pub outcome: Outcome,
    pub handoff: Option<Handoff>,
}

/// What the installer found, read before anything is decided and again at the point of no return:
/// a machine that changed while the wizard was open must not be overwritten on an old answer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Detection {
    /// The family, kept as the enum it is: a precondition is decided by asking what the machine
    /// is, not by comparing a label written for a human to a string.
    pub distro: crate::distro::Distro,
    pub kind: crate::install_kind::Kind,
    /// Caelestia's shell configuration is already where this install kind keeps it.
    pub installed: bool,
    /// The package manager this distribution installs with, if there is one.
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

    /// What to call the distribution and the layout on screen.
    pub fn distro_label(&self) -> &'static str {
        self.distro.label()
    }

    pub fn kind_label(&self) -> &'static str {
        self.kind.label()
    }

    /// The things that will stop an install, as opposed to the things that are merely true.
    /// Each one is the condition its own sentence describes, so a blocker never fires on a
    /// machine where what it says is missing is not needed - and a distribution that is unknown
    /// is said once, rather than also blaming the package manager it was never going to find.
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

/// What went wrong, what can be done about it, and what each answer costs.
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
            help: "run this step again from the start",
        },
        Choice {
            key: 's',
            label: "Skip",
            help: "mark it SKIPPED and carry on",
        },
        Choice {
            key: 'i',
            label: "Ignore",
            help: "mark it IGNORED, carry on, and report the install as failed",
        },
        Choice {
            key: 'q',
            label: "Stop",
            help: "end the install here",
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

    /// The command that reproduces the step outside the TUI, so a failure can be worked on
    /// somewhere there is room to read it.
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
    /// Which of the themeable apps are on this machine. Read once, and the reason a question can
    /// ask about the apps somebody has instead of listing the ones they might install.
    pub apps: crate::apps::Apps,
    /// Read from the machine when the wizard starts and re-read at the confirmation. What the
    /// machine is, and whether Caelestia is already on it, are asked of this rather than kept in
    /// fields of their own: two records of one fact are two records that can disagree.
    pub detection: Detection,
    /// Set when the user has been shown that Caelestia is already installed and chose to carry
    /// on anyway. Without it, the confirmation refuses to overwrite something nobody mentioned.
    pub reinstall_acknowledged: bool,
    /// Whether Caelestia was already there when the wizard started, which is what tells "you
    /// were told and said yes" apart from "this appeared while you were deciding".
    pub installed_when_started: bool,
    pub stage: Stage,
    pub overlay: Option<Overlay>,
    pub confirm: Option<Confirm>,
    pub action: Action,
    pub home: usize,
    pub answers: Answers,
    /// The answers the wizard was seeded with on this machine: what "changed" is measured against
    /// and what "reset" goes back to. A machine that already has the apps starts with them on, so
    /// the table's defaults alone would report a change nobody made.
    baseline: Answers,
    /// Which question the wizard is asking: one screen per question, in order.
    pub question: usize,
    pub cursor: usize,
    /// Which privilege route the user picked, once they have picked one.
    pub auth: Option<AuthMethod>,
    pub password: String,
    /// A password that is with sudo. The answer arrives on a later tick, so the frame can show
    /// that something is happening while PAM takes its time over it.
    pub(crate) checking: Option<std::sync::mpsc::Receiver<bool>>,
    /// Walk the state machine without running any step: what the tests use to see a whole install
    /// through. Nothing on the command line sets it, and it is false everywhere else.
    pub pretend: bool,
    pub attempts: usize,
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
    pub review_scroll: usize,
    pub area: Rect,
    pub spinner: usize,
    durations: Vec<Option<Duration>>,
    running_since: Option<Instant>,
    leaving: Option<Outcome>,
    handoff: Option<Handoff>,
    credential: Option<Credential>,
    inhibitor: Option<Inhibitor>,
    running: Option<Running>,
}

impl App {
    pub fn new(bundle: PathBuf, log_path: PathBuf, env: Env) -> Self {
        let mut answers = Answers::new();
        menu::seed_answers(&menu::QUESTIONS, &mut answers);
        // Only the apps this machine has are offered, and the ones it has start on: the answer to
        // "theme this app you have" is the app, not a prompt. An app that is not here answers no,
        // so a row nobody ever saw can never be the reason a step runs.
        let apps = crate::apps::Apps::here();
        for (id, answer) in apps.answers() {
            answers.insert(id, answer.to_string());
        }
        // What this machine started at, which is what "changed" and "reset" are measured against:
        // the apps it already has are on from the first screen, so nothing reads as switched on
        // before the user has touched anything.
        let baseline = answers.clone();
        Self {
            bundle,
            log_path,
            theme: Theme::resolve(&env),
            glyphs: Glyphs::resolve(&env),
            apps,
            env,
            // Read once, here, and again when it matters. The header is drawn thirty times a
            // second, and detection reads the filesystem and the PATH.
            detection: Detection::read(),
            reinstall_acknowledged: false,
            installed_when_started: crate::install_kind::shell_config().exists(),
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
            review_scroll: 0,
            area: Rect::new(0, 0, 0, 0),
            spinner: 0,
            durations: vec![None; STEPS.len()],
            running_since: None,
            leaving: None,
            handoff: None,
            credential: None,
            inhibitor: None,
            running: None,
        }
    }

    /// Point the wizard at a machine with a known set of apps, and take the answers it would have
    /// started with there. Which apps a machine has is read from the machine, so this is the only
    /// way to say what the app rows are about.
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

    /// The answers a script gave rather than the wizard asking. They are where the wizard starts,
    /// so they are the baseline as well: a script that switched something on is not a change the
    /// user made, and resetting goes back to what the script asked for.
    pub fn apply_settings(&mut self, settings: &[(&'static str, String)]) {
        menu::apply_set(settings, &mut self.answers);
        self.baseline = self.answers.clone();
    }

    // What the view asks -------------------------------------------------------------

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
            // Progress, where there is progress to report. The review screen used to show the
            // same counter as the run screen and always read "step 0 of 17", which is a
            // progress bar for something that has not started; its summary already says how
            // many steps will run.
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

    pub fn step_elapsed(&self, index: usize) -> Option<Duration> {
        if self.statuses[index] == Status::Running {
            return self.running_since.map(|since| since.elapsed());
        }
        self.durations[index]
    }

    pub fn phase_elapsed(&self, phase: Phase) -> Duration {
        STEPS
            .iter()
            .enumerate()
            .filter(|(_, step)| step.phase == phase)
            .filter_map(|(index, _)| self.step_elapsed(index))
            .sum()
    }

    pub fn total_elapsed(&self) -> Duration {
        self.durations.iter().flatten().sum::<Duration>()
            + self
                .running_since
                .map(|since| since.elapsed())
                .unwrap_or_default()
    }

    pub fn phase_status(&self, phase: Phase) -> Status {
        let statuses: Vec<Status> = STEPS
            .iter()
            .enumerate()
            .filter(|(_, step)| step.phase == phase)
            .map(|(index, _)| self.statuses[index])
            .collect();
        statuses
            .iter()
            .copied()
            .max_by_key(|status| rank(*status))
            .unwrap_or(Status::Pending)
    }

    /// How far through its phase a phase is, and how many steps it has. A step being worked on
    /// counts as reached, so the line reads as a position rather than a score.
    pub fn phase_progress(&self, phase: Phase) -> (usize, usize) {
        let steps: Vec<usize> = STEPS
            .iter()
            .enumerate()
            .filter(|(_, step)| step.phase == phase)
            .map(|(index, _)| index)
            .collect();
        let reached = steps
            .iter()
            .filter(|index| self.statuses[**index] != Status::Pending)
            .count();
        (reached, steps.len())
    }

    /// The step being worked on, as an index into the table.
    pub fn running_step(&self) -> Option<usize> {
        self.statuses
            .iter()
            .position(|status| *status == Status::Running)
    }

    pub fn tally(&self) -> Tally {
        let count = |status: Status| self.statuses.iter().filter(|each| **each == status).count();
        Tally {
            ok: count(Status::Ok),
            warn: count(Status::Warn),
            failed: count(Status::Failed),
            ignored: count(Status::Ignored),
            skipped: count(Status::Skipped),
            total: STEPS.len(),
        }
    }

    /// The rows of the question on screen, with the ones that are not worth showing left out: an
    /// app this machine does not have has nothing here to theme. This is the list the cursor
    /// indexes, so what is drawn and what a key moves over cannot disagree.
    pub fn current_entries(&self) -> Vec<&'static Entry> {
        menu::items_of(self.question)
            .iter()
            .filter(|entry| menu::shows(entry, &self.answers, &self.apps))
            .collect()
    }

    pub fn selected(&self) -> Option<&'static Entry> {
        self.current_entries().into_iter().nth(self.cursor)
    }

    /// Whether a row's answer differs from the one this machine started at.
    pub fn is_changed(&self, entry: &Entry) -> bool {
        menu::is_changed(entry, &self.apps, &self.answers, &self.baseline)
    }

    /// Whether a bulk row's apps are all on.
    pub fn preset_on(&self, entry: &Entry) -> bool {
        menu::preset_on(entry, &self.apps, &self.answers)
    }

    pub fn action_enabled(&self, action: Action) -> bool {
        match action {
            // Both of these work on an install that is already here. Offering one on a machine
            // with nothing on it offers work that cannot be done.
            Action::Install => true,
            Action::Update | Action::Uninstall => self.installed(),
        }
    }

    /// Whether this machine already has Caelestia on it: what the wizard reads, not what it
    /// remembers. One answer, so the screens, the action list and the confirmation cannot
    /// disagree about it.
    pub fn installed(&self) -> bool {
        self.detection.installed
    }

    /// Whether this machine already has Caelestia on it, read now rather than remembered. A
    /// pretend run reads nothing: it has no machine to read, and the tests set the detection
    /// they want to reason about.
    pub fn refresh_detection(&mut self) {
        if self.pretend {
            return;
        }
        self.detection = Detection::read();
        // A new reading is a new answer to whatever the last one was asked about, so a sentence
        // written about the old one is no longer true of the machine.
        self.problem = None;
    }

    /// The questions whose answers differ from a fresh install: what "changed" is counted over.
    /// A bulk row is a view of the switches it stands for and holds no answer, so counting it
    /// would report seven changes for one decision.
    pub fn question_changed(&self, question: usize) -> bool {
        menu::items_of(question)
            .iter()
            .any(|entry| menu::holds_an_answer(entry) && self.is_changed(entry))
    }

    /// How many answers differ from what this machine started at, across every question. A bulk
    /// row is a view of the switches it stands for and holds no answer, so counting it would
    /// report seven changes for one decision.
    pub fn changed_answers(&self) -> usize {
        menu::every_entry()
            .into_iter()
            .filter(|entry| menu::holds_an_answer(entry) && self.is_changed(entry))
            .count()
    }

    /// The lines the log pane shows, in order: everything, or only what went wrong.
    pub fn visible_log(&self) -> Vec<&LogLine> {
        self.log
            .iter()
            .filter(|line| !self.log_loud_only || line.is_loud())
            .collect()
    }

    pub fn log_rows(&self) -> usize {
        ui::log_rows(self.run_layout().log).max(1) as usize
    }

    pub fn run_layout(&self) -> ui::RunLayout {
        let body = ui::body(self.area);
        ui::run_layout(body, crate::screens::checklist_rows(self))
    }

    /// Where the log pane starts, sized for a pane: the run screen passes the pane it drew, and
    /// the full-screen log passes its own. One function, so the two cannot disagree.
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

    pub fn review_rows(&self) -> usize {
        let (_, list) = ui::review_layout(ui::body(self.area));
        list.height.max(1) as usize
    }

    /// How far the review list can be scrolled before it is showing its last page.
    pub fn review_limit(&self) -> usize {
        crate::screens::review_total(self).saturating_sub(self.review_rows())
    }

    // The loop ----------------------------------------------------------------------

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

    /// The signal handler's escape hatch, and `ctrl+c`: stop whatever is running, then leave.
    fn interrupt(&mut self) -> Flow {
        if self.overlay == Some(Overlay::Confirm) {
            return self.stop_and_leave();
        }
        if self.busy() {
            self.confirm = Some(Confirm::Quit);
            self.overlay = Some(Overlay::Confirm);
            return Flow::Continue;
        }
        Flow::Done(Outcome::Interrupted)
    }

    /// Whether a step is in flight, which is the only thing that makes quitting worth asking
    /// about.
    fn busy(&self) -> bool {
        self.running.is_some() || self.running_step().is_some()
    }

    fn stop_and_leave(&mut self) -> Flow {
        self.stop_running();
        Flow::Done(Outcome::Interrupted)
    }

    /// A step that is stopped is a step that is stopped: leaving the child behind would let a
    /// package manager carry on writing while the user believes they canceled.
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
        // A notice is the answer to the key before this one, so any key clears it.
        self.notice = None;

        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return self.interrupt();
        }
        if let Some(overlay) = self.overlay {
            return self.overlay_key(overlay, key);
        }
        // The keymap offers `t` everywhere, so it works everywhere. Not on the password
        // screen, where a letter is a letter.
        if key.code == KeyCode::Char('t') && self.stage != Stage::Privilege {
            self.theme.cycle();
            self.notice = Some(format!("{} theme", self.theme.mode.name()));
            return Flow::Continue;
        }
        match self.stage {
            Stage::Home => self.home_key(key),
            Stage::Detect => self.detect_key(key),
            Stage::Options => self.options_key(key),
            Stage::Review => self.review_key(key),
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
            Some(Overlay::Log) => vec![
                ui::key(glyphs.up_down(), "scroll"),
                ui::key("w", "loud only"),
                ui::key("f", "follow"),
                ui::key(glyphs.escape(), "close"),
            ],
            Some(Overlay::Failure) => vec![
                ui::key("r", "retry"),
                ui::key("s", "skip"),
                ui::key("i", "ignore"),
                ui::key("q", "stop"),
                ui::key(glyphs.escape(), "decide later"),
            ],
            Some(Overlay::Confirm) => vec![ui::key("y", "yes"), ui::key("n", "no")],
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
                Stage::Auth if self.auth == Some(AuthMethod::External) => vec![
                    ui::key(glyphs.enter(), "I have done it"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Auth => vec![
                    ui::key(glyphs.up_down(), "move"),
                    ui::key(glyphs.enter(), "choose"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Privilege if self.checking.is_some() => Vec::new(),
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
                    ui::key(glyphs.enter(), "next"),
                    ui::key(glyphs.up_down(), "move"),
                    ui::key(glyphs.left_right(), "change"),
                    ui::key(glyphs.escape(), "back"),
                    // The resets come last because they are what a narrow footer can afford to
                    // lose: the way on and the way back belong ahead of them.
                    ui::key("r", "reset"),
                    ui::key("R", "reset all"),
                ],
                Stage::Review => vec![
                    ui::key(glyphs.up_down(), "scroll"),
                    ui::key(glyphs.enter(), "install"),
                    ui::key(glyphs.escape(), "back"),
                ],
                Stage::Run if self.paused => vec![
                    ui::key(glyphs.enter(), "the failure"),
                    ui::key("l", "log"),
                    ui::key("q", "quit"),
                ],
                Stage::Run => vec![
                    ui::key(glyphs.up_down(), "scroll"),
                    ui::key("f", "follow"),
                    ui::key("w", "loud only"),
                    ui::key("l", "log"),
                    ui::key("q", "quit"),
                ],
                Stage::Done => vec![
                    ui::key("r", "retry failed"),
                    ui::key("l", "log"),
                    ui::key(glyphs.enter(), "finish"),
                    ui::key("q", "quit"),
                ],
            },
        }
    }

    // Home --------------------------------------------------------------------------

    fn home_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.home = if self.home == 0 {
                    Action::ALL.len() - 1
                } else {
                    self.home - 1
                };
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.home = (self.home + 1) % Action::ALL.len();
            }
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Enter | KeyCode::Char(' ') => return self.choose_action(),
            KeyCode::Esc | KeyCode::Char('q') => return Flow::Done(Outcome::Canceled),
            _ => {}
        }
        Flow::Continue
    }

    fn choose_action(&mut self) -> Flow {
        let action = Action::ALL[self.home];
        if !self.action_enabled(action) {
            self.notice = Some(Action::unavailable(action).to_string());
            return Flow::Continue;
        }
        self.action = action;
        match action {
            // What is on the machine comes before what to do with it: the answer decides
            // whether this is an install at all.
            Action::Install => {
                self.show_detection();
                self.stage = Stage::Detect;
            }
            Action::Update | Action::Uninstall => {
                self.confirm = Some(Confirm::Handoff(action));
                self.overlay = Some(Overlay::Confirm);
            }
        }
        Flow::Continue
    }

    /// Read the machine again and forget the acknowledgment that went with the old reading: a
    /// warning about an install that has since been removed must not keep saying so, and one
    /// that has since appeared must stop being silent.
    fn show_detection(&mut self) {
        self.refresh_detection();
        self.reinstall_acknowledged = false;
    }

    // This machine -------------------------------------------------------------------

    fn detect_key(&mut self, key: KeyEvent) -> Flow {
        match key.code {
            KeyCode::Enter | KeyCode::Char(' ') => {
                // A machine the installer cannot install on is said so here rather than after
                // five screens of questions: the answer is not going to change by asking more.
                // The reason is already on screen above, so the answer to the key is the fact
                // that nothing moved.
                if !self.detection.blockers().is_empty() {
                    self.problem = Some(
                        "The installer cannot go on until the above is sorted out.".to_string(),
                    );
                    return Flow::Continue;
                }
                if self.installed() {
                    // Carrying on here is the deliberate act: it is the only place the user is
                    // told that this overwrites what is already there.
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
                self.confirm = Some(Confirm::Handoff(Action::Update));
                self.overlay = Some(Overlay::Confirm);
            }
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Esc => {
                // The screen's own message goes with the screen.
                self.problem = None;
                self.stage = Stage::Home;
            }
            _ => {}
        }
        Flow::Continue
    }

    // Privilege ---------------------------------------------------------------------

    fn privilege_key(&mut self, key: KeyEvent) -> Flow {
        // The password is with sudo, and no key pressed now can change what comes back: it
        // would only queue up a second attempt behind the first.
        if self.checking.is_some() {
            return Flow::Continue;
        }
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
                self.password.clear();
                self.problem = None;
                self.attempts = 0;
                self.auth = None;
                self.stage = Stage::Auth;
                Flow::Continue
            }
            // A chord is not a character of a password. A terminal that sends one for enter,
            // or any other combination, must not leave a stray letter in the field.
            KeyCode::Char(character) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                if !character.is_control() {
                    self.password.push(character);
                }
                Flow::Continue
            }
            _ => Flow::Continue,
        }
    }

    /// Hands the password to sudo on a thread of its own. PAM can take seconds to answer, and a
    /// frame that freezes for that long reads as a hang - which is what made people type their
    /// password again while the first attempt was still in flight.
    fn start_check(&mut self) {
        if self.checking.is_some() {
            return;
        }
        if self.password.is_empty() {
            self.problem = Some("Type the password first.".to_string());
            return;
        }
        // A correct password clears the system's tally, so an attempt is always worth letting
        // through while there is one to make; only a wrong one can lock the account, and a
        // locked account cannot take the right password either. Nothing asks the system in a
        // pretend run, where there is no system to ask.
        if !self.pretend && privileges::locked_out() {
            self.problem = Some("Locked out for a few minutes after too many tries.".to_string());
            return;
        }
        let (sender, receiver) = std::sync::mpsc::channel();
        if self.pretend {
            // Nothing here should call sudo: answer the way one that accepted would have.
            let _ = sender.send(true);
        } else {
            let secret = self.password.clone();
            thread::spawn(move || {
                let _ = sender.send(privileges::accepts(&secret));
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
                self.attempts += 1;
                self.problem = Some(if !self.pretend && privileges::on_the_last_entry() {
                    // The system counts refusals, and once it has counted enough it stops
                    // accepting the right password for a while. Warn before that happens
                    // rather than after it.
                    "Not accepted. A wrong entry now locks the account.".to_string()
                } else {
                    "That password was not accepted.".to_string()
                });
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => {}
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                self.checking = None;
                self.problem = Some("The password could not be checked.".to_string());
            }
        }
    }

    /// The password sudo accepted: publish it for the steps to escalate with.
    fn accept_password(&mut self) {
        if !self.pretend {
            let exe =
                std::env::current_exe().unwrap_or_else(|_| PathBuf::from("caelestia-install"));
            match Credential::install(&self.password, &exe) {
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

    // Privileges --------------------------------------------------------------------

    /// The route to root, offered only where there is a route to choose. A machine that is
    /// already authorized has nothing to ask about, so it is not asked.
    fn need_auth(&mut self) {
        if !needs_password() {
            self.begin_install();
            return;
        }
        self.auth = None;
        self.problem = None;
        self.cursor = 0;
        // A gate entered again is asked again from a clean slate: a count left over from the
        // last visit would report refusals this visit never made.
        self.attempts = 0;
        self.stage = Stage::Auth;
    }

    /// The routes that would actually work here, in the order they are offered.
    pub fn auth_methods(&self) -> Vec<AuthMethod> {
        vec![AuthMethod::Password, AuthMethod::External]
    }

    fn auth_key(&mut self, key: KeyEvent) -> Flow {
        // Waiting on the user's own terminal: nothing to navigate, only to carry on from.
        if self.auth == Some(AuthMethod::External) {
            match key.code {
                KeyCode::Enter | KeyCode::Char(' ') => {
                    if privileges::sudo_cached() {
                        self.begin_install();
                    } else {
                        self.problem =
                            Some("sudo is still not authorized. Run `sudo -v` first.".to_string());
                    }
                }
                KeyCode::Esc => {
                    self.auth = None;
                    self.problem = None;
                }
                _ => {}
            }
            return Flow::Continue;
        }

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
                match method {
                    AuthMethod::Password => self.stage = Stage::Privilege,
                    AuthMethod::External => {}
                }
            }
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Esc => self.stage = Stage::Review,
            _ => {}
        }
        Flow::Continue
    }

    // Options -----------------------------------------------------------------------

    fn options_key(&mut self, key: KeyEvent) -> Flow {
        let entries = self.current_entries();
        let rows = entries.len();
        // Rows come and go with the answers — a login screen style goes when the login screen is
        // left alone — so the cursor is pulled back onto the list before it is moved, and entering
        // and leaving keep working on a question whose rows have all gone.
        self.cursor = self.cursor.min(rows.saturating_sub(1));
        match key.code {
            KeyCode::Up | KeyCode::Char('k') if rows > 0 => {
                self.cursor = if self.cursor == 0 {
                    rows - 1
                } else {
                    self.cursor - 1
                };
            }
            KeyCode::Down | KeyCode::Char('j') if rows > 0 => {
                self.cursor = (self.cursor + 1) % rows;
            }
            KeyCode::Char('r') => self.reset_highlighted(),
            KeyCode::Char('R') => self.reset_all(),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            // Changing a value is its own gesture, so enter is free to mean "onward" and never
            // does two things depending on which row is under the cursor.
            KeyCode::Char(' ') | KeyCode::Right | KeyCode::Char('l') => {
                if let Some(entry) = self.selected() {
                    menu::change(entry, &self.apps, &mut self.answers);
                }
            }
            KeyCode::Left | KeyCode::Char('h') => {
                if let Some(entry) = self.selected() {
                    menu::change(entry, &self.apps, &mut self.answers);
                }
            }
            KeyCode::Enter => self.next_question(),
            KeyCode::Esc => self.previous_question(),
            _ => {}
        }
        Flow::Continue
    }

    /// Onward: the next question, or the review once there is nothing left to ask.
    pub fn next_question(&mut self) {
        if self.question + 1 < menu::question_count() {
            self.question += 1;
            self.cursor = 0;
        } else {
            self.stage = Stage::Review;
            self.review_scroll = 0;
        }
    }

    /// Back one question, and off the start of the wizard it is the detection screen: there is
    /// no way to walk past the point where the machine was read.
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
        if menu::reset(entry, &self.apps, &mut self.answers, &self.baseline) {
            self.notice = Some(format!("{} reset", entry.title()));
        }
    }

    /// Every row back to what this machine started at, apps and all.
    fn reset_all(&mut self) {
        self.answers = self.baseline.clone();
        self.notice = Some("every option is back at its default".to_string());
    }

    // Review ------------------------------------------------------------------------

    fn review_key(&mut self, key: KeyEvent) -> Flow {
        let rows = self.review_rows();
        let limit = self.review_limit();
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.review_scroll = self.review_scroll.saturating_sub(1);
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.review_scroll = (self.review_scroll + 1).min(limit);
            }
            KeyCode::PageUp => self.review_scroll = self.review_scroll.saturating_sub(rows),
            KeyCode::PageDown => {
                self.review_scroll = (self.review_scroll + rows).min(limit);
            }
            KeyCode::Home | KeyCode::Char('g') => self.review_scroll = 0,
            KeyCode::End | KeyCode::Char('G') => self.review_scroll = limit,
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            // Nothing is deployed on the strength of the key that walked into the screen: the
            // confirmation is its own deliberate step, separate from editing the answers.
            KeyCode::Enter | KeyCode::Char(' ') => {
                self.confirm = Some(Confirm::Install);
                self.overlay = Some(Overlay::Confirm);
            }
            KeyCode::Esc => {
                self.question = menu::question_count().saturating_sub(1);
                self.cursor = 0;
                self.stage = Stage::Options;
            }
            _ => {}
        }
        Flow::Continue
    }

    // Run ---------------------------------------------------------------------------

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
            }
            KeyCode::End => self.log_follow = true,
            KeyCode::Char('f') => {
                self.log_follow = !self.log_follow;
                self.notice = Some(if self.log_follow {
                    "following the log".to_string()
                } else {
                    "log paused".to_string()
                });
            }
            KeyCode::Char('w') => self.toggle_loud_only(),
            KeyCode::Char('l') => self.overlay = Some(Overlay::Log),
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Char('q') => {
                self.confirm = Some(Confirm::Quit);
                self.overlay = Some(Overlay::Confirm);
            }
            _ => {}
        }
        Flow::Continue
    }

    fn scroll_log(&mut self, step: isize, rows: usize) {
        self.log_follow = false;
        let furthest = self.visible_log().len().saturating_sub(rows) as isize;
        self.log_scroll = (self.log_scroll as isize + step).clamp(0, furthest) as usize;
    }

    fn toggle_loud_only(&mut self) {
        self.log_loud_only = !self.log_loud_only;
        self.log_scroll = 0;
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
            KeyCode::Char('?') => self.overlay = Some(Overlay::Keys),
            KeyCode::Enter | KeyCode::Char(' ') | KeyCode::Esc | KeyCode::Char('q') => {
                return self.finish();
            }
            _ => {}
        }
        Flow::Continue
    }

    /// The exit code has to agree with the screen: a session with a step that failed, or that the
    /// user chose to move past, is not a success.
    pub fn finish(&mut self) -> Flow {
        if self.tally().unresolved() > 0 {
            Flow::Done(Outcome::Failed)
        } else {
            Flow::Done(Outcome::Ok)
        }
    }

    // Overlays ----------------------------------------------------------------------

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
            }
            KeyCode::End | KeyCode::Char('G') => self.log_follow = true,
            KeyCode::Char('f') => self.log_follow = !self.log_follow,
            KeyCode::Char('w') => self.toggle_loud_only(),
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
            // Closing without deciding leaves the failure where it is and the run paused: a key
            // that means "back" everywhere else must not quietly accept a failure here.
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
        let confirmed = match key.code {
            KeyCode::Char('y') | KeyCode::Char('Y') | KeyCode::Enter => true,
            KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => false,
            _ => return Flow::Continue,
        };
        let Some(confirm) = self.confirm.take() else {
            self.overlay = None;
            return Flow::Continue;
        };
        self.overlay = None;
        if !confirmed {
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
        }
    }

    /// The point of no return. The machine is read one last time here, because every question
    /// about whether it is safe to install was answered minutes ago and the answer to "is
    /// Caelestia already here" is the one nobody should be surprised by.
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

    // The install itself ------------------------------------------------------------

    pub fn begin_install(&mut self) {
        // Keeping the session awake belongs to the install, not to one of the routes into it:
        // a machine that needed no password, or one authorized in another terminal, must be
        // held awake just the same.
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
        self.failure = None;
        self.paused = false;
        self.start_next();
    }

    /// Try the failed steps again, without redoing what worked.
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
                self.log.push(LogLine::parse(&format!(
                    "  [SKIP]  {} is switched off in the options",
                    STEPS[index].name
                )));
                self.current += 1;
                continue;
            }
            if self.pretend {
                self.statuses[index] = Status::Ok;
                self.durations[index] = Some(Duration::from_secs(2));
                self.log.push(LogLine::parse(&format!(
                    "  [OK]    {} finished",
                    STEPS[index].name
                )));
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
                    self.log
                        .push(LogLine::parse(&format!("  [ERR]   {problem}")));
                    self.failure = Some(FailureCard::new(step, &self.log));
                    self.paused = true;
                    return;
                }
            }
        }
        self.stage = Stage::Done;
        self.credential = None;
        self.inhibitor = None;
    }

    pub fn step_environment(&self) -> Vec<(&'static str, String)> {
        let mut env: Vec<(&'static str, String)> = self
            .answers
            .iter()
            .map(|(key, value)| (*key, value.clone()))
            .collect();
        env.push(("CONFIRM_ARG", "--noconfirm".to_string()));
        env.push(("BUNDLE_DIR", self.bundle.display().to_string()));
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
                self.durations[self.current] =
                    self.running_since.take().map(|since| since.elapsed());
                self.log
                    .push(LogLine::parse(&format!("  [ERR]   {problem}")));
                self.failure = Some(FailureCard::new(&STEPS[self.current], &self.log));
                self.paused = true;
            }
        }
    }
}

/// Counted once, so the screen and the exit code cannot disagree.
pub struct Tally {
    pub ok: usize,
    pub warn: usize,
    pub failed: usize,
    pub ignored: usize,
    pub skipped: usize,
    pub total: usize,
}

impl Tally {
    /// Steps that did not do what they were asked to do.
    pub fn unresolved(&self) -> usize {
        self.failed + self.ignored
    }

    pub fn ran(&self) -> usize {
        self.ok + self.warn
    }
}

/// What a set of statuses amounts to, loudest first.
fn rank(status: Status) -> u8 {
    match status {
        Status::Failed => 6,
        Status::Ignored => 5,
        Status::Warn => 4,
        Status::Ok => 3,
        Status::Running => 2,
        Status::Skipped => 1,
        Status::Pending => 0,
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
    let mut terminal = match ratatui::try_init() {
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
    ratatui::try_restore().ok();
    app.session(outcome)
}

fn event_loop(terminal: &mut DefaultTerminal, app: &mut App) -> Outcome {
    loop {
        if let Some(outcome) = app.leaving() {
            return outcome;
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
        // Which apps a machine has is read from the machine, so the host's own apps would leak
        // into every assertion. A known set: all of them, so the app rows are on screen.
        .with_apps(crate::apps::Apps::all());
        // The screens and the page keys agree on a size; the tests have to give them one.
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

    /// Which question a row lives in, by the row's id.
    fn question_of(id: &str) -> usize {
        (0..menu::question_count())
            .find(|index| menu::items_of(*index).iter().any(|entry| entry.id() == id))
            .unwrap_or_else(|| panic!("{id} is not in a question"))
    }

    /// A machine the installer can install on, so a test about the flow is not also a test
    /// about what happens to be installed on the machine running it.
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

    /// Everything the run screen shows, as a state without any of the work.
    fn run_with(statuses: &[Status]) -> App {
        let mut app = app();
        app.stage = Stage::Run;
        for (index, status) in statuses.iter().enumerate() {
            app.statuses[index] = *status;
        }
        app
    }

    #[test]
    fn home_offers_the_three_actions_the_installer_fronts() {
        let mut app = app();
        assert_eq!(app.stage, Stage::Home);
        let mut seen = Vec::new();
        for _ in 0..Action::ALL.len() {
            seen.push(Action::ALL[app.home]);
            press(&mut app, KeyCode::Down);
        }
        assert_eq!(
            seen,
            vec![Action::Install, Action::Update, Action::Uninstall]
        );
        assert_eq!(Action::ALL[app.home], Action::Install, "and it wraps");
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
        // Answering five screens of questions and then being refused is worse than being told
        // at the first screen why it will not work.
        let mut app = app();
        app.detection = Detection {
            package_manager: None,
            ..installable()
        };
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Detect);

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Detect, "it stays where the reason is");
        assert!(
            app.problem
                .as_deref()
                .unwrap_or_default()
                .contains("cannot go on"),
            "the answer to the key, in words the blocker above does not already use: {:?}",
            app.problem
        );

        // And the way out is still a way out.
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

        // One decision, six answers: the bulk row is a view of them and holds none of its own.
        char_key(&mut app, ' ');
        assert_eq!(
            app.changed_answers(),
            6,
            "six apps, not seven options: the row is not an answer"
        );

        // And undoing it leaves nothing changed.
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
        assert!(
            app.notice
                .as_deref()
                .unwrap_or_default()
                .contains("nothing to update"),
            "{:?}",
            app.notice
        );

        // With an install on the machine it is offered, and it confirms before handing over.
        app.detection.installed = true;
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Handoff(Action::Update)));
    }

    #[test]
    fn the_theme_key_works_on_every_screen_but_the_password_one() {
        // The keymap offers it everywhere, so it does what it says everywhere.
        for stage in [
            Stage::Home,
            Stage::Detect,
            Stage::Options,
            Stage::Review,
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

        // Except where a letter is a letter.
        let mut app = app();
        app.stage = Stage::Privilege;
        let before = app.theme.mode;
        char_key(&mut app, 't');
        assert_eq!(app.theme.mode, before, "a password may contain a t");
        assert_eq!(app.password, "t", "and it is typed, not swallowed");
    }

    #[test]
    fn the_options_footer_keeps_the_way_on_and_loses_the_resets_first() {
        // The footer drops whole groups from its end, so its order is the priority: a narrow
        // terminal must still show how to move on and how to get back.
        let mut app = app();
        app.stage = Stage::Options;
        let footer: Vec<&str> = app.keys().iter().map(|key| key.what).collect();
        let at = |needle: &str| {
            footer
                .iter()
                .position(|what| *what == needle)
                .unwrap_or_else(|| panic!("{needle} is missing from {footer:?}"))
        };
        assert!(at("next") < at("reset"), "{footer:?}");
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

        // Carrying on from that screen is the acknowledgment: it is the only place the user is
        // told, so it is the only place that may grant it.
        press(&mut app, KeyCode::Enter);
        assert!(app.reinstall_acknowledged);
        assert_eq!(app.stage, Stage::Options);

        // And the confirmation now lets it through rather than stopping it again.
        app.stage = Stage::Review;
        press(&mut app, KeyCode::Enter);
        char_key(&mut app, 'y');
        assert_ne!(app.stage, Stage::Detect);
    }

    #[test]
    fn an_install_that_appeared_while_the_wizard_was_open_stops_at_the_confirmation() {
        // The answers about this machine were taken minutes ago. The one that decides whether
        // this overwrites something is worth asking again at the point it matters.
        let mut app = app();
        app.detection = installable();
        app.installed_when_started = false;
        app.stage = Stage::Review;
        press(&mut app, KeyCode::Enter);

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
        app.stage = Stage::Review;
        press(&mut app, KeyCode::Enter);
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

        // git is a source install's precondition and nobody else's: a packaged install that
        // never touches a checkout must not be stopped for want of it.
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
        app.stage = Stage::Review;

        // Enter asks before it acts: nothing starts on the key that arrived at the screen.
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.overlay, Some(Overlay::Confirm));
        assert_eq!(app.confirm, Some(Confirm::Install));
        assert_eq!(app.stage, Stage::Review, "and nothing has started yet");

        char_key(&mut app, 'y');
        // A test process is not root and has no cached sudo, so there is a route to choose. The
        // wizard offers the choice rather than assuming the password.
        assert_eq!(app.stage, Stage::Auth);
        assert_eq!(app.auth, None, "no route is taken until one is picked");
        assert!(app.auth_methods().contains(&AuthMethod::Password));
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
    fn the_route_the_user_did_not_pick_still_works_after_they_take_it() {
        let mut app = app();
        app.stage = Stage::Auth;
        app.cursor = 1;
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.auth, Some(AuthMethod::External), "the second route");
        assert_eq!(app.stage, Stage::Auth, "and it waits there for the user");

        // Nothing is authorized yet, so saying "I have done it" is refused rather than
        // believed: the wizard checks rather than takes the word for it.
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.stage, Stage::Auth);
        assert!(
            app.problem.is_some(),
            "{}",
            app.problem.clone().unwrap_or_default()
        );
        assert_eq!(app.leaving(), None);
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

            // Saying no leaves the wizard where it was.
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
        let mut app = app();
        app.stage = Stage::Auth;
        app.auth = Some(AuthMethod::Password);
        app.stage = Stage::Privilege;
        char_key(&mut app, 'x');
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Auth, "the gate hands back to the methods");
        assert_eq!(app.password, "", "and it forgets the password");
        assert_eq!(app.leaving(), None);

        // The review is one step behind the answers, and the last question is one step behind
        // the review.
        app.stage = Stage::Review;
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Options);
        assert_eq!(app.question, menu::question_count() - 1);

        // Back through the questions, and off the front of the wizard.
        for expected in (0..menu::question_count() - 1).rev() {
            press(&mut app, KeyCode::Esc);
            assert_eq!(app.question, expected);
        }
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Detect);
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.stage, Stage::Home);
        assert_eq!(app.leaving(), None);
    }

    #[test]
    fn quitting_from_home_is_a_cancel_and_not_an_interruption() {
        let mut app = app();
        assert_eq!(press(&mut app, KeyCode::Esc), Flow::Done(Outcome::Canceled));
        assert_eq!(char_key(&mut app, 'q'), Flow::Done(Outcome::Canceled));
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

        // A key pressed now cannot change the answer that is already on its way.
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
        // Some terminals send the enter key as a control character - ctrl+j is what script(1)
        // sends - and a chord must never leave a stray letter in the field.
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
    fn the_checklist_collapses_a_phase_that_has_finished() {
        let app = run_with(&[
            Status::Ok,
            Status::Ok,
            Status::Ok,
            Status::Ok,
            Status::Running,
        ]);
        let lines = crate::screens::checklist(&app);
        // One line per phase, plus the running step's own line: six rows where the old screen
        // spent nineteen.
        assert_eq!(lines.len(), 6, "{lines:?}");
        assert!(lines.len() < STEPS.len());
    }

    #[test]
    fn the_way_on_from_a_failure_is_a_decision_rather_than_a_dismissal() {
        let mut app = run_with(&[Status::Failed]);
        app.current = 0;
        app.failure = Some(FailureCard::new(&STEPS[0], &[]));
        app.paused = true;
        app.overlay = Some(Overlay::Failure);

        // `esc` closes the card and leaves the failure exactly where it was.
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.overlay, None);
        assert!(app.paused);
        assert_eq!(app.statuses[0], Status::Failed);
        assert_eq!(app.current, 0, "and nothing advanced past it");

        // Enter brings it back rather than starting anything.
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
            // The step is the last one, so carrying on lands on the summary without starting
            // anything.
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
        let tally = app.tally();
        assert_eq!(
            tally.ran() + tally.skipped,
            STEPS.len(),
            "every step either ran or was switched off"
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
    fn a_phase_reports_the_worst_thing_that_happened_in_it() {
        let mut app = app();
        app.begin_install();
        app.statuses[1] = Status::Warn;
        assert_eq!(app.phase_status(Phase::Prepare), Status::Warn);
        let (reached, total) = app.phase_progress(Phase::Prepare);
        assert_eq!((reached, total), (4, 4));
        assert_eq!(app.phase_status(Phase::Finalize), Status::Ok);
        assert!(app.phase_elapsed(Phase::Prepare) > Duration::ZERO);
    }

    #[test]
    fn a_phase_that_has_not_started_reports_nothing_and_the_worst_wins() {
        let app = run_with(&[Status::Ok, Status::Warn, Status::Failed]);
        assert_eq!(app.phase_status(Phase::Prepare), Status::Failed);
        assert_eq!(app.phase_status(Phase::Configure), Status::Pending);
        assert_eq!(app.phase_elapsed(Phase::Prepare), Duration::ZERO);
        assert_eq!(app.phase_progress(Phase::Prepare), (3, 4));
    }

    #[test]
    fn options_reset_one_row_or_all_of_them() {
        let mut app = app();
        app.stage = Stage::Options;
        // The bulk row sits at the top of the question it answers.
        app.question = question_of(menu::PRESET_THEME_APPS);
        app.cursor = 0;
        assert!(
            matches!(app.selected(), Some(Entry::Preset { .. })),
            "the bulk row is the one under the cursor"
        );

        char_key(&mut app, ' ');
        let preset = app.selected().expect("a row");
        assert!(app.is_changed(preset));

        // `r` puts that row back, and a bulk row takes its members with it.
        char_key(&mut app, 'r');
        let preset = app.selected().expect("a row");
        assert!(!app.is_changed(preset));

        // `R` puts everything back, including a row that was changed by hand.
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

        // Enter advances; it does not change the answer under the cursor.
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

        // The last one leads to the review rather than off the end.
        for _ in 1..menu::question_count() {
            press(&mut app, KeyCode::Enter);
        }
        assert_eq!(app.stage, Stage::Review);
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

        // And on a select it steps through the options rather than doing nothing.
        app.question = question_of("DEFAULT_SHELL");
        app.cursor = 0;
        let select = app.selected().map(Entry::id).expect("a select");
        assert_eq!(app.answers.get(select).map(String::as_str), Some("fish"));
        char_key(&mut app, ' ');
        assert_eq!(app.answers.get(select).map(String::as_str), Some("zsh"));
    }

    #[test]
    fn review_scrolls_inside_its_own_list() {
        let mut app = app();
        app.area = Rect::new(0, 0, 80, 24);
        app.stage = Stage::Review;
        let rows = app.review_rows();
        let limit = app.review_limit();
        assert!(rows > 3, "the test terminal has a list to scroll");
        assert!(limit > 0, "and the list is longer than the pane");

        press(&mut app, KeyCode::End);
        assert_eq!(app.review_scroll, limit);
        press(&mut app, KeyCode::Down);
        assert_eq!(app.review_scroll, limit, "and it stops at the end");
        press(&mut app, KeyCode::PageUp);
        assert_eq!(app.review_scroll, limit.saturating_sub(rows));
        press(&mut app, KeyCode::Home);
        assert_eq!(app.review_scroll, 0);
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
        // Ctrl+C twice: the first asks, the second stops and leaves.
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
            Stage::Review,
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
            ("INSTALL_SDDM", "false".to_string()),
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

        // And what was answered reaches the steps, which is the whole point of answering it.
        assert!(
            app.step_environment()
                .iter()
                .any(|(key, value)| *key == "DEFAULT_SHELL" && value == "zsh")
        );

        // Reset goes back to what the script asked for, not to the table's own defaults.
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
    fn a_question_whose_rows_have_all_gone_can_still_be_left() {
        // The app rows go when the machine has none of the apps, and the login screen style goes
        // when the login screen is left alone. Neither leaves the user stuck on a screen.
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of(menu::PRESET_THEME_APPS);
        app.apps = crate::apps::Apps::default();
        for (id, answer) in crate::apps::Apps::default().answers() {
            app.answers.insert(id, answer.to_string());
        }

        assert!(app.current_entries().is_empty());
        assert!(app.selected().is_none());

        // A key that would change a row does nothing rather than panicking.
        char_key(&mut app, ' ');
        char_key(&mut app, 'j');
        assert_eq!(app.cursor, 0);

        press(&mut app, KeyCode::Enter);
        assert_eq!(app.question, 3, "onward still works");
        assert_eq!(app.stage, Stage::Options);

        press(&mut app, KeyCode::Esc);
        assert_eq!(app.question, 2, "and back does too");
    }

    #[test]
    fn leaving_a_question_hides_a_row_without_moving_the_cursor_off_its_neighbour() {
        let mut app = app();
        app.stage = Stage::Options;
        app.question = question_of("INSTALL_SDDM");
        app.cursor = 0;
        let rows = app.current_entries().len();

        // Turning the login screen off takes the style under it with it.
        char_key(&mut app, ' ');
        assert_eq!(app.current_entries().len(), rows - 1);
        assert_eq!(
            app.selected().map(Entry::id),
            Some("INSTALL_SDDM"),
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
