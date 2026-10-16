use crate::output;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::toolchain;

use super::{
    Failures, Group, elevated, elevated_in, grouped, install_custom_fonts,
    install_darkly_gtk_theme, install_starship, link_qdbus6, link_sassc, matugen_helper, names,
    retry_individually, run_visibly, run_xdg_user_dirs, wanted, with_clone,
};

// The lists are data: whitespace-separated, so a package does not take a line of
// its own, and read back through `names`.
pub(super) const CORE: &str = "
    cmake ninja-build ccache qt6-qttools-devel extra-cmake-modules libgcc glibc wl-clipboard
    cliphist wl-clip-persist inotify-tools wireplumber trash-cli jq aubio aubio-devel lm_sensors
    lm_sensors-devel pipewire-devel pulseaudio-qt-qt6-devel pulseaudio-libs-devel fftw-devel
    qt6-qtbase qt6-qtbase-private-devel qt6-qtdeclarative qt6-qtdeclarative-devel qt6-qtwayland
    qt6-qtwayland-devel qt6-qtsvg qt6-qtsvg-devel qt6-qtshadertools-devel qt6-qtmultimedia-devel
    qt6-qt5compat-devel qt6-qtimageformats kf6-kglobalaccel-devel kf6-kwindowsystem-devel
    kf6-kguiaddons-devel kf6-kcoreaddons-devel kwin-devel kf6-kconfig-devel
    kf6-networkmanager-qt-devel kpipewire kpipewire-devel libepoxy-devel libdrm-devel
    libqalculate libqalculate-devel libsecret vulkan-headers ksshaskpass libX11-devel
    protobuf-devel protobuf-compiler openssl-devel avahi
";

pub(super) const SHELL: &str = "
    foot eza fastfetch starship btop bash pciutils
";

pub(super) const THEMES: &str = "
    adw-gtk3-theme google-rubik-fonts google-noto-sans-fonts google-noto-sans-cjk-ttc-fonts
    google-noto-emoji-fonts
";

pub(super) const UTILITIES: &str = "
    fuzzel swappy ddcutil NetworkManager ImageMagick tesseract tesseract-langpack-eng spectacle
    gpu-screen-recorder slurp grim brightnessctl power-profiles-daemon xdg-utils sassc bat
    ripgrep xdg-user-dirs
";

pub(super) const COPR_CORE: &str = "
    app2unit libcava
";

pub(super) const COPR_SHELL: &str = "
    quickshell-git matugen
";

pub(super) const COPR_ALL: &str = "
    quickshell-git gpu-screen-recorder app2unit starship libcava wl-clip-persist matugen
";

pub fn run(context: &Context, group: Group) -> Result<(), Failure> {
    output::info("Installing Fedora packages...");

    let mut packages = grouped(group, CORE, SHELL, THEMES, UTILITIES);
    let copr_packages = match group {
        Group::Core => names(COPR_CORE),
        Group::Shell => names(COPR_SHELL),
        // The utils group has no COPR packages of its own: what it asks for is either carried
        // by the repositories or named by another group's list.
        Group::Themes | Group::Utils => Vec::new(),
        Group::All => names(COPR_ALL),
    };

    // A COPR package is one the repositories do not carry yet, so dnf is asked for it with
    // the repository it lives in rather than as part of the batch.
    if group.covers(Group::Core) {
        packages.extend(names(COPR_CORE));
    }
    if group.covers(Group::Shell) {
        packages.extend(names(COPR_SHELL));
    }

    output::info(&format!("Installing packages (group: {})...", group.name()));

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

    enable_h264_codecs();
    if group.covers(Group::Core) {
        packages.push("ffmpeg");
    }

    let mut failures = Failures::default();
    install_batch(&packages, &copr_packages, group, &mut failures);
    install_copr_packages(context, &packages, &copr_packages, &mut failures);

    if group.covers(Group::Themes) {
        // No Fedora package carries these in the shapes the shell asks for, so they come
        // from upstream directly.
        install_custom_fonts(false, &mut failures);

        let darkly = wanted(
            context,
            "INSTALL_DARKLY",
            "Skipping Darkly package installation by user choice.",
        );
        if darkly {
            install_darkly(&mut failures);
        }
    }

    run_xdg_user_dirs();

    if group.covers(Group::Shell) {
        link_sassc();
        link_qdbus6();
    }

    failures.report();
    output::ok("Fedora package installation complete.");
    Ok(())
}

