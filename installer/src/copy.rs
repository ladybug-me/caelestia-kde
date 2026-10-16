use std::fs;
use std::io;
use std::path::Path;

pub fn file(source: &Path, target: &Path) -> io::Result<u64> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(source, target)
}

// `cp -a`, minus the timestamps: the contents of `source` land in `target`, keeping
// the shape and the permissions, and leaving a symlink a symlink.
pub fn tree(source: &Path, target: &Path) -> io::Result<()> {
    fs::create_dir_all(target)?;

    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let destination = target.join(entry.file_name());

        if file_type.is_dir() {
            tree(&entry.path(), &destination)?;
        } else if file_type.is_symlink() {
            link(&entry.path(), &destination)?;
        } else {
            fs::copy(entry.path(), &destination)?;
        }
    }
    Ok(())
}

#[cfg(unix)]
fn link(source: &Path, target: &Path) -> io::Result<()> {
    std::os::unix::fs::symlink(fs::read_link(source)?, target)
}

#[cfg(not(unix))]
fn link(source: &Path, target: &Path) -> io::Result<()> {
    fs::copy(source, target).map(|_| ())
}

// `ln -sf`: whatever the link was before is replaced rather than written through.
pub fn symlink(link: &Path, target: &Path) -> io::Result<()> {
    if let Some(parent) = link.parent() {
        fs::create_dir_all(parent)?;
    }
    let _ = fs::remove_file(link);

    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(target, link)
    }
    #[cfg(not(unix))]
    {
        let _ = target;
        Err(io::Error::other("symlinks need a unix"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn a_tree_lands_whole_and_loses_what_the_target_had() {
        let work = TempDir::new("caelestia-copy-test").expect("a temporary directory");
        let source = work.path().join("source");
        let target = work.path().join("target");
        fs::create_dir_all(source.join("nested")).expect("a nested directory");
        fs::write(source.join("top.conf"), b"top").expect("a file");
        fs::write(source.join("nested").join("deep.conf"), b"deep").expect("a file");

        tree(&source, &target).expect("the tree is copied");

        assert_eq!(
            fs::read_to_string(target.join("top.conf")).expect("the file"),
            "top"
        );
        assert_eq!(
            fs::read_to_string(target.join("nested").join("deep.conf")).expect("the file"),
            "deep"
        );
    }

    #[test]
    fn an_unreadable_source_is_an_error_rather_than_an_empty_copy() {
        let work = TempDir::new("caelestia-copy-test").expect("a temporary directory");
        let target = work.path().join("target");

        assert!(tree(&work.path().join("absent"), &target).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_replaces_what_the_link_was_before() {
        let work = TempDir::new("caelestia-copy-test").expect("a temporary directory");
        let first = work.path().join("first.conf");
        let second = work.path().join("second.conf");
        fs::write(&first, b"first").expect("a file");
        fs::write(&second, b"second").expect("a file");

        let link = work.path().join("nested/face");
        symlink(&link, &first).expect("the link is made");
        assert_eq!(fs::read_to_string(&link).expect("the target"), "first");

        symlink(&link, &second).expect("the link is remade");
        assert!(fs::symlink_metadata(&link).expect("the link").is_symlink());
        assert_eq!(fs::read_to_string(&link).expect("the target"), "second");
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_is_copied_as_a_symlink() {
        let work = TempDir::new("caelestia-copy-test").expect("a temporary directory");
        let source = work.path().join("source");
        let target = work.path().join("target");
        fs::create_dir_all(&source).expect("a source directory");
        fs::write(source.join("real.conf"), b"real").expect("a file");
        std::os::unix::fs::symlink("real.conf", source.join("link.conf")).expect("a symlink");

        tree(&source, &target).expect("the tree is copied");

        let copied = target.join("link.conf");
        assert!(
            fs::symlink_metadata(&copied)
                .expect("the link")
                .is_symlink()
        );
        assert_eq!(fs::read_to_string(&copied).expect("the file"), "real");
    }

    #[cfg(unix)]
    #[test]
    fn a_copied_file_keeps_the_permission_bits_it_had() {
        use std::os::unix::fs::PermissionsExt;

        let work = TempDir::new("caelestia-copy-test").expect("a temporary directory");
        let script = work.path().join("script.sh");
        fs::write(&script, b"#!/bin/sh\n").expect("a file");
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).expect("a mode");

        let target = work.path().join("copied.sh");
        file(&script, &target).expect("the file is copied");

        let mode = fs::metadata(&target)
            .expect("the copy")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o755);
    }
}
