use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::process;
use crate::tmp::TempDir;

// Swaps a whole tree in for another in one rename, so a reader never sees a half-copied
// destination and a failure leaves the previous tree in place. `required` names a file the
// new tree has to contain before it is allowed to replace anything.
pub fn atomic_replace_tree(src: &Path, dest: &Path, required: Option<&str>) -> io::Result<()> {
    if !src.is_dir() {
        return Err(io::Error::other(format!(
            "{} is not a directory",
            src.display()
        )));
    }

    let parent = dest
        .parent()
        .ok_or_else(|| io::Error::other(format!("{} has no parent directory", dest.display())))?;
    let base = dest
        .file_name()
        .ok_or_else(|| io::Error::other(format!("{} has no name", dest.display())))?
        .to_string_lossy()
        .to_string();
    fs::create_dir_all(parent)?;

    let staging = TempDir::new_in(parent, &format!(".{base}.incoming")).ok_or_else(|| {
        io::Error::other(format!("cannot stage the tree in {}", parent.display()))
    })?;
    crate::copy::tree(src, staging.path())?;

    if let Some(required) = required
        && !staging.path().join(required).exists()
    {
        return Err(io::Error::other(format!(
            "the new tree does not carry {required}"
        )));
    }

    let previous = parent.join(format!(".{base}.previous.{}", std::process::id()));
    let _ = fs::remove_dir_all(&previous);

    let had_destination = dest.exists();
    if had_destination {
        fs::rename(dest, &previous)?;
    }

    if let Err(error) = fs::rename(staging.path(), dest) {
        if had_destination {
            let _ = fs::rename(&previous, dest);
        }
        return Err(error);
    }

    if had_destination {
        let _ = fs::remove_dir_all(&previous);
    }
    Ok(())
}

// A copy of a tree under `<root>/<prefix>-<stamp>`, pruned to the newest `keep` snapshots.
// The stamp names the run rather than the content, so two in the same second do not collide.
pub fn snapshot_dir(src: &Path, root: &Path, prefix: &str, keep: usize) -> io::Result<PathBuf> {
    if !src.is_dir() {
        return Err(io::Error::other(format!(
            "{} is not a directory",
            src.display()
        )));
    }
    fs::create_dir_all(root)?;

    let stamp = timestamp().unwrap_or_else(|| "snapshot".to_string());
    let mut destination = root.join(format!("{prefix}-{stamp}"));
    let mut counter = 1;
    while destination.exists() {
        counter += 1;
        destination = root.join(format!("{prefix}-{stamp}-{counter:02}"));
    }

    crate::copy::tree(src, &destination)?;
    prune(root, prefix, keep.max(1))?;

    Ok(destination)
}

fn prune(root: &Path, prefix: &str, keep: usize) -> io::Result<()> {
    let mut snapshots = snapshots_in(root, prefix);
    snapshots.sort();

    let total = snapshots.len();
    for snapshot in snapshots.into_iter().take(total.saturating_sub(keep)) {
        let _ = fs::remove_dir_all(snapshot);
    }
    Ok(())
}

fn snapshots_in(root: &Path, prefix: &str) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(root) else {
        return Vec::new();
    };
    entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().starts_with(&format!("{prefix}-")))
                .unwrap_or(false)
        })
        .collect()
}

