use std::path::Path;
use std::time::{Duration, Instant};

use crate::exit::Outcome;
use crate::journal::Journal;
use crate::menu::Answers;
use crate::output;
use crate::privileges;
use crate::runner::Running;
use crate::steps::{self, STEPS, Status, Step};

const POLL: Duration = Duration::from_millis(50);

pub fn run(bundle: &Path, answers: &Answers, resume: bool) -> Outcome {
    if !privileges::is_root() && !privileges::sudo_cached() {
        eprintln!(
            "caelestia-install: an unattended install needs root already available: run `sudo -v` \
             first, or run the installer itself with sudo."
        );
        return Outcome::Environment;
    }

    let plan = crate::journal::plan_id(answers);
    let mut journal = Journal::for_plan(&plan);
    if !resume {
        journal.clear();
    }
    if resume {
        output::info(&format!("journal: {}", journal.path().display()));
        for (id, status) in journal.problems() {
            if status == Status::Warn {
                output::info(&format!("{id} finished with a warning last time"));
            } else {
                output::warn(&format!(
                    "{id} stopped at {} last time; running it again",
                    status.as_journal()
                ));
            }
        }
    }
    let log = crate::app::log_path();
    let env = steps::environment(answers, bundle);

    let planned = STEPS
        .iter()
        .filter(|step| !steps::is_skipped(step, answers))
        .count();
    let mut ran = 0;
    let mut resumed = 0;

    for step in STEPS.iter() {
        if steps::is_skipped(step, answers) {
            output::skip(&format!("{} is switched off", step.name));
            journal.record(step.id, Status::Skipped, 0);
            continue;
        }
        if resume && journal.done(step.id) {
            output::skip(&format!("{} was already done", step.name));
            resumed += 1;
            continue;
        }

        output::info(&format!("{}  {}", step.id, step.name));
        let started = Instant::now();
        match execute(step, bundle, &log, &env) {
            Ok(Status::Ok) => {
                journal.record(step.id, Status::Ok, started.elapsed().as_secs());
                output::ok(step.name);
            }
            Ok(Status::Warn) => {
                journal.record(step.id, Status::Warn, started.elapsed().as_secs());
                output::warn(step.name);
            }
            Ok(Status::Skipped) => {
                journal.record(step.id, Status::Skipped, started.elapsed().as_secs());
                output::skip(step.name);
            }
            Ok(_) => {
                journal.record(step.id, Status::Failed, started.elapsed().as_secs());
                output::err(&format!("{} failed", step.name));
                return Outcome::Failed;
            }
            Err(problem) => {
                journal.record(step.id, Status::Failed, started.elapsed().as_secs());
                output::err(&format!("{}: {problem}", step.name));
                return Outcome::Failed;
            }
        }
        ran += 1;
    }

    if resumed > 0 {
        output::ok(&format!(
            "{ran} steps ran, {resumed} were already done of {planned} planned"
        ));
    } else {
        output::ok(&format!("{ran} of {planned} steps ran"));
    }
    Outcome::Ok
}

fn execute(
    step: &Step,
    bundle: &Path,
    log: &Path,
    env: &[(&'static str, String)],
) -> Result<Status, String> {
    let mut running = Running::spawn_native(bundle, step.id, log, env)?;
    let mut lines: Vec<String> = Vec::new();
    let mut printed = 0;

    loop {
        running.drain(&mut lines);
        while printed < lines.len() {
            println!("{}", lines[printed].trim_end());
            printed += 1;
        }

        if crate::signals::terminated() {
            running.stop();
            return Err("interrupted".to_string());
        }

        match running.poll()? {
            Some(status) => {
                running.drain(&mut lines);
                while printed < lines.len() {
                    println!("{}", lines[printed].trim_end());
                    printed += 1;
                }
                return Ok(running.outcome(status));
            }
            None => std::thread::sleep(POLL),
        }
    }
}
