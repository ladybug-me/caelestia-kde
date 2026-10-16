use std::path::Path;

use crate::output;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;
use crate::toolchain;

use super::{
    Failures, Group, elevated, elevated_in, grouped, install_darkly_gtk_theme, link_sassc,
    run_visibly, run_xdg_user_dirs, wanted, with_clone,
};

// The lists are data: whitespace-separated, so a package does not take a line of
// its own, and read back through `names`.
pub(super) const CORE: &str = "
    cmake ninja ccache qt6-tools extra-cmake-modules gcc-libs glibc rsync wl-clipboard cliphist
    wl-clip-persist inotify-tools app2unit wireplumber trash-cli jq aubio lm_sensors libpipewire
    pulseaudio-qt libpulse fftw qt6-base qt6-declarative qt6-wayland qt6-shadertools qt6-svg
    qt6-multimedia qt6-5compat qt6-imageformats kglobalaccel kglobalacceld kguiaddons
    kwindowsystem kcoreaddons kconfig networkmanager-qt kpipewire kwin ffmpeg libqalculate
    libsecret ksshaskpass libx11 vulkan-headers protobuf openssl avahi
";

pub(super) const SHELL: &str = "
    quickshell matugen python foot eza fastfetch starship btop bash pciutils
";

pub(super) const THEMES: &str = "
    adw-gtk-theme ttf-jetbrains-mono-nerd ttf-material-symbols-variable ttf-rubik-vf
    ttf-cascadia-code-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji
";

pub(super) const UTILITIES: &str = "
    fuzzel swappy ddcutil networkmanager imagemagick tesseract tesseract-data-eng satty
    spectacle gpu-screen-recorder slurp grim brightnessctl power-profiles-daemon xdg-utils sassc
    bat ripgrep lazygit xdg-user-dirs
";

// The AUR packages whose build has a repository of its own, tried once makepkg has failed.
const SOURCE_BUILD_REPOS: [(&str, &str); 2] = [
    ("ttf-rubik-vf", "https://github.com/googlefonts/rubik"),
    ("app2unit", "https://github.com/Vladimir-csp/app2unit"),
];

pub fn run(context: &Context, group: Group) -> Result<(), Failure> {
    output::info("Installing Arch packages...");
    ensure_yay();

    let mut packages = grouped(group, CORE, SHELL, THEMES, UTILITIES);

    if group.covers(Group::Shell)
        && wanted(
            context,
            "INSTALL_FISH",
            "Skipping Fish installation by user choice.",
        )
    {
        packages.push("fish");
    }
    if group.covers(Group::Themes)
        && wanted(
            context,
            "INSTALL_PAPIRUS",
            "Skipping Papirus icon theme installation by user choice.",
        )
    {
        packages.push("papirus-icon-theme");
    }

    // libcava is the one target no package manager can answer for: the prebuilt SDK provides
    // it without being a package, so the SDK is asked for first and the package only if it
    // did not arrive.
    if group.covers(Group::Core) {
        if toolchain::cava_sdk_installed() || toolchain::install_cava_sdk() {
            output::info("CAVA SDK ready.");
        } else {
            packages.push("libcava");
        }
    }

    let darkly = group.covers(Group::Themes)
        && wanted(
            context,
            "INSTALL_DARKLY",
            "Skipping Darkly package installation by user choice.",
        );
    if darkly {
        packages.push("darkly-bin");
    }

    remove_stale_caelestia_bin_repository();

    output::info(&format!("Installing packages (group: {})...", group.name()));
    let mut failures = Failures::default();
    install_batch(&packages, group, &mut failures);

    if darkly && !super::darkly_gtk_installed() {
        output::info("Installing Darkly GTK theme...");
        // sassc is the build dependency upstream's install.sh needs; it is asked for the way
        // everything else here is, through the AUR helper first.
        let _ = run_visibly("yay", &["-S", "--needed", "--noconfirm", "sassc"], None)
            || elevated("pacman", &["-S", "--needed", "--noconfirm", "sassc"]);
        if !install_darkly_gtk_theme() {
            failures.add("darkly-gtk");
        }
    }

    run_xdg_user_dirs();
    link_sassc();

    failures.report();
    output::ok("Arch package installation complete.");
    Ok(())
}

// yay is what reaches the AUR, and several of the packages below only exist there. It is
// bootstrapped from its own package rather than from a helper the distribution does not ship.
fn ensure_yay() {
    if process::available("yay") {
        return;
    }

    output::info("yay not found - installing...");
    let _ = privileges::elevated(
        "pacman",
        &["-S", "--needed", "--noconfirm", "base-devel", "git"],
        None,
    );

    let Some(work) = TempDir::new("caelestia-yay") else {
        output::warn("Could not create a directory to build yay in.");
        return;
    };
    let cloned = run_visibly(
        "git",
        &[
            "clone",
            "--depth",
            "1",
            "https://aur.archlinux.org/yay-bin.git",
            ".",
        ],
        Some(work.path()),
    );
    if cloned {
        let _ = run_visibly("makepkg", &["-si", "--noconfirm"], Some(work.path()));
    }

    if !process::available("yay") {
        output::warn("yay could not be installed; AUR packages will not be available.");
    }
}

