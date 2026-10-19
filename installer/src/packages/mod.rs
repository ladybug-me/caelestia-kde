use std::path::Path;

use crate::distro::{self, Distro};
use crate::output;
use crate::paths;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

pub mod arch;
pub mod debian;
pub mod fedora;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Group {
    Core,
    Shell,
    Themes,
    Utils,
    All,
}

impl Group {
    pub fn name(self) -> &'static str {
        match self {
            Group::Core => "core",
            Group::Shell => "shell",
            Group::Themes => "themes",
            Group::Utils => "utils",
            Group::All => "all",
        }
    }

    pub fn from_env() -> Self {
        match std::env::var("PACKAGE_GROUP").unwrap_or_default().trim() {
            "core" => Group::Core,
            "shell" => Group::Shell,
            "themes" => Group::Themes,
            "utils" => Group::Utils,
            _ => Group::All,
        }
    }

    pub fn covers(self, one: Group) -> bool {
        self == Group::All || self == one
    }
}

pub fn all(context: &Context) -> Result<(), Failure> {
    let group = Group::from_env();
    let family = distro::detect();

    match family {
        Distro::Arch => arch::run(context, group),
        Distro::Fedora => fedora::run(context, group),
        Distro::Debian => debian::run(context, group),
        Distro::Unknown => Err(format!(
            "No package list for '{}' (expected arch, fedora or debian)",
            family.name()
        )
        .into()),
    }
}

pub fn tooling(context: &Context) -> Result<(), Failure> {
    println!();
    output::info("Ensuring Python tooling for konsave backups");
    ensure_python_tooling();

    println!();
    output::info("Ensuring the palette generator");
    if matugen_helper(&context.bundle, "ensure_matugen") {
        output::ok("Palette generator ready.");
    } else {
        output::warn(
            "matugen installation failed: wallpapers and schemes cannot generate a palette.",
        );
        output::info("  Arch:   sudo pacman -S matugen");
        output::info(
            "  Fedora: sudo dnf copr enable avengemedia/danklinux && sudo dnf install matugen",
        );
        output::info("  Debian: cargo install matugen (the installer builds it for you)");
    }

    println!();
    output::ok("Package installation complete.");
    Ok(())
}

fn ensure_python_tooling() {
    if process::available("python3")
        && process::succeeds("python3", &["-m", "pip", "--version"], None)
    {
        return;
    }

    let installed = match distro::detect() {
        Distro::Arch => elevated(
            "pacman",
            &["-S", "--needed", "--noconfirm", "python", "python-pip"],
        ),
        Distro::Fedora => elevated("dnf", &["install", "-y", "python3", "python3-pip"]),
        Distro::Debian => {
            let _ = privileges::elevated("apt-get", &["update"], None);
            elevated(
                "apt-get",
                &["install", "-y", "python3", "python3-pip", "python3-venv"],
            )
        }
        Distro::Unknown => {
            output::warn("Could not determine the distro for Python tooling installation.");
            return;
        }
    };

    if !installed {
        output::warn(
            "The Python tooling could not be installed; konsave backups will be unavailable.",
        );
    }
}

pub fn matugen_helper(bundle: &Path, function: &str) -> bool {
    let helper = bundle.join("scripts").join("lib").join("matugen.sh");
    if !helper.is_file() {
        output::warn(&format!("{} is missing.", helper.display()));
        return false;
    }

    let helper = helper.to_string_lossy().to_string();
    process::run_visible(
        "bash",
        &[
            "-c",
            "source \"$1\" && \"$2\"",
            "caelestia-matugen",
            &helper,
            function,
        ],
        None,
    ) == Some(0)
}

pub fn install_starship() -> bool {
    let Some(work) = TempDir::new("caelestia-starship") else {
        return false;
    };
    let script = work.path().join("install-starship.sh");
    if !crate::download::fetch("https://starship.rs/install.sh", &script, &[]) {
        return false;
    }

    let script = script.to_string_lossy().to_string();
    run_visibly("sh", &[&script, "-y"], None)
}

pub fn with_clone(url: &str, extra_clone_args: &[&str], build: impl FnOnce(&Path) -> bool) -> bool {
    let Some(work) = TempDir::new("caelestia-build") else {
        output::err(&format!("Could not create a directory to build {url} in."));
        return false;
    };

    let mut args: Vec<&str> = vec!["clone", "--depth", "1"];
    args.extend(extra_clone_args.iter().copied());
    args.push(url);
    args.push(".");

    if !run_visibly("git", &args, Some(work.path())) {
        output::err(&format!("Failed to clone {url}."));
        return false;
    }

    build(work.path())
}

pub fn run_visibly(program: &str, args: &[&str], directory: Option<&Path>) -> bool {
    process::run_visible(program, args, directory) == Some(0)
}

