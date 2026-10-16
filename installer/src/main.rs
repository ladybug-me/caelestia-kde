mod app;
mod apps;
mod bundle;
mod cli;
mod copy;
mod distro;
mod download;
mod env;
mod exit;
mod glyphs;
mod install_fs;
mod install_kind;
mod js;
mod logline;
mod menu;
mod output;
mod packages;
mod paths;
mod pkg;
mod privileges;
mod process;
mod runner;
mod screens;
mod signals;
mod steps;
mod theme;
mod tmp;
mod toolchain;
mod ui;
mod uninstall;
mod update;
mod update_state;

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};

use app::{Handoff, Session};
use bundle::Bundle;
use cli::{Args, Invocation, PresetAction};
use env::Env;
use exit::Outcome;
use steps::Failure;

const VERSION: &str = include_str!("../data/tui.version");

const USAGE: &str = "\
caelestia-install [OPTIONS] [BUNDLE_DIR]
caelestia-install step [OPTIONS] STEP_ID

  Install, update or remove Caelestia. With no arguments this opens the wizard, which offers
  all three.

Arguments:
  BUNDLE_DIR      the tree to operate on (default: this binary's directory)
  STEP_ID         a step to run on its own, by its id

Options:
  --update        skip the wizard and run the update path
  --uninstall     skip the wizard and run the uninstall path
  --bundle DIR    the tree a step operates on
  --ascii         draw with plain ASCII instead of block and arrow glyphs
  --unicode       draw with Unicode even where the locale suggests otherwise
  --light, --dark force the light or the dark theme instead of reading the terminal
  --no-animation  no spinner, no redraw beyond what changed
  --set ID=value  answer one of the wizard's options and skip being asked
  --debug         write the phase trace to stderr
  --version       print the installer version and exit
  -h, --help      print this help and exit

The wizard adapts to the terminal: it reads NO_COLOR, TERM, COLORTERM and COLORFGBG, and falls
back to plain ASCII and to colors your terminal can actually show. Override it with
CAELESTIA_TUI_GLYPHS=ascii|unicode, CAELESTIA_TUI_THEME=light|dark or
CAELESTIA_TUI_NO_ANIMATION=1.

--set takes the id of an option, as the wizard names it, and a value it can hold: a switch takes
true or false, a select takes one of its options. Repeat it for every answer a script needs.
\"caelestia-install --set INSTALL_SDDM=false --set DEFAULT_SHELL=zsh\" answers two questions and
leaves the rest at their defaults.

Exit codes:
  0 finished                1 a step failed
  2 bad arguments           3 canceled by the user
  4 wrong place, or missing scripts     5 installer bug
  130 interrupted
";

static DEBUG: AtomicBool = AtomicBool::new(false);

fn trace(message: &str) {
    if DEBUG.load(Ordering::Relaxed) {
        eprintln!("[installer] {message}");
    }
}

fn main() -> ExitCode {
    let invocation = match cli::parse(std::env::args_os().skip(1)) {
        Ok(invocation) => invocation,
        Err(problem) => {
            eprintln!("caelestia-install: {problem}");
            eprint!("{USAGE}");
            return ExitCode::from(Outcome::Usage.code());
        }
    };

    let outcome = match invocation {
        Invocation::Help => {
            print!("{USAGE}");
            Outcome::Ok
        }
        Invocation::Version => {
            println!("{}", VERSION.trim());
            Outcome::Ok
        }
        Invocation::Askpass(pipe) => askpass(&pipe),
        Invocation::Step { id, bundle, debug } => run_step(&id, bundle, debug),
        Invocation::Run(args) => run(args),
    };

    ExitCode::from(outcome.code())
}

fn run_step(id: &str, bundle: Option<PathBuf>, debug: bool) -> Outcome {
    DEBUG.store(debug, Ordering::Relaxed);

    let requested = bundle.or_else(|| std::env::var_os("BUNDLE_DIR").map(PathBuf::from));
    let bundle = Bundle::discover(requested);
    trace(&format!("bundle dir: {}", bundle.root().display()));

    let Some(step) = steps::find(id) else {
        eprintln!("caelestia-install: no step is called '{id}'");
        return Outcome::Usage;
    };
    trace(&format!("step {} ({})", step.id, step.name));

    let context = steps::Context {
        bundle: bundle.root().to_path_buf(),
    };
    match steps::run(step, &context) {
        0 => Outcome::Ok,
        _ => Outcome::Failed,
    }
}

fn askpass(pipe: &Path) -> Outcome {
    match privileges::read_secret(pipe) {
        Ok(secret) => {
            println!("{secret}");
            Outcome::Ok
        }
        Err(problem) => {
            eprintln!("caelestia-install: {problem}");
            Outcome::Environment
        }
    }
}

fn run(args: Args) -> Outcome {
    DEBUG.store(args.debug, Ordering::Relaxed);

    let bundle = Bundle::discover(args.bundle.clone());
    trace(&format!("bundle dir: {}", bundle.root().display()));

    match args.action {
        PresetAction::Update => {
            let branch = std::env::var("CAELESTIA_UPDATE_BRANCH")
                .ok()
                .filter(|value| !value.is_empty());
            match update::run(bundle.root(), branch) {
                Ok(()) => Outcome::Ok,
                Err(Failure::Message(problem)) => {
                    output::err(&problem);
                    Outcome::Failed
                }
                Err(Failure::Reported) => Outcome::Failed,
            }
        }
        PresetAction::Uninstall => match uninstall::run(bundle.root()) {
            Ok(()) => Outcome::Ok,
            Err(Failure::Message(problem)) => {
                output::err(&problem);
                Outcome::Failed
            }
            Err(Failure::Reported) => Outcome::Failed,
        },
        PresetAction::Wizard => {
            if let Err(problem) = bundle.check_scripts() {
                eprintln!("caelestia-install: {problem}");
                return Outcome::Environment;
            }
            trace("phase 1: home");
            let env = look(&args);
            let session = app::run(bundle.root().to_path_buf(), app::log_path(), env, &args.set);
            handoff(&bundle, session)
        }
    }
}

/// The terminal decides, unless the caller said otherwise.
fn look(args: &Args) -> Env {
    let mut env = Env::capture();
    if let Some(glyphs) = &args.look.glyphs {
        env.glyphs = Some(glyphs.clone());
    }
    if let Some(theme) = &args.look.theme {
        env.theme = Some(theme.clone());
    }
    if args.look.no_animation {
        env.no_animation = true;
    }
    env
}

/// The wizard can hand the terminal to the update or the uninstall path, which own their own
/// prompts. That work happens here, after the TUI has given the terminal back.
fn handoff(bundle: &Bundle, session: Session) -> Outcome {
    match session.handoff {
        None => session.outcome,
        Some(Handoff::Update) => {
            trace("handoff: update");
            let branch = std::env::var("CAELESTIA_UPDATE_BRANCH")
                .ok()
                .filter(|value| !value.is_empty());
            match update::run(bundle.root(), branch) {
                Ok(()) => Outcome::Ok,
                Err(Failure::Message(problem)) => {
                    output::err(&problem);
                    Outcome::Failed
                }
                Err(Failure::Reported) => Outcome::Failed,
            }
        }
        Some(Handoff::Uninstall) => {
            trace("handoff: uninstall");
            match uninstall::run(bundle.root()) {
                Ok(()) => Outcome::Ok,
                Err(Failure::Message(problem)) => {
                    output::err(&problem);
                    Outcome::Failed
                }
                Err(Failure::Reported) => Outcome::Failed,
            }
        }
    }
}
