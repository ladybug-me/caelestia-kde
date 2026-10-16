use std::fs;
use std::path::Path;

use crate::distro::{self, Distro};
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};

const SESSION_PACKAGES: [&str; 5] = [
    "kwin",
    "plasma-workspace",
    "libplasma",
    "qt6-base",
    "qt6-declarative",
];

pub fn run(context: &Context) -> Result<(), Failure> {
    let stamp = paths::state_dir().join("caelestia").join("stale-session");

    if stamp.is_file() {
        let recorded = fs::read_to_string(&stamp).unwrap_or_default();
        let recorded = recorded.trim().to_string();
        if !recorded.is_empty() && session_identity().as_deref() == Some(recorded.as_str()) {
            output::err("This Plasma session still predates the last KWin/Qt upgrade. Log out and");
            output::err("back in (or reboot), then run the installer again.");
            return Err(Failure::Reported);
        }
        let _ = fs::remove_file(&stamp);
    }

    if context.flag("SKIP_SYSTEM_UPDATE", false) {
        output::info("Skipping full system update (SKIP_SYSTEM_UPDATE=true).");
        return Ok(());
    }

    let confirm = context.variable("CONFIRM_ARG").is_some();
    match distro::detect() {
        Distro::Arch => upgrade_arch(&stamp, context),
        Distro::Fedora => {
            let mut args = vec!["upgrade", "--refresh"];
            if confirm {
                args.push("-y");
            }
            escalate_or_fail("dnf", &args)
        }
        Distro::Debian => {
            escalate_or_fail("apt-get", &["update"])?;
            let mut args = vec!["upgrade"];
            if confirm {
                args.push("-y");
            }
            escalate_or_fail("apt-get", &args)
        }
        Distro::Unknown => {
            output::warn("Distro not set properly, skipping system update.");
            Ok(())
        }
    }
}

fn upgrade_arch(stamp: &Path, context: &Context) -> Result<(), Failure> {
    let flag = context.variable("CONFIRM_ARG");
    let mut args: Vec<&str> = vec!["-Syu"];
    if let Some(flag) = flag.as_deref() {
        args.push(flag);
    }

    let before = session_package_versions();
    escalate_or_fail("pacman", &args)?;

    let after = session_package_versions();
    if after == before {
        return Ok(());
    }

    output::err("The upgrade replaced packages the running session still has loaded in memory:");
    for index in 0..SESSION_PACKAGES.len() {
        let had = &before[index];
        let now = &after[index];
        if had != now {
            output::err(&format!("had {had}"));
            output::err(&format!("now {now}"));
        }
    }
    output::err("Building and loading the Caelestia KWin plugin now would link against the new");
    output::err("libraries while the live KWin still runs the old ones, which fails later with");
    output::err("errors that look unrelated to this upgrade.");
    output::err("Exit the installer, log out and back in (or reboot), then run it again - the");
    output::err("upgrade is already applied, so the re-run goes straight to the rest.");

    if let Some(identity) = session_identity() {
        if let Some(parent) = stamp.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(stamp, format!("{identity}\n"));
    }
    Err(Failure::Reported)
}

fn escalate_or_fail(program: &str, args: &[&str]) -> Result<(), Failure> {
    match privileges::elevated(program, args, None) {
        Ok(0) => Ok(()),
        Ok(code) => {
            output::err(&format!("{program} {} exited {code}", args.join(" ")));
            Err(Failure::Reported)
        }
        Err(problem) => Err(problem.into()),
    }
}

fn session_package_versions() -> Vec<String> {
    SESSION_PACKAGES
        .iter()
        .map(|package| {
            process::capture("pacman", &["-Q", package])
                .filter(|text| !text.is_empty())
                .unwrap_or_else(|| format!("{package} not-installed"))
        })
        .collect()
}

fn session_identity() -> Option<String> {
    let (pid, started) = kwin_process()?;
    Some(format!("{pid} {started}"))
}

fn kwin_process() -> Option<(u32, String)> {
    let mut processes: Vec<(u32, String)> = Vec::new();
    for entry in fs::read_dir("/proc").ok()? {
        let Ok(entry) = entry else { continue };
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|name| name.parse::<u32>().ok())
        else {
            continue;
        };
        let Ok(name) = fs::read_to_string(entry.path().join("comm")) else {
            continue;
        };
        processes.push((pid, name.trim().to_string()));
    }

    let pick = |wanted: &str| {
        processes
            .iter()
            .filter(|(_, name)| name == wanted)
            .map(|(pid, _)| *pid)
            .min()
    };

    let pid = pick("kwin_wayland").or_else(|| pick("kwin_x11"))?;
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    Some((pid, start_time(&stat)?))
}

fn start_time(stat: &str) -> Option<String> {
    let after_name = stat.rsplit_once(')')?.1;
    let mut fields = after_name.split_whitespace();
    fields.nth(19).map(|value| value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_session_identity_is_the_start_time_from_the_statement() {
        let stat =
            "1234 (kwin_wayland) S 1 1234 1234 0 -1 4194560 1 0 0 0 1 2 3 4 20 0 1 0 98765 100 200";
        assert_eq!(start_time(stat).as_deref(), Some("98765"));
    }

    #[test]
    fn a_process_name_with_spaces_does_not_shift_the_start_time() {
        let plain = "1234 (kwin_wayland) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 98765";
        let spaced = "1234 (kwin wayland) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 98765";
        assert_eq!(start_time(plain), start_time(spaced));
    }

    #[test]
    fn a_statement_without_the_field_has_no_start_time() {
        assert!(start_time("1234 (kwin_wayland) S 1 2").is_none());
        assert!(start_time("no parentheses here").is_none());
    }
}