// Fedora ships ffmpeg without the H264 codecs, and the shell records video: RPM Fusion is
// what carries them. Enabling it swaps the free build out for the full one.
fn enable_h264_codecs() {
    if process::succeeds("rpm", &["-q", "rpmfusion-free-release"], None) {
        return;
    }

    output::info("Enabling RPM Fusion for H264 hardware codecs...");
    let release = process::capture("rpm", &["-E", "%fedora"]).unwrap_or_default();
    let release = release.trim();

    let urls = [
        format!(
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-{release}.noarch.rpm"
        ),
        format!(
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-{release}.noarch.rpm"
        ),
    ];
    let _ = privileges::elevated("dnf", &["install", "-y", &urls[0], &urls[1]], None);
    let _ = privileges::elevated(
        "dnf",
        &["swap", "-y", "ffmpeg-free", "ffmpeg", "--allowerasing"],
        None,
    );
}

fn install_batch(packages: &[&str], copr_packages: &[&str], group: Group, failures: &mut Failures) {
    let batch: Vec<&str> = packages
        .iter()
        .copied()
        .filter(|package| !copr_packages.contains(package))
        .collect();

    let missing = pkg::missing(&batch);
    if missing.is_empty() {
        output::info(&format!(
            "All standard packages for group {} are already installed.",
            group.name()
        ));
        return;
    }

    output::info("Installing packages via dnf (batch mode)...");
    let mut args: Vec<&str> = vec!["install", "-y"];
    args.extend(missing.iter().copied());
    if elevated("dnf", &args) {
        return;
    }

    output::info("Batch install had failures. Retrying standard packages individually...");
    retry_individually(
        &missing,
        "dnf",
        |package| elevated("dnf", &["install", "-y", package]),
        failures,
    );
}

fn install_copr_packages(
    context: &Context,
    packages: &[&str],
    copr_packages: &[&str],
    failures: &mut Failures,
) {
    for package in copr_packages {
        if !packages.contains(package) {
            continue;
        }

        // libcava is the other target no package manager can answer for: the prebuilt SDK
        // provides it without being a package, and asking dnf for it just fails.
        if *package == "libcava" && toolchain::cava_sdk_installed() {
            continue;
        }
        if pkg::present(package) || process::available(package) {
            continue;
        }

        if elevated("dnf", &["install", "-y", package]) {
            continue;
        }

        output::info(&format!(
            "dnf failed to install {package}. Attempting copr fallback..."
        ));
        if copr_fallback(context, package) {
            continue;
        }

        output::info(&format!(
            "Copr fallback failed or not defined for {package}. Attempting manual build..."
        ));
        if !manual_fallback(package) {
            failures.add(package);
        }
    }
}

fn copr_fallback(context: &Context, package: &str) -> bool {
    let enable = |repository: &str| elevated("dnf", &["copr", "enable", "-y", repository]);

    match package {
        "quickshell-git" | "quickshell" => {
            enable("errornointernet/quickshell")
                && elevated("dnf", &["install", "-y", "quickshell-git"])
        }
        "matugen" => matugen_helper(&context.bundle, "install_matugen_fedora"),
        // Install the package that was asked for: the COPR also ships -ui, and reporting
        // success for that would leave gpu-screen-recorder itself missing.
        "gpu-screen-recorder" => {
            enable("brycensranch/gpu-screen-recorder-git")
                && elevated("dnf", &["install", "-y", "gpu-screen-recorder"])
        }
        "app2unit" => {
            enable("celestelove/app2unit") && elevated("dnf", &["install", "-y", "app2unit"])
        }
        "starship" => enable("atim/starship") && elevated("dnf", &["install", "-y", "starship"]),
        "libcava" => {
            if toolchain::cava_sdk_installed() || toolchain::install_cava_sdk() {
                output::info("CAVA SDK ready.");
                return true;
            }
            enable("celestelove/libcava") && elevated("dnf", &["install", "-y", "libcava-devel"])
        }
        "wl-clip-persist" => {
            enable("leloubil/wl-clip-persist")
                && elevated("dnf", &["install", "-y", "wl-clip-persist"])
        }
        _ => false,
    }
}

fn manual_fallback(package: &str) -> bool {
    match package {
        "app2unit" => {
            let _ = privileges::elevated("dnf", &["install", "-y", "make"], None);
            with_clone(
                "https://github.com/Vladimir-csp/app2unit",
                &[],
                |directory| {
                    let built = elevated_in("make", &["install"], directory);
                    if !built {
                        output::err(&format!("Manual build for {package} failed."));
                    }
                    built
                },
            )
        }
        "gpu-screen-recorder" => {
            let _ = privileges::elevated(
                "dnf",
                &[
                    "install",
                    "-y",
                    "meson",
                    "ninja-build",
                    "pkgconf",
                    "libXcomposite-devel",
                    "libXrandr-devel",
                    "libXfixes-devel",
                    "libdrm-devel",
                    "wayland-devel",
                    "pipewire-devel",
                    "libcap-devel",
                    "ffmpeg-devel",
                ],
                None,
            );
            with_clone(
                "https://git.dec05eba.com/gpu-screen-recorder",
                &[],
                |directory| {
                    let built = run_visibly("meson", &["setup", "build"], Some(directory))
                        && run_visibly("ninja", &["-C", "build"], Some(directory))
                        && elevated_in("meson", &["install", "-C", "build"], directory);
                    if !built {
                        output::err(&format!("Manual build for {package} failed."));
                    }
                    built
                },
            )
        }
        "starship" => {
            if install_starship() {
                output::info("starship installed successfully.");
                true
            } else {
                output::err(&format!("Manual build for {package} failed."));
                false
            }
        }
        _ => {
            output::err(&format!("No manual fallback defined for {package}."));
            false
        }
    }
}

