use crate::distro::{self, Distro};
use crate::privileges;
use crate::process;

// What the shell build can link against, in the same words the build stamp stores: a
// pkg-config version, "sdk" for headers that are there without one, or "none". One probe,
// so the stamp and the guard cannot disagree.
pub fn cava_state() -> String {
    if let Some(version) = process::capture("pkg-config", &["--modversion", "libcava"])
        .filter(|version| !version.is_empty())
        .or_else(|| {
            process::capture("pkg-config", &["--modversion", "cava"]).filter(|v| !v.is_empty())
        })
    {
        return version;
    }
    if std::path::Path::new("/usr/include/cava/cavacore.h").exists() {
        return "sdk".to_string();
    }
    "none".to_string()
}

pub fn linguist_tools_available() -> bool {
    let fallback = std::env::var("CAELESTIA_LRELEASE_FALLBACK")
        .unwrap_or_else(|_| "/usr/lib/qt6/bin/lrelease".to_string());
    process::available("lrelease") || process::is_executable(std::path::Path::new(&fallback))
}

// The distro is named rather than detected here for the same reason the package layer
// names it everywhere: "whichever manager is on PATH" answers for the wrong package
// universe on a machine with a second one installed.
pub fn install_linguist_tools() -> bool {
    if linguist_tools_available() {
        return true;
    }

    match distro::detect() {
        Distro::Arch => {
            privileges::elevated(
                "pacman",
                &["-S", "--needed", "--noconfirm", "qt6-tools"],
                None,
            ) == Ok(0)
        }
        Distro::Fedora => {
            privileges::elevated("dnf", &["install", "-y", "qt6-qttools-devel"], None) == Ok(0)
        }
        Distro::Debian => {
            privileges::elevated(
                "apt-get",
                &["install", "-y", "qt6-l10n-tools", "qt6-tools-dev"],
                None,
            ) == Ok(0)
        }
        Distro::Unknown => false,
    }
}

pub fn cava_sdk_installed() -> bool {
    cava_state() != "none"
}

pub fn install_cava_sdk() -> bool {
    let suffix = match distro::detect() {
        Distro::Arch => "arch",
        Distro::Fedora => "fedora",
        Distro::Debian => "ubuntu",
        Distro::Unknown => return false,
    };

    let arch = std::env::var("CAELESTIA_TARGET_ARCH")
        .ok()
        .filter(|arch| !arch.is_empty())
        .or_else(|| process::capture("uname", &["-m"]))
        .unwrap_or_else(|| "x86_64".to_string());
    let url = format!(
        "https://github.com/ladybug-me/cava/releases/download/continuous/cava-{arch}-{suffix}.tar.gz"
    );

    let Some(work) = crate::tmp::TempDir::new("caelestia-cava") else {
        return false;
    };
    let archive = work.path().join("cava.tar.gz");
    if !crate::download::fetch(&url, &archive, &[]) {
        return false;
    }

    match crate::download::verify(&url, &archive) {
        crate::download::Verification::Mismatch => {
            crate::output::warn(&format!("Checksum mismatch for {url} - not unpacking it."));
            return false;
        }
        crate::download::Verification::Unpublished => {
            if !crate::download::is_own_release(&url)
                && let Some(digest) = crate::download::sha256(&archive)
            {
                crate::output::warn(&format!(
                    "No published checksum for {url} - unpacking without verification (SHA-256 {digest})."
                ));
            }
        }
        crate::download::Verification::Match => {}
    }

    // The archive is unpacked as root and tar takes the mode and the owner from it, so the
    // entries themselves have to be safe when there is no published hash to check.
    if !crate::download::archive_entries_are_safe(&archive) {
        crate::output::warn(&format!(
            "Refusing to unpack {url}: the archive has setuid, setgid or escaping entries."
        ));
        return false;
    }

    let archive = archive.to_string_lossy().to_string();
    let args = [
        "--no-same-owner",
        "--no-same-permissions",
        "--exclude=bin",
        "-C",
        "/usr",
        "-xzf",
        &archive,
    ];
    if privileges::is_root() {
        return process::status("tar", &args, None) == Some(0);
    }
    privileges::elevated("tar", &args, None) == Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_cava_probe_reports_something_it_can_compare() {
        let state = cava_state();
        assert!(!state.is_empty(), "the stamp needs a word for every state");
        assert!(
            state == "none" || state == "sdk" || state.starts_with(|c: char| c.is_ascii_digit()),
            "a version, the sdk, or none: {state}"
        );
        assert_eq!(cava_sdk_installed(), state != "none");
    }

    #[test]
    fn the_linguist_tools_are_looked_for_by_name_and_by_the_fallback_path() {
        assert_eq!(
            linguist_tools_available(),
            process::available("lrelease")
                || std::path::Path::new("/usr/lib/qt6/bin/lrelease").is_file()
        );
    }
}
