use std::fs;
use std::path::Path;

use crate::process;
use crate::tmp::TempDir;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Verification {
    Match,
    Mismatch,
    Unpublished,
}

const ATTEMPTS: u32 = 3;

fn transient(code: i32) -> bool {
    matches!(code, 6 | 7 | 18 | 28 | 35 | 52 | 55 | 56)
}

pub fn fetch(url: &str, destination: &Path, extra: &[&str]) -> bool {
    let destination_text = destination.to_string_lossy().to_string();
    let mut args: Vec<&str> = vec!["-fsSL", "--connect-timeout", "10"];
    args.extend(extra.iter().copied());
    args.push(url);
    args.push("-o");
    args.push(&destination_text);

    for attempt in 0..ATTEMPTS {
        let code = process::status("curl", &args, None).unwrap_or(-1);
        if code == 0 {
            return true;
        }
        if !transient(code) || attempt + 1 == ATTEMPTS {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_millis(500u64 << attempt));
    }
    false
}

fn probe(url: &str, destination: &Path) -> bool {
    let destination_text = destination.to_string_lossy().to_string();
    process::status_quietly(
        "curl",
        &[
            "-fsSL",
            "--connect-timeout",
            "10",
            url,
            "-o",
            &destination_text,
        ],
        None,
    ) == Some(0)
}

pub fn sha256(file: &Path) -> Option<String> {
    let file = file.to_string_lossy().to_string();
    let digest = process::capture("sha256sum", &[&file])?;
    digest
        .split_whitespace()
        .next()
        .filter(|field| !field.is_empty())
        .map(|field| field.to_string())
}

pub fn verify(url: &str, file: &Path) -> Verification {
    let Some(work) = TempDir::new("caelestia-checksum") else {
        return Verification::Unpublished;
    };
    let sidecar = work.path().join("published.sha256");
    let sidecar_url = format!("{url}.sha256");

    if !probe(&sidecar_url, &sidecar) {
        return Verification::Unpublished;
    }
    let Ok(published) = fs::read_to_string(&sidecar) else {
        return Verification::Unpublished;
    };
    let expected = published
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_string();
    if expected.is_empty() {
        return Verification::Unpublished;
    }

    match sha256(file) {
        Some(actual) if actual == expected => Verification::Match,
        _ => Verification::Mismatch,
    }
}

#[allow(dead_code)]
pub fn is_own_release(url: &str) -> bool {
    url.starts_with("https://github.com/ladybug-me/") && url.contains("/releases/download/")
}

#[allow(dead_code)]
pub fn archive_entries_are_safe(archive: &Path) -> bool {
    let archive = archive.to_string_lossy().to_string();
    let Some(listing) = process::capture("tar", &["-tvzf", &archive]) else {
        return false;
    };

    for line in listing.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Some(mode) = line.split_whitespace().next() else {
            continue;
        };
        if mode.contains('s') || mode.contains('S') {
            return false;
        }
        let Some(name) = line.split_whitespace().last() else {
            continue;
        };
        if name.starts_with('/')
            || name.starts_with("../")
            || name.contains("/../")
            || name.ends_with("/..")
        {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn our_own_release_assets_are_recognised() {
        assert!(is_own_release(
            "https://github.com/ladybug-me/caelestia-kde/releases/download/v1/caelestia-install-x86_64-v0.1.0"
        ));
        assert!(!is_own_release(
            "https://github.com/ladybug-me/caelestia-kde"
        ));
        assert!(!is_own_release(
            "https://github.com/someone-else/thing/releases/download/v1/thing"
        ));
    }

    #[test]
    fn only_an_outage_is_worth_trying_again() {
        for code in [6, 7, 18, 28, 35, 52, 55, 56] {
            assert!(transient(code), "curl {code} is an outage");
        }
        for code in [0, 22, 37, 63] {
            assert!(!transient(code), "curl {code} is not an outage");
        }
    }

    #[test]
    fn a_download_that_is_not_there_does_not_verify() {
        let work = TempDir::new("caelestia-download-test").expect("a temporary directory");
        let file = work.path().join("file");
        fs::write(&file, b"contents").expect("a file");

        assert_eq!(
            verify("file:///nonexistent/caelestia", &file),
            Verification::Unpublished
        );
    }

    #[test]
    fn a_missing_checksum_tool_reports_nothing() {
        let work = TempDir::new("caelestia-download-test").expect("a temporary directory");
        let missing = work.path().join("missing");
        assert!(sha256(&missing).is_none());
    }

    #[test]
    fn an_archive_with_a_setuid_entry_is_refused_before_it_is_unpacked() {
        let work = TempDir::new("caelestia-download-test").expect("a temporary directory");
        let archive = work.path().join("bad.tar.gz");
        let payload = work.path().join("payload");
        fs::create_dir_all(&payload).expect("a payload directory");
        fs::write(payload.join("escape"), b"x").expect("a file");

        let payload_path = payload.to_string_lossy().to_string();
        let archive_path = archive.to_string_lossy().to_string();
        assert!(process::succeeds(
            "tar",
            &["-czf", &archive_path, "-C", &payload_path, "escape"],
            None
        ));
        assert!(archive_entries_are_safe(&archive), "a plain file is safe");

        let missing = work.path().join("missing.tar.gz");
        assert!(
            !archive_entries_are_safe(&missing),
            "a missing archive is not safe"
        );
    }

    #[test]
    fn the_destination_is_written_by_a_fetch() {
        let work = TempDir::new("caelestia-download-test").expect("a temporary directory");
        let source = work.path().join("source");
        fs::write(&source, b"payload").expect("a source file");
        let destination = work.path().join("destination");

        let url = format!("file://{}", source.display());
        assert!(fetch(&url, &destination, &[]));
        assert_eq!(
            fs::read_to_string(&destination).expect("the destination"),
            "payload"
        );
    }

    #[test]
    fn a_download_that_fails_reports_it() {
        let work = TempDir::new("caelestia-download-test").expect("a temporary directory");
        let destination: PathBuf = work.path().join("destination");
        assert!(!fetch("file:///nonexistent/caelestia", &destination, &[]));
    }
}