pub fn elevated(program: &str, args: &[&str]) -> bool {
    privileges::elevated(program, args, None) == Ok(0)
}

pub fn elevated_in(program: &str, args: &[&str], directory: &Path) -> bool {
    privileges::elevated(program, args, Some(directory)) == Ok(0)
}

pub fn names(list: &str) -> Vec<&str> {
    list.split_whitespace().collect()
}

/// What an uninstall offers to remove: the subset of the tables that is also a common desktop
/// tool, plus the names an older install could have used. The package names live here and nowhere
/// else; the uninstall asks for this list rather than keeping a copy of its own.
pub fn removable(distro: crate::distro::Distro) -> Vec<&'static str> {
    let (removable, legacy) = match distro {
        crate::distro::Distro::Arch => (arch::REMOVABLE, arch::LEGACY),
        crate::distro::Distro::Fedora => (fedora::REMOVABLE, fedora::LEGACY),
        crate::distro::Distro::Debian => (debian::REMOVABLE, debian::LEGACY),
        crate::distro::Distro::Unknown => return Vec::new(),
    };
    let mut offered = names(removable);
    offered.extend(names(legacy));
    offered.sort_unstable();
    offered.dedup();
    offered
}

pub fn grouped(
    group: Group,
    core: &'static str,
    shell: &'static str,
    themes: &'static str,
    utils: &'static str,
) -> Vec<&'static str> {
    match group {
        Group::Core => names(core),
        Group::Shell => names(shell),
        Group::Themes => names(themes),
        Group::Utils => names(utils),
        Group::All => [core, shell, themes, utils]
            .into_iter()
            .flat_map(names)
            .collect(),
    }
}

#[derive(Default)]
pub struct Failures {
    packages: Vec<String>,
}

impl Failures {
    pub fn add(&mut self, package: &str) {
        self.packages.push(package.to_string());
    }

    pub fn is_empty(&self) -> bool {
        self.packages.is_empty()
    }

    pub fn report(&self) {
        if self.is_empty() {
            return;
        }

        output::err("The following packages could not be installed:");
        for package in &self.packages {
            output::err(&format!("  - {package}"));
            pkg::record_failure(package);
        }
    }
}

pub fn retry_individually(
    missing: &[&str],
    manager: &str,
    attempt: impl Fn(&str) -> bool,
    failures: &mut Failures,
) {
    for package in missing {
        if pkg::present(package) {
            continue;
        }
        if !attempt(package) {
            output::err(&format!("{manager} failed to install {package}."));
            failures.add(package);
        }
    }
}

pub fn wanted(context: &Context, flag: &str, skip: &str) -> bool {
    if context.flag(flag, true) {
        return true;
    }
    output::info(skip);
    false
}

pub fn install_custom_fonts(with_rubik: bool, failures: &mut Failures) {
    output::info("Downloading and installing required custom fonts (parallel)...");

    let fonts = paths::data_home().join("fonts");
    if std::fs::create_dir_all(&fonts).is_err() {
        output::err(&format!("Could not create {}.", fonts.display()));
        failures.add("fonts");
        return;
    }

    let Some(scratch) = TempDir::new("caelestia-fonts") else {
        output::err("Could not create a directory to unpack the fonts in.");
        failures.add("fonts");
        return;
    };

    let material = fonts.join("MaterialSymbolsRounded.ttf");
    let rubik = fonts.join("Rubik-VariableFont_wght.ttf");
    let cascadia = scratch.path().join("CascadiaCode.zip");
    let jetbrains = scratch.path().join("JetBrainsMono.zip");

    let material_url = "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf";
    let rubik_url =
        "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik-VariableFont_wght.ttf";
    let nerds = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2";
    let cascadia_url = format!("{nerds}/CascadiaCode.zip");
    let jetbrains_url = format!("{nerds}/JetBrainsMono.zip");

    std::thread::scope(|scope| {
        scope.spawn(|| fetch(material_url, &material));
        scope.spawn(|| fetch(&cascadia_url, &cascadia));
        scope.spawn(|| fetch(&jetbrains_url, &jetbrains));
        if with_rubik {
            scope.spawn(|| fetch(rubik_url, &rubik));
        }
    });

    for (archive, name) in [
        (&cascadia, "CascadiaCode font"),
        (&jetbrains, "JetBrains Mono Nerd Font"),
    ] {
        if !unpack(archive, &fonts) {
            output::err(&format!("Failed to extract the {name}."));
            failures.add(name);
        }
    }

    if !material.is_file() {
        failures.add("Material Symbols font");
    }
    if with_rubik && !rubik.is_file() {
        failures.add("Rubik font");
    }

    let _ = process::succeeds("fc-cache", &["-f"], None);
}