// Darkly is not in Fedora's repositories, so it is asked for in the order that keeps the
// user's system manager aware of it: the package, then the author's COPR, and only then the
// prebuilt RPM, which nothing will update.
fn install_darkly(failures: &mut Failures) {
    if !process::available("darkly") && !pkg::present("darkly") {
        install_darkly_package(failures);
    }

    if !super::darkly_gtk_installed() {
        output::info("Installing Darkly GTK theme...");
        let _ = privileges::elevated("dnf", &["install", "-y", "sassc"], None);
        if !install_darkly_gtk_theme() {
            failures.add("darkly-gtk");
        }
    }
}

fn install_darkly_package(failures: &mut Failures) {
    if elevated("dnf", &["install", "-y", "darkly"]) {
        return;
    }

    output::info("Enabling Darkly COPR (deltacopy/darkly)...");
    let from_copr = elevated("dnf", &["copr", "enable", "-y", "deltacopy/darkly"])
        && elevated("dnf", &["install", "-y", "darkly"]);
    if from_copr {
        return;
    }

    output::info("COPR install failed; falling back to prebuilt RPM from GitHub releases...");
    match darkly_rpm_asset_url() {
        Some(url) => {
            if !elevated("dnf", &["install", "-y", &url]) {
                output::err("Failed to install the Darkly RPM.");
                failures.add("darkly");
            }
        }
        None => {
            output::err("No prebuilt Darkly RPM found for this Fedora version.");
            failures.add("darkly");
        }
    }
}

// The release notes are quoted, so every URL in them ends at the next quote: the build for
// this Fedora release is the one named after it, and any other Fedora build after that.
fn darkly_rpm_asset_url() -> Option<String> {
    let release = process::capture(
        "curl",
        &[
            "-fsSL",
            "https://api.github.com/repos/Bali10050/Darkly/releases/latest",
        ],
    )?;

    let urls: Vec<&str> = release
        .split('"')
        .filter(|part| part.starts_with("https://"))
        .collect();

    let release = process::capture("rpm", &["-E", "%fedora"]).unwrap_or_default();
    let release = release.trim();
    if !release.is_empty() {
        let wanted = format!(".fc{release}.x86_64.rpm");
        if let Some(url) = urls.iter().find(|url| url.ends_with(&wanted)) {
            return Some(url.to_string());
        }
    }

    urls.into_iter()
        .find(|url| is_fedora_rpm(url))
        .map(str::to_string)
}

fn is_fedora_rpm(url: &str) -> bool {
    let Some(name) = url.rsplit('/').next() else {
        return false;
    };
    let Some(stem) = name.strip_suffix(".x86_64.rpm") else {
        return false;
    };
    stem.rsplit('.').next().is_some_and(|tag| {
        tag.strip_prefix("fc")
            .is_some_and(|digits| !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_all_run_treats_every_copr_package_as_one() {
        for package in [COPR_CORE, COPR_SHELL].into_iter().flat_map(names) {
            assert!(
                names(COPR_ALL).contains(&package),
                "{package} is a COPR package for one group but not for all of them"
            );
        }

        for package in names(COPR_ALL) {
            let asked_for = [CORE, SHELL, THEMES, UTILITIES, COPR_CORE, COPR_SHELL]
                .into_iter()
                .any(|list| names(list).contains(&package));
            assert!(
                asked_for,
                "{package} comes from a COPR but is never asked for"
            );
        }
    }

    #[test]
    fn a_fedora_rpm_is_recognised_by_the_tag_in_its_file_name() {
        assert!(is_fedora_rpm(
            "https://example.invalid/download/darkly-1.2-1.fc43.x86_64.rpm"
        ));
        assert!(!is_fedora_rpm(
            "https://example.invalid/download/darkly-1.2-1.fc43.aarch64.rpm"
        ));
        assert!(!is_fedora_rpm(
            "https://example.invalid/download/darkly-1.2-1.x86_64.rpm"
        ));
        assert!(!is_fedora_rpm(
            "https://example.invalid/download/darkly-1.2-1.fcx.x86_64.rpm"
        ));
        assert!(!is_fedora_rpm("https://example.invalid/releases/tag/v1.2"));
    }
}
