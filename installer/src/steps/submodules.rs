use std::fs;
use std::path::Path;

use crate::copy;
use crate::output;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

const DOTS: &str = "src/dots";
const ICONS: &str = "src/yet-another-monochrome-icon-set";
const PATH_SUFFIX: &str = ".path";
const URL_SUFFIX: &str = ".url";
const URL_KEYS: &str = r"^submodule\..*\.url";

pub fn run(context: &Context) -> Result<(), Failure> {
    let bundle = &context.bundle;

    if bundle.join(".gitmodules").is_file() {
        output::info("Initializing submodules...");
        prune_removed_submodules(bundle);
        let _ = process::succeeds("git", &["submodule", "sync", "--recursive"], Some(bundle));

        let jobs = process::capture("nproc", &[]).unwrap_or_else(|| "1".to_string());
        let _ = process::succeeds(
            "git",
            &[
                "submodule",
                "update",
                "--init",
                "--recursive",
                "--depth",
                "1",
                "--jobs",
                &jobs,
            ],
            Some(bundle),
        );
    }

    if !has_content(&bundle.join(DOTS)) {
        output::info("src/dots is empty; fetching it another way.");
        if !ensure_content(bundle, DOTS) {
            return Err(unfetchable_dots(bundle));
        }
    }
    output::ok("src/dots ready.");

    if !has_content(&bundle.join(ICONS)) {
        output::info("src/yet-another-monochrome-icon-set is empty; fetching it another way.");
        if ensure_content(bundle, ICONS) {
            output::ok("Icon set ready.");
        } else {
            output::warn(
                "Icon set could not be fetched; the monochrome icon theme will be missing.",
            );
        }
    }
    Ok(())
}

fn unfetchable_dots(bundle: &Path) -> Failure {
    let bundle = bundle.display();
    format!(
        "src/dots is still empty, and the installer cannot deploy without it.\n\
         \n\
         Fetch it by hand:\n\
         \n\
         \x20   git -C \"{bundle}\" submodule update --init --recursive src/dots\n\
         \n\
         Running this step on its own tries again:\n\
         \n\
         \x20   caelestia-install step 02a-submodules --bundle \"{bundle}\"\n\
         \n\
         A checkout that cannot be written to cannot fetch a submodule. If\n\
         this one is the read-only shared folder, clone the repository to a\n\
         writable directory first and install from there."
    )
    .into()
}

fn has_content(directory: &Path) -> bool {
    fs::read_dir(directory)
        .map(|mut entries| entries.next().is_some())
        .unwrap_or(false)
}

fn key_name<'a>(key: &'a str, ending: &str) -> Option<&'a str> {
    key.strip_prefix("submodule.")?
        .strip_suffix(ending)
        .filter(|name| !name.is_empty())
}

fn gitmodules(bundle: &Path, arguments: &[&str]) -> Option<String> {
    let mut full = vec!["config", "--file", ".gitmodules"];
    full.extend_from_slice(arguments);
    process::capture_in("git", &full, Some(bundle))
}

fn recorded_path(bundle: &Path, name: &str) -> Option<String> {
    gitmodules(
        bundle,
        &["--get", &format!("submodule.{name}{PATH_SUFFIX}")],
    )
    .filter(|path| !path.is_empty())
}

fn recorded_url(bundle: &Path, name: &str) -> Option<String> {
    gitmodules(bundle, &["--get", &format!("submodule.{name}{URL_SUFFIX}")])
        .filter(|url| !url.is_empty())
}

fn name_for_path(bundle: &Path, path: &str) -> Option<String> {
    let keys = gitmodules(
        bundle,
        &["--name-only", "--get-regexp", r"^submodule\..*\.path$"],
    )?;

    keys.lines()
        .filter_map(|key| key_name(key, PATH_SUFFIX))
        .find(|name| recorded_path(bundle, name).as_deref() == Some(path))
        .map(str::to_string)
}

fn pinned_commit(bundle: &Path, path: &str) -> Option<String> {
    if !bundle.join(".git").is_dir() {
        return None;
    }
    process::capture_in("git", &["ls-tree", "HEAD", "--", path], Some(bundle))?
        .split_whitespace()
        .nth(2)
        .map(str::to_string)
}