fn fetch(url: &str, destination: &Path) {
    if !crate::download::fetch(url, destination, &[]) {
        output::err(&format!("Failed to download {url}."));
    }
}

fn unpack(archive: &Path, directory: &Path) -> bool {
    if !archive.is_file() {
        return false;
    }
    let archive = archive.to_string_lossy().to_string();
    let directory = directory.to_string_lossy().to_string();
    process::succeeds("unzip", &["-qo", &archive, "-d", &directory], None)
}

pub fn link_sassc() {
    if !process::available("sassc") || process::available("sass") {
        return;
    }
    let _ = privileges::elevated(
        "ln",
        &["-sf", "/usr/bin/sassc", "/usr/local/bin/sass"],
        None,
    );
}

pub fn link_qdbus6() {
    if process::available("qdbus6") {
        return;
    }

    let candidates = [
        process::locate("qdbus-qt6").map(|path| path.to_string_lossy().to_string()),
        Some("/usr/lib64/qt6/bin/qdbus".to_string()),
        Some("/usr/lib/qt6/bin/qdbus".to_string()),
    ];
    for source in candidates.into_iter().flatten() {
        if Path::new(&source).exists() {
            let _ = privileges::elevated("ln", &["-sf", &source, "/usr/local/bin/qdbus6"], None);
            return;
        }
    }
}

pub fn run_xdg_user_dirs() {
    if process::available("xdg-user-dirs-update") {
        let _ = process::succeeds("xdg-user-dirs-update", &[], None);
    }
}

pub fn darkly_gtk_installed() -> bool {
    let local = paths::data_home().join("themes").join("Darkly");
    local.is_dir()
        || paths::home().join(".themes/Darkly").is_dir()
        || Path::new("/usr/share/themes/Darkly").is_dir()
}

