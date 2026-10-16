use std::fs;
use std::path::Path;

use crate::process;

// The shell's update state, four files under the installed config directory:
//
//   .current_commit   the revision the running shell was built from
//   .update_branch    the tracked update channel (main or dev only)
//   .current_version  the version.env of that revision
//   .checkout         where that revision was built from
//
// `scripts/lib/update-state.sh` is the same contract for the readers that are still shell
// (the updater and the Nexus updates page); the names and the validation are that file's, so
// a Rust writer and a shell reader agree.

const COMMIT: &str = ".current_commit";
const BRANCH: &str = ".update_branch";
const VERSION: &str = ".current_version";
const CHECKOUT: &str = ".checkout";

// Only main and dev are channels. A checkout parked on a feature branch must not silently
// re-point the update channel (#565): anything else leaves the tracked branch alone.
pub fn set_branch(config: &Path, branch: &str) -> bool {
    if !matches!(branch, "main" | "dev") {
        return false;
    }
    if fs::create_dir_all(config).is_err() {
        return false;
    }
    fs::write(config.join(BRANCH), format!("{branch}\n")).is_ok()
}

// Names what is actually installed. A build that was skipped has nothing to record, and a
// tree that is not a checkout has no revision to name.
pub fn record_installed_revision(bundle: &Path, config: &Path) -> bool {
    record(
        bundle,
        config,
        std::env::var("CAELESTIA_SKIP_BUILD").as_deref() == Ok("1"),
    )
}

fn record(bundle: &Path, config: &Path, build_skipped: bool) -> bool {
    if build_skipped || !bundle.join(".git").is_dir() {
        return false;
    }
    if fs::create_dir_all(config).is_err() {
        return false;
    }

    if let Some(branch) =
        process::capture_in("git", &["rev-parse", "--abbrev-ref", "HEAD"], Some(bundle))
    {
        let _ = set_branch(config, &branch);
    }

    let Some(head) = process::capture_in("git", &["rev-parse", "HEAD"], Some(bundle)) else {
        let _ = fs::remove_file(config.join(COMMIT));
        return false;
    };
    if fs::write(config.join(COMMIT), format!("{head}\n")).is_err() {
        return false;
    }

    let _ = fs::write(config.join(CHECKOUT), format!("{}\n", bundle.display()));

    let version = bundle.join(".github").join("version.env");
    if version.is_file() {
        let _ = fs::copy(&version, config.join(VERSION));
    } else if let Some(text) =
        process::capture_in("git", &["show", "HEAD:.github/version.env"], Some(bundle))
    {
        let _ = fs::write(config.join(VERSION), format!("{text}\n"));
    }

    true
}

#[cfg(test)]
fn read(config: &Path, name: &str) -> Option<String> {
    fs::read_to_string(config.join(name))
        .ok()
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    fn run_git(directory: &Path, arguments: &[&str]) -> bool {
        std::process::Command::new("git")
            .args(["-c", "user.email=test@example.com"])
            .args(["-c", "user.name=Test"])
            .args(["-c", "init.defaultBranch=main"])
            .args(arguments)
            .current_dir(directory)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    fn checkout(work: &TempDir, name: &str) -> std::path::PathBuf {
        let repo = work.path().join(name);
        fs::create_dir_all(repo.join(".github")).expect("a repository");
        fs::write(repo.join(".github/version.env"), "VERSION=v1.0.0\n").expect("the version");
        run_git(&repo, &["init", "--quiet"]);
        run_git(&repo, &["add", "-A"]);
        run_git(&repo, &["commit", "--quiet", "-m", "release"]);
        repo
    }

    #[test]
    fn only_a_channel_is_tracked() {
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let config = work.path().join("config");

        assert!(set_branch(&config, "dev"));
        assert_eq!(read(&config, BRANCH).as_deref(), Some("dev"));
        assert!(set_branch(&config, "main"));
        assert_eq!(read(&config, BRANCH).as_deref(), Some("main"));

        assert!(
            !set_branch(&config, "feature/thing"),
            "a feature branch is not a channel"
        );
        assert_eq!(
            read(&config, BRANCH).as_deref(),
            Some("main"),
            "so the channel it was on stays"
        );
    }

    #[test]
    fn the_installed_revision_is_the_commit_the_branch_and_the_version() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let repo = checkout(&work, "repo");
        let config = work.path().join("config");

        assert!(record(&repo, &config, false));

        let head = process::capture_in("git", &["rev-parse", "HEAD"], Some(&repo));
        assert_eq!(read(&config, COMMIT), head);
        assert_eq!(read(&config, BRANCH).as_deref(), Some("main"));
        assert_eq!(
            fs::read_to_string(config.join(VERSION)).expect("the version"),
            "VERSION=v1.0.0\n"
        );
        assert_eq!(
            fs::read_to_string(config.join(CHECKOUT)).expect("the checkout"),
            format!("{}\n", repo.display())
        );
    }

    #[test]
    fn a_build_that_was_skipped_records_nothing() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let repo = checkout(&work, "repo");
        let config = work.path().join("config");

        assert!(
            !record(&repo, &config, true),
            "a skipped build has no revision to claim"
        );
        assert_eq!(read(&config, COMMIT), None);
        assert_eq!(read(&config, VERSION), None);
    }

    #[test]
    fn a_tree_that_is_not_a_checkout_records_nothing() {
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let plain = work.path().join("plain");
        fs::create_dir_all(plain.join(".github")).expect("a tree");
        fs::write(plain.join(".github/version.env"), "VERSION=v1.0.0\n").expect("the version");
        let config = work.path().join("config");

        assert!(!record(&plain, &config, false));
        assert_eq!(read(&config, COMMIT), None);
    }

    #[test]
    fn a_feature_branch_does_not_re_point_the_channel() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let repo = checkout(&work, "repo");
        let config = work.path().join("config");
        assert!(set_branch(&config, "dev"));

        run_git(&repo, &["checkout", "--quiet", "-b", "feature/thing"]);
        assert!(record(&repo, &config, false));

        assert_eq!(
            read(&config, BRANCH).as_deref(),
            Some("dev"),
            "a checkout parked on a feature branch leaves the tracked channel alone"
        );
        assert!(
            read(&config, COMMIT).is_some(),
            "but the revision is recorded"
        );
    }

    #[test]
    fn the_version_comes_from_the_commit_when_the_tree_does_not_carry_it() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-update-state-test").expect("a temporary directory");
        let repo = checkout(&work, "repo");
        let config = work.path().join("config");
        // In the commit but not in the working tree, which is what a tree an update replaced
        // looks like when it carries less than the commit does.
        fs::remove_file(repo.join(".github/version.env")).expect("the version file goes");

        assert!(record(&repo, &config, false));

        assert_eq!(
            fs::read_to_string(config.join(VERSION)).expect("the version"),
            "VERSION=v1.0.0\n"
        );
    }
}