// The URL .gitmodules records is what the content comes from, whether or not the checkout
// can reach the gitlink on its own.
fn fetch_by_clone(bundle: &Path, path: &str) -> bool {
    let Some(name) = name_for_path(bundle, path) else {
        return false;
    };
    let Some(url) = recorded_url(bundle, &name) else {
        return false;
    };
    if !process::available("git") {
        return false;
    }

    let pinned = pinned_commit(bundle, path);
    let Some(work) = TempDir::new("caelestia-submodule") else {
        return false;
    };
    let checkout = work.path().join("clone");

    if !process::succeeds(
        "git",
        &[
            "clone",
            "--quiet",
            "--depth",
            "1",
            "--",
            &url,
            &checkout.to_string_lossy(),
        ],
        None,
    ) {
        return false;
    }

    let cloned =
        process::capture_in("git", &["rev-parse", "HEAD"], Some(&checkout)).unwrap_or_default();
    let unpinned_allowed =
        std::env::var("CAELESTIA_ALLOW_UNPINNED_SUBMODULES").as_deref() == Ok("1");
    if let Some(pinned) = pinned
        && cloned != pinned
        && !unpinned_allowed
    {
        return false;
    }

    let target = bundle.join(path);
    let _ = fs::remove_dir_all(&target);
    if fs::create_dir_all(&target).is_err() {
        return false;
    }
    if copy::tree(&checkout, &target).is_err() {
        return false;
    }

    let _ = fs::remove_dir_all(target.join(".git"));
    has_content(&target)
}

fn ensure_content(bundle: &Path, path: &str) -> bool {
    if has_content(&bundle.join(path)) {
        return true;
    }

    // A stale registration fails the first update; the sync repairs it and the second
    // update is the one that works.
    let attempts: [&[&str]; 3] = [
        &["submodule", "update", "--init", "--recursive", "--", path],
        &["submodule", "sync", "--recursive", "--", path],
        &["submodule", "update", "--init", "--recursive", "--", path],
    ];
    for arguments in attempts {
        let _ = process::succeeds("git", arguments, Some(bundle));
        if has_content(&bundle.join(path)) {
            return true;
        }
    }

    let _ = process::succeeds(
        "git",
        &[
            "submodule",
            "update",
            "--init",
            "--recursive",
            "--force",
            "--",
            path,
        ],
        Some(bundle),
    );
    if has_content(&bundle.join(path)) {
        return true;
    }

    fetch_by_clone(bundle, path)
}

fn prune_removed_submodules(bundle: &Path) {
    let Some(keys) = process::capture_in(
        "git",
        &["config", "--name-only", "--get-regexp", URL_KEYS],
        Some(bundle),
    ) else {
        return;
    };

    for name in keys
        .lines()
        .filter_map(|key| key_name(key, URL_SUFFIX))
        .filter(|name| !name.is_empty())
    {
        if recorded_url(bundle, name).is_some() {
            continue;
        }

        let worktree = process::capture_in(
            "git",
            &["config", "--get", &format!("submodule.{name}{PATH_SUFFIX}")],
            Some(bundle),
        )
        .filter(|path| !path.is_empty())
        .unwrap_or_else(|| name.to_string());

        let _ = process::succeeds("git", &["submodule", "deinit", "-f", name], Some(bundle));
        let _ = process::succeeds(
            "git",
            &["config", "--remove-section", &format!("submodule.{name}")],
            Some(bundle),
        );
        let _ = fs::remove_dir_all(bundle.join(".git").join("modules").join(name));
        let _ = fs::remove_dir_all(bundle.join(worktree));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_directory_with_anything_in_it_has_content() {
        let work = TempDir::new("caelestia-submodules-test").expect("a temporary directory");

        assert!(!has_content(&work.path().join("missing")));
        assert!(!has_content(work.path()));

        fs::write(work.path().join(".hidden"), b"x").expect("a hidden file");
        assert!(has_content(work.path()), "a dotfile is content too");
    }

    #[test]
    fn a_submodule_name_is_read_from_its_key_and_never_left_empty() {
        assert_eq!(
            key_name("submodule.caelestia.path", PATH_SUFFIX),
            Some("caelestia")
        );
        assert_eq!(
            key_name("submodule.src/dots.url", URL_SUFFIX),
            Some("src/dots")
        );
        assert_eq!(key_name("submodule..url", URL_SUFFIX), None);
        assert_eq!(key_name("submodule.caelestia.branch", URL_SUFFIX), None);
        assert_eq!(key_name("nonsubmodule.caelestia.url", URL_SUFFIX), None);
    }
}
