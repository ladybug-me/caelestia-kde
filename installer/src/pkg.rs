use crate::distro::{self, Distro};
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;

pub fn present(package: &str) -> bool {
    match distro::detect() {
        Distro::Arch => process::succeeds("pacman", &["-Qq", package], None),
        Distro::Fedora => process::succeeds("rpm", &["-q", package], None),
        Distro::Debian => process::succeeds("dpkg", &["-s", package], None),
        Distro::Unknown => false,
    }
}

pub fn install(package: &str, confirm: Option<&str>) -> bool {
    let family = distro::detect();
    match family {
        Distro::Arch => {
            let mut args = vec!["-S", "--needed"];
            if let Some(flag) = confirm {
                args.push(flag);
            }
            args.push(package);

            if process::succeeds("yay", &args, None) {
                return true;
            }
            privileges::elevated("pacman", &args, None) == Ok(0)
        }
        Distro::Fedora => privileges::elevated("dnf", &["install", "-y", package], None) == Ok(0),
        Distro::Debian => {
            privileges::elevated("apt-get", &["install", "-y", package], None) == Ok(0)
        }
        Distro::Unknown => {
            output::warn(&format!(
                "No package manager is known for '{}'; cannot install {package}.",
                family.name()
            ));
            false
        }
    }
}

pub fn missing<'a>(packages: &[&'a str]) -> Vec<&'a str> {
    packages
        .iter()
        .copied()
        .filter(|package| !present(package))
        .collect()
}

// One transaction for a set of packages: the managers resolve the dependency graph once,
// and a failure is reported once. This is the direct route (no AUR helper), which is what
// a dependency the distro itself carries wants.
pub fn install_all(packages: &[&str]) -> bool {
    if packages.is_empty() {
        return true;
    }

    let family = distro::detect();
    let (program, mut args): (&str, Vec<&str>) = match family {
        Distro::Arch => ("pacman", vec!["-S", "--noconfirm"]),
        Distro::Fedora => ("dnf", vec!["install", "-y"]),
        Distro::Debian => ("apt-get", vec!["install", "-y"]),
        Distro::Unknown => {
            output::warn(&format!(
                "No package manager is known for '{}'; cannot install {}.",
                family.name(),
                packages.join(" ")
            ));
            return false;
        }
    };
    args.extend_from_slice(packages);
    privileges::elevated(program, &args, None) == Ok(0)
}

pub fn install_first(candidates: &[&str]) -> bool {
    let confirm = std::env::var("CONFIRM_ARG")
        .ok()
        .filter(|value| !value.is_empty());

    let mut failed: Vec<&str> = Vec::new();
    for package in candidates {
        if present(package) {
            output::skip(&format!("{package} already installed."));
            return true;
        }

        output::info(&format!("Installing {package}..."));
        if install(package, confirm.as_deref()) {
            output::ok(&format!("{package} installed."));
            return true;
        }

        output::warn(&format!("Could not install {package}, skipping."));
        failed.push(package);
    }

    for package in failed {
        record_failure(package);
    }
    false
}

pub fn record_failure(package: &str) {
    let directory = paths::cache_dir().join("caelestia-kde");
    if std::fs::create_dir_all(&directory).is_err() {
        return;
    }
    let path = directory.join("failed_packages.txt");
    let existing = std::fs::read_to_string(&path).unwrap_or_default();
    let _ = std::fs::write(&path, format!("{existing}{package}\n"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_is_present_for_an_unknown_distribution() {
        assert!(!present("caelestia-not-a-package-for-any-distro"));
    }

    #[test]
    fn a_set_of_packages_nothing_is_missing_from_needs_no_manager() {
        assert!(install_all(&[]), "an empty set is already satisfied");
    }

    #[test]
    fn what_is_missing_is_reported_in_the_order_it_was_asked_for() {
        assert_eq!(
            missing(&[
                "caelestia-not-a-package-for-any-distro",
                "caelestia-nor-this-one",
            ]),
            [
                "caelestia-not-a-package-for-any-distro",
                "caelestia-nor-this-one"
            ]
        );
        assert_eq!(missing(&[]), Vec::<&str>::new());
    }
}