pub fn install_darkly_gtk_theme() -> bool {
    with_clone("https://github.com/wrymt/darkly-gtk", &[], |directory| {
        let code = process::run_visible("./install.sh", &["-l"], Some(directory));
        if code != Some(0) {
            output::err("Failed to install the Darkly GTK theme.");
            return false;
        }
        true
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_group_has_its_own_name_and_all_of_them_are_covered_by_all() {
        let groups = [Group::Core, Group::Shell, Group::Themes, Group::Utils];
        let mut names: Vec<&str> = groups.iter().map(|group| group.name()).collect();
        names.push(Group::All.name());
        let count = names.len();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), count, "two groups share a name");

        for group in groups {
            assert!(Group::All.covers(group), "all covers {}", group.name());
            assert!(group.covers(group), "{} covers itself", group.name());
            assert!(!group.covers(Group::All), "{} is not all", group.name());
        }
    }

    #[test]
    fn a_group_that_is_not_named_is_the_whole_install() {
        assert_eq!(Group::from_env(), Group::All);
    }

    #[test]
    fn a_failure_list_is_quiet_until_something_goes_into_it() {
        let mut failures = Failures::default();
        assert!(failures.is_empty());
        failures.add("nothing-installs-this");
        assert!(!failures.is_empty());
    }

    #[test]
    fn every_package_list_is_a_list_of_package_names() {
        let lists = [
            ("arch core", arch::CORE),
            ("arch shell", arch::SHELL),
            ("arch themes", arch::THEMES),
            ("arch utils", arch::UTILITIES),
            ("fedora core", fedora::CORE),
            ("fedora shell", fedora::SHELL),
            ("fedora themes", fedora::THEMES),
            ("fedora utils", fedora::UTILITIES),
            ("fedora copr core", fedora::COPR_CORE),
            ("fedora copr shell", fedora::COPR_SHELL),
            ("fedora copr all", fedora::COPR_ALL),
            ("debian core", debian::CORE),
            ("debian shell", debian::SHELL),
            ("debian themes", debian::THEMES),
            ("debian utils", debian::UTILITIES),
            ("debian fallback core", debian::FALLBACK_CORE),
            ("debian fallback shell", debian::FALLBACK_SHELL),
            ("debian fallback themes", debian::FALLBACK_THEMES),
            ("debian fallback utils", debian::FALLBACK_UTILS),
        ];

        for (name, list) in lists {
            let packages = names(list);
            assert!(!packages.is_empty(), "the {name} list is empty");

            let mut sorted = packages.clone();
            sorted.sort_unstable();
            sorted.dedup();
            assert_eq!(sorted.len(), packages.len(), "{name} names a package twice");

            for package in packages {
                assert!(
                    !package.contains(['$', '"', '\'', '\\', ';', '&', '*', '?', '(', ')']),
                    "{name} names {package}, which is not a package name"
                );
            }
        }
    }

    #[test]
    fn one_line_of_packages_is_read_back_as_the_same_names() {
        assert_eq!(names("a b\n  c\td"), ["a", "b", "c", "d"]);
        assert_eq!(names(""), Vec::<&str>::new());
    }

    /// Everything a distribution's install can put on the machine. The tests use this as the
    /// list the uninstall has to stay inside.
    /// Everything this distribution's install can put on the machine, as one list. An uninstall offers
    /// these to be removed, so the copy it keeps cannot fall behind the install.
    fn installable(distro: crate::distro::Distro) -> Vec<&'static str> {
        let (core, shell, themes, utils) = tables(distro);
        if core.is_empty() {
            return Vec::new();
        }
        let mut names = grouped(Group::Core, core, shell, themes, utils);
        for group in [Group::Shell, Group::Themes, Group::Utils] {
            names.extend(grouped(group, core, shell, themes, utils));
        }
        names.extend(elsewhere(distro));
        names.sort_unstable();
        names.dedup();
        names
    }

    fn tables(
        distro: crate::distro::Distro,
    ) -> (&'static str, &'static str, &'static str, &'static str) {
        match distro {
            crate::distro::Distro::Arch => (arch::CORE, arch::SHELL, arch::THEMES, arch::UTILITIES),
            crate::distro::Distro::Fedora => (
                fedora::CORE,
                fedora::SHELL,
                fedora::THEMES,
                fedora::UTILITIES,
            ),
            crate::distro::Distro::Debian => (
                debian::CORE,
                debian::SHELL,
                debian::THEMES,
                debian::UTILITIES,
            ),
            crate::distro::Distro::Unknown => ("", "", "", ""),
        }
    }

    /// The lists a distribution reaches for when its own repositories do not carry a package:
    /// Fedora's COPR set and Debian's fallbacks. They install real names too.
    fn elsewhere(distro: crate::distro::Distro) -> Vec<&'static str> {
        let lists: &[&'static str] = match distro {
            crate::distro::Distro::Fedora => {
                &[fedora::COPR_CORE, fedora::COPR_SHELL, fedora::COPR_ALL]
            }
            crate::distro::Distro::Debian => &[
                debian::FALLBACK_CORE,
                debian::FALLBACK_SHELL,
                debian::FALLBACK_THEMES,
                debian::FALLBACK_UTILS,
            ],
            _ => &[],
        };
        lists.iter().flat_map(|list| names(list)).collect()
    }

    #[test]
    fn an_uninstall_offers_desktop_tools_and_nothing_the_install_does_not_put_down() {
        for distro in [
            crate::distro::Distro::Arch,
            crate::distro::Distro::Fedora,
            crate::distro::Distro::Debian,
        ] {
            let offered = removable(distro);
            assert!(!offered.is_empty(), "{} offers nothing", distro.name());

            let installed = installable(distro);
            for package in &offered {
                let installed_here = installed.contains(package);
                let legacy = match distro {
                    crate::distro::Distro::Arch => names(arch::LEGACY),
                    crate::distro::Distro::Fedora => names(fedora::LEGACY),
                    crate::distro::Distro::Debian => names(debian::LEGACY),
                    crate::distro::Distro::Unknown => Vec::new(),
                };
                assert!(
                    installed_here || legacy.contains(package),
                    "{}: {package} is neither installed nor a legacy name",
                    distro.name()
                );
                // A legacy name is offered because an older install put it down, whatever it is;
                // what the current table offers to remove has to be a tool, not a build input.
                assert!(
                    !installed_here
                        || (!package.starts_with("qt6-")
                            && !package.contains("-dev")
                            && !package.contains("-devel")
                            && *package != "cmake"),
                    "{}: {package} is a build dependency, not a desktop tool to offer",
                    distro.name()
                );
            }
        }
    }

    #[test]
    fn a_legacy_name_is_one_the_table_no_longer_installs() {
        for (distro, legacy) in [
            (crate::distro::Distro::Arch, arch::LEGACY),
            (crate::distro::Distro::Fedora, fedora::LEGACY),
            (crate::distro::Distro::Debian, debian::LEGACY),
        ] {
            let installed = installable(distro);
            for package in names(legacy) {
                assert!(
                    !installed.contains(&package),
                    "{}: {package} is still installed, so it belongs in the table, not in LEGACY",
                    distro.name()
                );
            }
        }
    }

    #[test]
    fn every_group_gets_its_own_slice_and_all_gets_every_slice() {
        let lists = ("core", "shell", "themes", "utils");
        let (core, shell, themes, utils) = lists;

        assert_eq!(grouped(Group::Core, core, shell, themes, utils), ["core"]);
        assert_eq!(grouped(Group::Shell, core, shell, themes, utils), ["shell"]);
        assert_eq!(
            grouped(Group::All, core, shell, themes, utils),
            ["core", "shell", "themes", "utils"]
        );
    }
}
