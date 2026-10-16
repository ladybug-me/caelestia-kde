use std::fs;
use std::path::Path;

use crate::distro::{self, Distro};
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

pub fn run(_context: &Context) -> Result<(), Failure> {
    match distro::detect() {
        Distro::Arch => arch(),
        Distro::Fedora => fedora(),
        Distro::Debian => debian(),
        Distro::Unknown => Ok(()),
    }
}

fn arch() -> Result<(), Failure> {
    ensure_yay()?;
    enable_ccache()
}

fn ensure_yay() -> Result<(), Failure> {
    if process::available("yay") {
        output::ok("yay is already installed.");
        return Ok(());
    }

    output::info("yay not found, installing...");
    if !process::available("pacman") {
        return Err("pacman not found. This installer requires Arch Linux.".into());
    }

    elevated(
        "pacman",
        &["-S", "--needed", "--noconfirm", "base-devel", "git"],
    )?;

    let work = TempDir::new("caelestia-yay")
        .ok_or_else(|| "could not create a working directory for yay".to_string())?;
    let checkout = work.path().join("yay-bin");
    let destination = checkout.to_string_lossy().to_string();
    if !process::succeeds(
        "git",
        &[
            "clone",
            "--depth",
            "1",
            "https://aur.archlinux.org/yay-bin.git",
            &destination,
        ],
        None,
    ) {
        return Err("could not clone yay-bin from the AUR".into());
    }
    if process::status("makepkg", &["-si", "--noconfirm"], Some(&checkout)) != Some(0) {
        return Err("could not build yay with makepkg".into());
    }

    output::ok("yay installed.");
    Ok(())
}

fn enable_ccache() -> Result<(), Failure> {
    output::info("Enabling ccache for makepkg builds (caches AUR rebuilds)...");

    if !process::available("ccache") {
        output::info("ccache not found, installing...");
        elevated("pacman", &["-S", "--needed", "--noconfirm", "ccache"])?;
    }

    let makepkg_conf = Path::new("/etc/makepkg.conf");
    if let Ok(text) = fs::read_to_string(makepkg_conf)
        && text.contains("!ccache")
    {
        output::info("Enabling ccache in /etc/makepkg.conf (system-wide makepkg setting)...");
        let state = paths::state_dir().join("caelestia");
        let _ = fs::create_dir_all(&state);
        let _ = fs::write(state.join("ccache-enabled"), "");
        elevated("sed", &["-i", "s/!ccache/ccache/", "/etc/makepkg.conf"])?;
    }
    output::ok("makepkg ccache configured.");

    output::info("Configuring yay sudo looping and disabling interactive menus...");
    let _ = process::status_quietly(
        "yay",
        &[
            "-Y",
            "--sudoloop",
            "--nocleanmenu",
            "--nodiffmenu",
            "--save",
        ],
        None,
    );
    output::ok("yay configured.");
    Ok(())
}

fn fedora() -> Result<(), Failure> {
    output::info("Checking for Fedora prerequisites (dnf, yq, createrepo_c, jq)...");

    if !process::available("dnf") {
        return Err("dnf not found. This installer requires Fedora 42 or later.".into());
    }

    if process::available("yq") && process::available("createrepo_c") && process::available("jq") {
        output::ok("Prerequisites are already installed.");
        return Ok(());
    }

    output::info("Missing prerequisites, installing...");
    elevated("dnf", &["install", "-y", "yq", "createrepo_c", "jq"])?;
    output::ok("Prerequisites installed.");
    Ok(())
}

fn debian() -> Result<(), Failure> {
    output::info("Checking for Debian prerequisites (apt-get, yq, jq, build-essential)...");

    if !process::available("apt-get") {
        return Err(
            "apt-get not found. This installer requires a Debian-based distribution.".into(),
        );
    }

    if process::available("yq") && process::available("jq") && process::available("g++") {
        output::ok("Prerequisites are already installed.");
        return Ok(());
    }

    output::info("Missing prerequisites, installing...");
    elevated("apt-get", &["update"])?;
    elevated(
        "apt-get",
        &[
            "install",
            "-y",
            "yq",
            "jq",
            "build-essential",
            "git",
            "curl",
        ],
    )?;
    output::ok("Prerequisites installed.");
    Ok(())
}

fn elevated(program: &str, args: &[&str]) -> Result<(), Failure> {
    match privileges::elevated(program, args, None) {
        Ok(0) => Ok(()),
        Ok(code) => {
            output::err(&format!("{program} {} exited {code}", args.join(" ")));
            Err(Failure::Reported)
        }
        Err(problem) => Err(problem.into()),
    }
}
