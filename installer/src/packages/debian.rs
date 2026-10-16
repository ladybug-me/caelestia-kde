use std::path::PathBuf;

use crate::copy;
use crate::output;
use crate::paths;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;
use crate::toolchain;

use super::{
    Failures, Group, elevated, elevated_in, grouped, install_custom_fonts,
    install_darkly_gtk_theme, install_starship, link_qdbus6, link_sassc, matugen_helper,
    retry_individually, run_visibly, run_xdg_user_dirs, wanted, with_clone,
};

// gpu-screen-recorder has no apt package, so the fallback below clones upstream and runs its
// ./install.sh as root. That is only acceptable against a pinned revision: never point this
// at master. To update, list the upstream tags with
//   git ls-remote --tags https://repo.dec05eba.com/gpu-screen-recorder
// bump the ref, and test the build before shipping it.
const GPU_SCREEN_RECORDER_REF: &str = "6.1.3";

// The lists are data: whitespace-separated, so a package does not take a line of
// its own, and read back through `names`.
pub(super) const CORE: &str = "
    cmake ninja-build ccache g++ build-essential qt6-l10n-tools qt6-tools-dev
    extra-cmake-modules wl-clipboard cliphist inotify-tools wireplumber trash-cli jq yq libc6
    libaubio-dev aubio-tools lm-sensors libsensors-dev libpipewire-0.3-dev pipewire libfftw3-dev
    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qml6-module-qtquick qt6-wayland
    qt6-wayland-dev qt6-svg-dev qt6-shadertools-dev qt6-multimedia-dev qt6-5compat-dev
    qt6-image-formats-plugins libkf6globalaccel-dev libkf6windowsystem-dev libkf6guiaddons-dev
    libkf6coreaddons-dev kwin-dev libkf6pulseaudioqt-dev libpulse-dev libkf6config-dev
    libkf6networkmanagerqt-dev libkpipewire-dev libepoxy-dev libdrm-dev ffmpeg libavcodec-dev
    libavformat-dev libavutil-dev libswscale-dev libqalculate-dev qalc libvulkan-dev
    libsecret-1-dev ksshaskpass libx11-dev libsecret-tools libprotobuf-dev protobuf-compiler
    libssl-dev avahi-daemon
";

pub(super) const SHELL: &str = "
    foot eza fastfetch btop bash pciutils
";

pub(super) const THEMES: &str = "
    adw-gtk3
";

pub(super) const UTILITIES: &str = "
    fuzzel swappy ddcutil network-manager imagemagick tesseract-ocr tesseract-ocr-eng
    kde-spectacle slurp grim brightnessctl power-profiles-daemon xdg-utils sassc python3-venv uv
    konsave
";

pub(super) const FALLBACK_CORE: &str = "
    libcava app2unit cliphist matugen
";

pub(super) const FALLBACK_SHELL: &str = "
    quickshell starship
";

pub(super) const FALLBACK_THEMES: &str = "
    adw-gtk3
";

pub(super) const FALLBACK_UTILS: &str = "
    gpu-screen-recorder cliphist wl-clip-persist satty uv konsave
";