// One transaction for the whole group, then one attempt per package that is still missing:
// a single package the AUR cannot resolve must not take the rest of the group with it.
fn install_batch(packages: &[&str], group: Group, failures: &mut Failures) {
    let missing = pkg::missing(packages);
    if missing.is_empty() {
        output::info(&format!(
            "All requested packages for group {} are already installed.",
            group.name()
        ));
        return;
    }

    let mut args: Vec<&str> = vec!["-S", "--needed", "--noconfirm"];
    args.extend(missing.iter().copied());
    if run_visibly("yay", &args, None) {
        return;
    }

    output::info("Batch install had failures. Retrying individually...");
    for package in &missing {
        if pkg::present(package) {
            continue;
        }

        if !run_visibly("yay", &["-S", "--needed", "--noconfirm", package], None) {
            output::info(&format!(
                "yay failed to install {package}. Attempting manual build from AUR..."
            ));
            if !build_from_aur(package) && !build_from_source(package) {
                failures.add(package);
            }
        }
    }
}

fn build_from_aur(package: &str) -> bool {
    let url = format!("https://aur.archlinux.org/{package}.git");
    let built = with_clone(&url, &[], |directory| {
        if run_visibly("makepkg", &["-si", "--noconfirm"], Some(directory)) {
            return true;
        }
        output::err(&format!("Manual build from AUR for {package} failed."));
        false
    });

    if !built {
        output::err(&format!(
            "Could not fetch the AUR repository for {package}."
        ));
    }
    built
}

fn build_from_source(package: &str) -> bool {
    let Some((_, url)) = SOURCE_BUILD_REPOS.iter().find(|(name, _)| *name == package) else {
        output::err(&format!("No source repository mapping for {package}."));
        return false;
    };

    output::info(&format!("Compiling {package} from source ({url})..."));
    let built = with_clone(url, &[], |directory| build_detected(package, directory));
    if built {
        output::info(&format!("Built {package} from source."));
    }
    built
}

// Upstream repositories in this list use whatever build system they grew up with, so the
// system is read off the tree rather than assumed. Each one installs as root, which is why
// every branch ends in the escalated install.
fn build_detected(package: &str, directory: &Path) -> bool {
    let built = if directory.join("meson.build").is_file() {
        run_visibly("meson", &["setup", "build"], Some(directory))
            && run_visibly("meson", &["compile", "-C", "build"], Some(directory))
            && elevated_in("meson", &["install", "-C", "build"], directory)
    } else if directory.join("CMakeLists.txt").is_file() {
        run_visibly("cmake", &["-B", "build"], Some(directory))
            && run_visibly("cmake", &["--build", "build"], Some(directory))
            && elevated_in("cmake", &["--install", "build"], directory)
    } else if directory.join("configure").is_file()
        || directory.join("configure.ac").is_file()
        || directory.join("autogen.sh").is_file()
    {
        let autogen = directory.join("autogen.sh");
        let prepared = !autogen.is_file()
            || (process::is_executable(&autogen)
                && run_visibly("./autogen.sh", &[], Some(directory)));
        prepared
            && run_visibly("./configure", &[], Some(directory))
            && run_visibly("make", &[], Some(directory))
            && elevated_in("make", &["install"], directory)
    } else if ["Makefile", "makefile", "GNUmakefile"]
        .iter()
        .any(|name| directory.join(name).is_file())
    {
        run_visibly("make", &[], Some(directory)) && elevated_in("make", &["install"], directory)
    } else {
        output::err(&format!(
            "No recognized build system for {package}; skipping source build."
        ));
        false
    };

    if !built {
        output::err(&format!("Manual build for {package} failed."));
    }
    built
}

// A repository entry this project used to add. Left behind, it fails every later pacman call,
// so it is removed before anything is installed.
fn remove_stale_caelestia_bin_repository() {
    let conf = Path::new("/etc/pacman.conf");
    let Ok(text) = std::fs::read_to_string(conf) else {
        return;
    };
    if !text.lines().any(|line| line.trim() == "[caelestia-bin]") {
        return;
    }

    output::info("Removing stale caelestia-bin repo entry from pacman.conf...");
    let _ = privileges::elevated(
        "sed",
        &["-i", "/^\\[caelestia-bin\\]/,/^$/d", "/etc/pacman.conf"],
        None,
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_source_build_repository_is_named_by_a_repository() {
        for (package, url) in SOURCE_BUILD_REPOS {
            assert!(url.starts_with("https://"), "{package}: {url}");
            assert!(!package.is_empty());
        }
    }
}
