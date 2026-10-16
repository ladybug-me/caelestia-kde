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

// What a distro's package list is split into. Every group is a slice of one list, and "all"
// is what the install step asks for; naming one is how a partial install takes a single slice.
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

    // Whether installing this group covers the one asked about: "all" covers everything.
    pub fn covers(self, one: Group) -> bool {
        self == Group::All || self == one
    }
}

// 02-all-packages: the distribution's own packages, which the shell, its plugin and the
// utilities around them are built against.
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

// 02-packages: the tooling no distribution packages for us and the rest of the install needs
// regardless of where it came from - pip, for the konsave backups, and matugen, without
// which no wallpaper can be turned into a palette.
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

// matugen has a ladder of its own - dnf, yay, pacman, a GitHub release, cargo - and the
// session's own startup task asks the same helper for the same thing. The installer runs
// that helper rather than carrying a second copy of the ladder to drift from it.
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

// starship publishes an installer script rather than a package for every distribution. It is
// fetched first and then run, so a failed download is not a half-run install.
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

// Every manual fallback below is a repository cloned into a scratch directory and a command
// run inside it, so the clone lives here and each distro supplies only its own command.
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

// The build commands and the package managers below all print progress the user is watching,
// so the success of a command is asked for without its output being swallowed.
pub fn run_visibly(program: &str, args: &[&str], directory: Option<&Path>) -> bool {
    process::run_visible(program, args, directory) == Some(0)
}

// Running something as root: what every call site below wants to know is whether it worked.
pub fn elevated(program: &str, args: &[&str]) -> bool {
    privileges::elevated(program, args, None) == Ok(0)
}

pub fn elevated_in(program: &str, args: &[&str], directory: &Path) -> bool {
    privileges::elevated(program, args, Some(directory)) == Ok(0)
}

// The lists are data: whitespace-separated, so a package does not take a line of its own.
pub fn names(list: &str) -> Vec<&str> {
    list.split_whitespace().collect()
}

// The list a group asks for: its own slice of a distro's packages, or every slice for a full
// install.
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

// What could not be installed, said once at the end of the group rather than as each attempt
// fails, and recorded where the update checker reads it.
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

// The second pass over a batch that failed: one attempt per package, so a single package the
// manager cannot resolve does not take the rest of the group with it.
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

// A package the user asked to leave out, in the group that would have carried it.
pub fn wanted(context: &Context, flag: &str, skip: &str) -> bool {
    if context.flag(flag, true) {
        return true;
    }
    output::info(skip);
    false
}

// The theme's own fonts, which no distribution carries in the shapes the shell asks for.
// Fetched at once: three or four files from two hosts, and the downloads are the whole cost.
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

// Both of these ship as packages and then have to answer to a name the shell calls: sass for
// the Dart compiler, qdbus6 for the Qt6 one, which several distributions only install under
// the versioned name.
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

// The Darkly GTK theme ships as a build script rather than a package, which is why it is not
// in any of the lists below. Upstream's installer only drops theme directories, so the
// directories are the whole answer to whether it is there.
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

    // The lists are what the step hands to a package manager, so a name with whitespace or a
    // shell metacharacter in it would be read as something else entirely. The distro modules
    // carry the data; this is the one place it is checked.
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