pub fn run(context: &Context, group: Group) -> Result<(), Failure> {
    output::info("Installing Debian packages...");

    let mut packages = grouped(group, CORE, SHELL, THEMES, UTILITIES);
    let fallback_targets = grouped(
        group,
        FALLBACK_CORE,
        FALLBACK_SHELL,
        FALLBACK_THEMES,
        FALLBACK_UTILS,
    );

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

    let mut failures = Failures::default();
    install_batch(&packages, &fallback_targets, &mut failures);
    install_fallback_targets(context, &fallback_targets, &mut failures);

    if group.covers(Group::Themes) {
        install_custom_fonts(true, &mut failures);

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
    output::ok("Debian package installation complete.");
    Ok(())
}

// The fallback targets are set aside from the batch: each one is asked for on its own,
// because a target apt does not carry at all would otherwise fail the whole transaction.
fn install_batch(packages: &[&str], fallback_targets: &[&str], failures: &mut Failures) {
    let batch: Vec<&str> = packages
        .iter()
        .copied()
        .filter(|package| !fallback_targets.contains(package))
        .collect();

    let missing = pkg::missing(&batch);
    if missing.is_empty() {
        output::info("All standard Debian packages already installed.");
        return;
    }

    output::info("Updating apt package index...");
    let _ = privileges::elevated("apt-get", &["update"], None);

    output::info(&format!(
        "Batch installing missing Debian packages: {}",
        missing.join(" ")
    ));
    let mut args: Vec<&str> = vec!["install", "-y", "--no-install-recommends"];
    args.extend(missing.iter().copied());
    if elevated("apt-get", &args) {
        return;
    }

    output::info("Batch install had failures. Retrying standard packages individually...");
    retry_individually(
        &missing,
        "apt",
        |package| {
            elevated(
                "apt-get",
                &["install", "-y", "--no-install-recommends", package],
            )
        },
        failures,
    );
}

fn install_fallback_targets(context: &Context, targets: &[&str], failures: &mut Failures) {
    for package in targets {
        if pkg::present(package) || process::available(package) {
            continue;
        }
        // The prebuilt SDK provides libcava without being a package, and asking apt for it
        // just fails.
        if *package == "libcava" && toolchain::cava_sdk_installed() {
            continue;
        }
        if elevated("apt-get", &["install", "-y", package]) {
            continue;
        }

        output::info(&format!(
            "apt failed or package missing for {package}. Attempting manual fallback..."
        ));
        if !fallback(context, package) {
            failures.add(package);
        }
    }
}

fn fallback(context: &Context, package: &str) -> bool {
    match package {
        "quickshell" => {
            output::info("Attempting to install quickshell from PPA...");
            add_ppa("ppa:avengemedia/danklinux");
            if elevated("apt-get", &["install", "-y", "quickshell"]) {
                true
            } else {
                output::err("Failed to install quickshell from PPA.");
                false
            }
        }
        "libcava" => {
            if toolchain::cava_sdk_installed() || toolchain::install_cava_sdk() {
                output::info("CAVA SDK ready.");
                return true;
            }

            output::info("Attempting to install cava from PPA...");
            add_ppa("ppa:hsheth2/ppa");
            if elevated("apt-get", &["install", "-y", "cava"]) {
                output::info("cava installed via PPA.");
                true
            } else {
                output::err("Failed to install libcava SDK / cava.");
                false
            }
        }
        "app2unit" => {
            let _ = privileges::elevated("apt-get", &["install", "-y", "make", "scdoc"], None);
            with_clone(
                "https://github.com/Vladimir-csp/app2unit",
                &[],
                |directory| {
                    let built = elevated_in("make", &["install"], directory)
                        || elevated_in("make", &["install-bin"], directory);
                    if !built {
                        output::err(&format!("Manual build for {package} failed."));
                    }
                    built
                },
            )
        }
        "gpu-screen-recorder" => {
            let _ = privileges::elevated(
                "apt-get",
                &[
                    "install",
                    "-y",
                    "build-essential",
                    "git",
                    "ffmpeg",
                    "meson",
                    "libxi-dev",
                    "libdrm-dev",
                    "libavcodec-dev",
                    "libavformat-dev",
                    "libx11-dev",
                    "libxcomposite-dev",
                    "libxdamage-dev",
                    "libxrender-dev",
                    "libxrandr-dev",
                    "libpulse-dev",
                    "libva-dev",
                    "libcap-dev",
                    "libdbus-1-dev",
                    "libpipewire-0.3-dev",
                    "libavfilter-dev",
                    "libvulkan-dev",
                ],
                None,
            );
            output::info(&format!(
                "Building gpu-screen-recorder {GPU_SCREEN_RECORDER_REF} from repo.dec05eba.com (pinned ref; its ./install.sh runs as root)."
            ));
            with_clone(
                "https://repo.dec05eba.com/gpu-screen-recorder",
                &["--branch", GPU_SCREEN_RECORDER_REF],
                |directory| {
                    let built = elevated_in("./install.sh", &[], directory);
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
        "cliphist" => install_cliphist(package),
        "wl-clip-persist" => {
            let _ = privileges::elevated(
                "apt-get",
                &[
                    "install",
                    "-y",
                    "build-essential",
                    "curl",
                    "git",
                    "libwayland-dev",
                ],
                None,
            );

            if !rust_is_recent() {
                output::info("Modern Rust toolchain (>= 1.85) required. Installing via rustup...");
                install_rustup();
            }

            let Some(cargo) = cargo_path() else {
                output::err(&format!("Cargo not available to build {package}."));
                return false;
            };
            let cargo = cargo.to_string_lossy().to_string();

            with_clone(
                "https://github.com/Linus789/wl-clip-persist",
                &[],
                |directory| {
                    let built = run_visibly(&cargo, &["build", "--release"], Some(directory))
                        && elevated_in(
                            "cp",
                            &["target/release/wl-clip-persist", "/usr/local/bin/"],
                            directory,
                        );
                    if !built {
                        output::err(&format!("cargo build {package} failed."));
                    }
                    built
                },
            )
        }
        "satty" => install_satty(package),
        "uv" => {
            if install_uv() {
                output::info("uv installed successfully.");
                true
            } else {
                output::err("Failed to install uv.");
                false
            }
        }
        "konsave" => {
            let Some(uv) = uv_path() else {
                output::err(&format!(
                    "uv is required to install {package}, but it is not available."
                ));
                return false;
            };
            let uv = uv.to_string_lossy().to_string();

            if run_visibly(&uv, &["tool", "install", "konsave"], None) {
                true
            } else {
                output::err(&format!("uv tool install {package} failed."));
                false
            }
        }
        "adw-gtk3" => install_adw_gtk3(package),
        // The matugen ladder is shared with the session's own startup task, which is why the
        // installer asks that helper rather than carrying a second copy of it.
        "matugen" => matugen_helper(&context.bundle, "install_matugen_debian"),
        _ => false,
    }
}

fn add_ppa(repository: &str) -> bool {
    let _ = privileges::elevated(
        "apt-get",
        &["install", "-y", "software-properties-common"],
        None,
    );
    let added = elevated("add-apt-repository", &["-y", repository]);
    let _ = privileges::elevated("apt-get", &["update"], None);
    added
}

// The release notes are quoted, so every URL in them ends at the next quote and the asset for
// this machine's architecture is the one whose name ends with it.
fn install_cliphist(package: &str) -> bool {
    output::info("Downloading the cliphist binary from GitHub releases...");

    let architecture = match process::capture("uname", &["-m"])
        .unwrap_or_default()
        .trim()
    {
        "aarch64" => "linux-arm64",
        "armv7l" => "linux-arm",
        "i386" | "i686" => "linux-386",
        _ => "linux-amd64",
    };

    let release = process::capture(
        "curl",
        &[
            "-fsSL",
            "https://api.github.com/repos/sentriz/cliphist/releases/latest",
        ],
    );
    let url = release.as_deref().and_then(|release| {
        release
            .split('"')
            .find(|part| part.starts_with("https://") && part.ends_with(architecture))
            .map(str::to_string)
    });

    let Some(url) = url else {
        output::err("Could not resolve the cliphist release URL.");
        return false;
    };

    let Some(work) = TempDir::new("caelestia-cliphist") else {
        return false;
    };
    let binary = work.path().join("cliphist");
    if !crate::download::fetch(&url, &binary, &[]) {
        output::err("Failed to download cliphist.");
        return false;
    }

    let binary = binary.to_string_lossy().to_string();
    if !elevated(
        "install",
        &["-m", "755", &binary, "/usr/local/bin/cliphist"],
    ) {
        output::err(&format!("Failed to install {package}."));
        return false;
    }

    output::info("cliphist installed successfully to /usr/local/bin.");
    true
}

fn install_satty(package: &str) -> bool {
    if cargo_binstall_path().is_none() {
        output::info("Installing cargo-binstall...");
        let Some(work) = TempDir::new("caelestia-binstall") else {
            return false;
        };
        let script = work.path().join("install-cargo-binstall.sh");
        let url = "https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh";
        if crate::download::fetch(url, &script, &[]) {
            let script = script.to_string_lossy().to_string();
            let _ = run_visibly("bash", &[&script], None);
        }
        ensure_cargo_path_in_start_files();
    }

    let Some(binstall) = cargo_binstall_path() else {
        output::err(&format!(
            "cargo-binstall not available to install {package}."
        ));
        return false;
    };
    let binstall = binstall.to_string_lossy().to_string();

    if run_visibly(&binstall, &["-y", "satty"], None) {
        return true;
    }

    output::info("Normal cargo-binstall failed. Trying with sudo...");
    if elevated(&binstall, &["-y", "satty"]) {
        return true;
    }

    output::err(&format!("sudo cargo-binstall {package} failed."));
    false
}

fn install_uv() -> bool {
    let Some(work) = TempDir::new("caelestia-uv") else {
        return false;
    };
    let script = work.path().join("install-uv.sh");
    if !crate::download::fetch("https://astral.sh/uv/install.sh", &script, &[]) {
        return false;
    }

    let script = script.to_string_lossy().to_string();
    run_visibly("sh", &[&script], None)
}

fn install_adw_gtk3(package: &str) -> bool {
    let Some(work) = TempDir::new("caelestia-adw-gtk3") else {
        return false;
    };
    let archive = work.path().join("adw-gtk3.tar.xz");
    let url = "https://github.com/lassekongo83/adw-gtk3/releases/download/v5.3/adw-gtk3v5.3.tar.xz";

    output::info("Downloading the adw-gtk3 theme...");
    if !crate::download::fetch(url, &archive, &[]) {
        output::err("Failed to download the adw-gtk3 theme.");
        return false;
    }

    let archive = archive.to_string_lossy().to_string();
    let unpacked = work.path().to_string_lossy().to_string();
    if !run_visibly("tar", &["-xJf", &archive, "-C", &unpacked], None) {
        output::err("Failed to unpack the adw-gtk3 theme.");
        return false;
    }

    let themes = paths::data_home().join("themes");
    if std::fs::create_dir_all(&themes).is_err() {
        output::err(&format!("Could not create {}.", themes.display()));
        return false;
    }

    let copied = ["adw-gtk3", "adw-gtk3-dark"]
        .iter()
        .all(|name| copy::tree(&work.path().join(name), &themes.join(name)).is_ok());
    if !copied {
        output::err(&format!("Failed to install {package}."));
        return false;
    }
    true
}

// Darkly publishes a prebuilt package per distribution and release, so this machine's own
// identity is what picks the one to ask for.
fn install_darkly(failures: &mut Failures) {
    if !process::available("darkly") && !pkg::present("darkly") {
        match darkly_deb_asset_url() {
            Some(url) => {
                let Some(work) = TempDir::new("caelestia-darkly") else {
                    return;
                };
                let package = work.path().join("darkly.deb");

                output::info("Downloading the Darkly .deb from GitHub releases...");
                if !crate::download::fetch(&url, &package, &[]) {
                    output::err("Failed to download the Darkly .deb from GitHub releases.");
                    failures.add("darkly");
                    return;
                }

                let package = package.to_string_lossy().to_string();
                let installed = elevated("apt-get", &["install", "-y", &package])
                    || elevated("dpkg", &["-i", &package]);
                if !installed {
                    output::err("Failed to install the Darkly .deb.");
                    failures.add("darkly");
                }
            }
            None => {
                output::err("No prebuilt Darkly .deb found for this distro.");
                failures.add("darkly");
            }
        }
    }

    if !super::darkly_gtk_installed() {
        output::info("Installing Darkly GTK theme...");
        let _ = privileges::elevated("apt-get", &["install", "-y", "sassc"], None);
        if !install_darkly_gtk_theme() {
            failures.add("darkly-gtk");
        }
    }
}

// Upstream tags its packages per distribution and version, so the ones this machine could
// take are named in order and the first that exists is the one.
fn darkly_deb_asset_url() -> Option<String> {
    let released = process::capture(
        "curl",
        &[
            "-fsSL",
            "https://api.github.com/repos/Bali10050/Darkly/releases/latest",
        ],
    )?;

    let id = os_release_field("ID");
    let version = os_release_field("VERSION_ID");

    let needles: Vec<String> = match id.as_str() {
        "neon" | "kdeneon" => vec!["kdeneon".to_string()],
        "ubuntu" | "kubuntu" | "linuxmint" | "pop" => {
            vec![format!("kubuntu-{version}"), "kubuntu".to_string()]
        }
        "debian" => {
            if version.starts_with("14") || version.starts_with("15") {
                ["debian14", "debian13", "debian"]
                    .map(str::to_string)
                    .to_vec()
            } else {
                ["debian13", "debian14", "debian"]
                    .map(str::to_string)
                    .to_vec()
            }
        }
        _ => ["debian13", "debian14", "kubuntu", "kdeneon", "debian"]
            .map(str::to_string)
            .to_vec(),
    };

    let urls: Vec<&str> = released
        .split('"')
        .filter(|part| part.starts_with("https://") && part.ends_with("_amd64.deb"))
        .collect();

    for needle in needles {
        if let Some(url) = urls.iter().find(|url| url.contains(&needle)) {
            return Some(url.to_string());
        }
    }
    None
}

fn os_release_field(name: &str) -> String {
    let path =
        std::env::var("CAELESTIA_OS_RELEASE").unwrap_or_else(|_| "/etc/os-release".to_string());
    let Ok(text) = std::fs::read_to_string(&path) else {
        return String::new();
    };

    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() == name {
            return value.trim().trim_matches(['"', '\'']).to_lowercase();
        }
    }
    String::new()
}

fn install_rustup() {
    let Some(work) = TempDir::new("caelestia-rustup") else {
        return;
    };
    let script = work.path().join("install-rustup.sh");
    if !crate::download::fetch("https://sh.rustup.rs", &script, &[]) {
        return;
    }

    let script = script.to_string_lossy().to_string();
    let _ = run_visibly(
        "sh",
        &[
            &script,
            "-y",
            "--default-toolchain",
            "stable",
            "--profile",
            "minimal",
        ],
        None,
    );
}

// A tool that installs into ~/.cargo/bin is only on PATH for a session the shells have been
// told about, which is what the startup files are for.
fn ensure_cargo_path_in_start_files() {
    let home = paths::home();
    let line = "export PATH=\"$HOME/.cargo/bin:$PATH\"";

    for name in [".bashrc", ".zshrc", ".profile"] {
        let file = home.join(name);
        let existing = std::fs::read_to_string(&file).unwrap_or_default();
        if existing.lines().any(|text| text.trim() == line) {
            continue;
        }
        let _ = std::fs::write(&file, format!("{existing}{line}\n"));
    }

    if process::available("fish") {
        let _ = process::succeeds("fish", &["-c", "fish_add_path ~/.cargo/bin"], None);
    }
}

fn rust_is_recent() -> bool {
    let Some(version) = process::capture("rustc", &["--version"]) else {
        return false;
    };
    let Some(number) = version.split_whitespace().nth(1) else {
        return false;
    };
    number
        .split('.')
        .nth(1)
        .and_then(|minor| minor.parse::<u32>().ok())
        .is_some_and(|minor| minor >= 85)
}

// The tools below install into ~/.cargo/bin or ~/.local/bin, which a session that predates
// them does not have on PATH: they are asked for by that path first.
fn cargo_path() -> Option<PathBuf> {
    binary_in(&[".cargo/bin/cargo"], "cargo")
}

fn cargo_binstall_path() -> Option<PathBuf> {
    binary_in(&[".cargo/bin/cargo-binstall"], "cargo-binstall")
}

fn uv_path() -> Option<PathBuf> {
    binary_in(&[".local/bin/uv", ".cargo/bin/uv"], "uv")
}

fn binary_in(candidates: &[&str], name: &str) -> Option<PathBuf> {
    let home = paths::home();
    for candidate in candidates {
        let path = home.join(candidate);
        if process::is_executable(&path) {
            return Some(path);
        }
    }
    process::locate(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_fallback_target_is_handled_by_the_fallback_ladder() {
        let targets = [
            FALLBACK_CORE,
            FALLBACK_SHELL,
            FALLBACK_THEMES,
            FALLBACK_UTILS,
        ];
        for package in targets.into_iter().flat_map(crate::packages::names) {
            let handled = matches!(
                package,
                "quickshell"
                    | "starship"
                    | "libcava"
                    | "app2unit"
                    | "gpu-screen-recorder"
                    | "cliphist"
                    | "wl-clip-persist"
                    | "satty"
                    | "adw-gtk3"
                    | "uv"
                    | "konsave"
                    | "matugen"
            );
            assert!(handled, "{package} is asked for with no fallback behind it");
        }
    }

    #[test]
    fn the_pinned_revision_is_a_tag_and_not_a_branch() {
        assert!(!GPU_SCREEN_RECORDER_REF.is_empty());
        assert!(
            !matches!(GPU_SCREEN_RECORDER_REF, "master" | "main" | "HEAD"),
            "{GPU_SCREEN_RECORDER_REF} is not a pinned revision"
        );
        assert!(GPU_SCREEN_RECORDER_REF.starts_with(char::is_numeric));
    }
}