pub fn timestamp() -> Option<String> {
    let stamp = process::capture("date", &["+%Y%m%d_%H%M%S"])?;
    if stamp.is_empty() {
        return None;
    }
    Some(stamp)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn work(name: &str) -> TempDir {
        TempDir::new(name).expect("a temporary directory")
    }

    #[test]
    fn a_new_tree_replaces_the_one_that_was_there() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("source");
        let dest = work.path().join("target/tree");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("new.conf"), b"new").expect("a file");
        fs::create_dir_all(work.path().join("target/tree")).expect("the destination");
        fs::write(work.path().join("target/tree/old.conf"), b"old").expect("a file");

        atomic_replace_tree(&source, &dest, None).expect("the tree is swapped in");

        assert!(dest.join("new.conf").is_file());
        assert!(
            !dest.join("old.conf").exists(),
            "the tree that was there is gone, not merged into"
        );
        assert_no_staging(&work.path().join("target"), "tree");
    }

    #[test]
    fn a_missing_destination_is_created_with_its_parents() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("source");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("metadata.json"), b"{}").expect("a file");

        let dest = work.path().join("nested/deeper/tree");
        atomic_replace_tree(&source, &dest, Some("metadata.json")).expect("the tree is installed");

        assert!(dest.join("metadata.json").is_file());
    }

    #[test]
    fn a_tree_without_the_file_it_must_carry_does_not_replace_anything() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("source");
        let dest = work.path().join("target/tree");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("other.conf"), b"x").expect("a file");
        fs::create_dir_all(&dest).expect("the destination");
        fs::write(dest.join("kept.conf"), b"kept").expect("a file");

        assert!(atomic_replace_tree(&source, &dest, Some("metadata.json")).is_err());
        assert!(
            dest.join("kept.conf").is_file(),
            "a refused tree leaves the destination as it was"
        );
        assert_no_staging(&work.path().join("target"), "tree");
    }

    #[test]
    fn a_source_that_is_not_there_is_an_error_rather_than_an_empty_tree() {
        let work = work("caelestia-install-fs-test");
        let dest = work.path().join("target/tree");

        assert!(atomic_replace_tree(&work.path().join("absent"), &dest, None).is_err());
        assert!(
            !dest.exists(),
            "nothing is installed from a source that is not there"
        );
    }

    #[test]
    fn a_snapshot_is_named_after_the_run_and_stamps_a_copy() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("config");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("shell.qml"), b"// shell").expect("a file");
        let root = work.path().join("backups");

        let first = snapshot_dir(&source, &root, "quickshell-caelestia", 3).expect("a snapshot");
        assert!(
            first
                .file_name()
                .unwrap()
                .to_string_lossy()
                .starts_with("quickshell-caelestia-"),
            "{}",
            first.display()
        );
        assert_eq!(
            fs::read_to_string(first.join("shell.qml")).expect("the copy"),
            "// shell"
        );

        let second = snapshot_dir(&source, &root, "quickshell-caelestia", 3).expect("a snapshot");
        assert_ne!(
            first, second,
            "two snapshots taken in the same second are two directories"
        );
    }

    #[test]
    fn only_the_newest_snapshots_are_kept() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("config");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("shell.qml"), b"// shell").expect("a file");
        let root = work.path().join("backups");

        for stamp in ["20240101_000001", "20240101_000002", "20240101_000003"] {
            let old = root.join(format!("quickshell-caelestia-{stamp}"));
            fs::create_dir_all(&old).expect("an older snapshot");
        }

        snapshot_dir(&source, &root, "quickshell-caelestia", 3).expect("a snapshot");

        let mut left = snapshots_in(&root, "quickshell-caelestia");
        left.sort();
        assert_eq!(left.len(), 3, "the limit is what is kept: {left:?}");

        let names: Vec<String> = left
            .iter()
            .map(|path| path.file_name().unwrap().to_string_lossy().to_string())
            .collect();
        assert!(
            !names.iter().any(|name| name.ends_with("20240101_000001")),
            "the oldest goes first: {names:?}"
        );
        assert!(
            names.iter().any(|name| name.ends_with("20240101_000003")),
            "and the newest that was there stays: {names:?}"
        );
    }

    #[test]
    fn a_snapshot_of_a_tree_that_is_not_there_is_an_error() {
        let work = work("caelestia-install-fs-test");
        let root = work.path().join("backups");

        assert!(snapshot_dir(&work.path().join("absent"), &root, "prefix", 3).is_err());
        assert!(
            !root.exists() || snapshots_in(&root, "prefix").is_empty(),
            "nothing is invented for a source that is not there"
        );
    }

    #[test]
    fn a_limit_of_zero_still_keeps_the_snapshot_that_was_just_taken() {
        let work = work("caelestia-install-fs-test");
        let source = work.path().join("config");
        fs::create_dir_all(&source).expect("the source tree");
        fs::write(source.join("shell.qml"), b"// shell").expect("a file");
        let root = work.path().join("backups");

        let snapshot = snapshot_dir(&source, &root, "prefix", 0).expect("a snapshot");

        assert!(
            snapshot.is_dir(),
            "the caller is told where its snapshot went"
        );
        assert_eq!(snapshots_in(&root, "prefix").len(), 1);
    }

    fn assert_no_staging(parent: &Path, base: &str) {
        let leftovers: Vec<String> = fs::read_dir(parent)
            .expect("the parent directory")
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().to_string())
            .filter(|name| name.starts_with(&format!(".{base}.")))
            .collect();
        assert!(leftovers.is_empty(), "staging left behind: {leftovers:?}");
    }
}
