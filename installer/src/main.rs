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
mod headless;
mod install_fs;
mod install_kind;
mod journal;
mod js;
mod logline;
mod logout;
mod menu;
mod output;
mod packages;
mod paths;
mod pkg;
mod plan;
mod privileges;
mod process;
mod report;
mod runner;
mod screens;
mod signals;
mod steps;
mod theme;
mod tmp;
mod toolchain;
mod tui;
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

pub(crate) const VERSION: &str = include_str!("../data/tui.version");

const USAGE: &str = "\
caelestia-install [OPTIONS] [BUNDLE_DIR]
caelestia-install step [OPTIONS] STEP_ID
caelestia-install steps [--for install|packaged|update]

  Install, update or remove Caelestia. With no arguments this opens the wizard, which offers
  all three.

Arguments:
  BUNDLE_DIR      the tree to operate on (default: this binary's directory)
  STEP_ID         a step to run on its own, by its id

Options:
  --update        skip the wizard and run the update path
  --uninstall     skip the wizard and run the uninstall path
  --bundle DIR    the tree to operate on, where a bare BUNDLE_DIR would also go
  --ascii         draw with plain ASCII instead of block and arrow glyphs
  --unicode       draw with Unicode even where the locale suggests otherwise
  --light, --dark force the light or the dark theme instead of reading the terminal
  --no-animation  no spinner, no redraw beyond what changed
  --set ID=value  answer one of the wizard's options and skip being asked
  --plan          print the steps this run would take, then stop without changing anything
  --dry-run       the same as --plan
  --json          print the plan as JSON instead of text; needs --plan
  --non-interactive  run the plan without the wizard; needs root or a warm sudo ticket
  --yes           the same as --non-interactive
  --resume        with --non-interactive, skip the steps a previous run already finished
  --debug         write the phase trace to stderr
  --version       print the installer version and exit
  -h, --help      print this help and exit

The wizard adapts to the terminal: it reads NO_COLOR, TERM, COLORTERM and COLORFGBG, and falls
back to plain ASCII and to colors your terminal can actually show. Override it with
CAELESTIA_TUI_GLYPHS=ascii|unicode, CAELESTIA_TUI_THEME=light|dark or
CAELESTIA_TUI_NO_ANIMATION=1.

--set takes the id of an option, as the wizard names it, and a value it can hold: a switch takes
true or false, a select takes one of its options. Repeat it for every answer a script needs.
\"caelestia-install --set SYNC_LOGIN_SCREEN=false --set DEFAULT_SHELL=zsh\" answers two questions and
leaves the rest at their defaults.

--plan answers what this run would do to this machine without doing any of it: the steps, grouped
by phase, with the ones an answer has switched off marked skip. It reads the machine (which apps
are installed, which distribution this is) and changes nothing. --json prints the same plan for a
pipeline. Both exit 0 whether or not steps would be skipped.

--non-interactive runs that same plan without the wizard, streaming each step's output and
recording it in a journal under the user's state directory, so a run that stops can be continued
with --resume instead of started again. It needs root already available - run it with sudo, or
warm the ticket with \"sudo -v\" first - because an unattended run must never wait at a prompt.
Answers come from --set, and anything not answered stays at the default the wizard would have
shown. The look flags belong to the wizard and are refused here rather than ignored.

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
        Invocation::Steps { purpose } => print_steps(purpose),
        Invocation::Run(args) => run(args),
    };

    ExitCode::from(outcome.code())
}

/// The step ids, one per line, so a shell launcher iterates the table instead of restating it.
fn print_steps(purpose: steps::Purpose) -> Outcome {
    for id in steps::ids(purpose) {
        println!("{id}");
    }
    Outcome::Ok
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
    let started = std::time::Instant::now();
    let code = steps::run(step, &context);
    journal::record_here(
        step.id,
        if code == 0 {
            steps::Status::Ok
        } else {
            steps::Status::Failed
        },
        started.elapsed().as_secs(),
    );
    match code {
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
        // A preset is the same handoff the wizard hands to: one place decides what running an
        // update or an uninstall means.
        PresetAction::Update => handoff(
            &bundle,
            app::Session {
                outcome: Outcome::Ok,
                handoff: Some(Handoff::Update),
            },
        ),
        PresetAction::Uninstall => handoff(
            &bundle,
            app::Session {
                outcome: Outcome::Ok,
                handoff: Some(Handoff::Uninstall),
            },
        ),
        PresetAction::Wizard => {
            if args.plan {
                return print_plan(&bundle, &args);
            }
            if args.non_interactive {
                signals::install();
                let answers = plan::answers(&args.set);
                return headless::run(bundle.root(), &answers, args.resume);
            }
            trace("phase 1: home");
            let env = look(&args);
            let session = app::run(bundle.root().to_path_buf(), app::log_path(), env, &args.set);
            handoff(&bundle, session)
        }
    }
}

fn print_plan(bundle: &Bundle, args: &Args) -> Outcome {
    let answers = plan::answers(&args.set);
    let rows = plan::rows(&answers);
    let version = VERSION.trim();
    if args.plan_json {
        println!("{}", plan::json(bundle.root(), version, &answers, &rows));
    } else {
        print!("{}", plan::text(bundle.root(), version, &answers, &rows));
    }
    Outcome::Ok
}

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

fn handoff(bundle: &Bundle, session: Session) -> Outcome {
    match session.handoff {
        None => session.outcome,
        Some(Handoff::Update) => {
            trace("handoff: update");
            let branch = std::env::var("CAELESTIA_UPDATE_BRANCH")
                .ok()
                .filter(|value| !value.is_empty());
            attempted(update::run(bundle.root(), branch))
        }
        Some(Handoff::Uninstall) => {
            trace("handoff: uninstall");
            attempted(uninstall::run(bundle.root()))
        }
        Some(Handoff::LogOut) => {
            trace("handoff: log out");
            match logout::now() {
                Ok(()) => Outcome::Ok,
                Err(problem) => {
                    output::err(&problem);
                    Outcome::Failed
                }
            }
        }
    }
}

/// A preset either finished or it did not. `Failure::Reported` already printed its own message, so
/// only a fresh one is echoed here; both endings are the same exit either way.
fn attempted(result: Result<(), Failure>) -> Outcome {
    match result {
        Ok(()) => Outcome::Ok,
        Err(Failure::Message(problem)) => {
            output::err(&problem);
            Outcome::Failed
        }
        Err(Failure::Reported) => Outcome::Failed,
    }
}
