use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Stdio;

use crate::copy;
use crate::distro::{self, Distro};
use crate::install_kind;
use crate::output;
use crate::paths;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

const THEME_NAME: &str = "caelestia";
const SYSTEM_THEME_DIR: &str = "/usr/share/sddm/themes/caelestia";
const SYSTEM_CONF_DIR: &str = "/etc/sddm.conf.d";
const LOCAL_SYNC: &str = "/usr/local/bin/caelestia-greeter-sync";
const SUDOERS_FILE: &str = "/etc/sudoers.d/caelestia-sddm-sync";
const DROP_IN: &str = "zz-caelestia.conf";
const OLD_DROP_IN: &str = "caelestia.conf";
const DROP_IN_BODY: &str = "[General]\n\
                           GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1\n\
                           \n\
                           [Theme]\n\
                           Current=caelestia\n";
const BACKUP: &str = "sddm.conf.theme-current";
const REQUIRED: [&str; 3] = ["theme.conf", "metadata.desktop", "Main.qml"];
const GREETER_DIRS: [&str; 5] = [
    "/usr/bin",
    "/usr/local/bin",
    "/usr/lib/sddm",
    "/usr/libexec/sddm",
    "/usr/local/libexec/sddm",
];

const ARCH_DEPS: [&str; 5] = [
    "sddm",
    "qt6-declarative",
    "qt6-5compat",
    "qt6-svg",
    "qt6-multimedia",
];
const FEDORA_DEPS: [&str; 5] = [
    "sddm",
    "qt6-qtdeclarative",
    "qt6-qt5compat",
    "qt6-qtsvg",
    "qt6-qtmultimedia",
];
const DEBIAN_DEPS: [&str; 5] = [
    "sddm",
    "qml6-module-qtquick",
    "qt6-5compat-dev",
    "libqt6svg6",
    "qt6-multimedia-dev",
];

// The posthook belongs to a JSON file that other tools own, so the edit is left to a JSON
// reader rather than to a hand-written one: the sections are merged, not replaced, and a
// key this installer has never heard of survives. python3 is a documented dependency of a
// Caelestia install - the color pipeline reads its scheme metadata with it.
const POSTHOOK_EDITOR: &str = r##"
import json, os, re, sys

cli_path, hook_cmd = sys.argv[1], sys.argv[2]

config = {}
if os.path.exists(cli_path):
    with open(cli_path) as f:
        config = json.load(f)

HELPERS = r"sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook"
ours = re.compile(
    r"\s*&&\s*" + HELPERS
    + r"|" + HELPERS + r"\s*&&\s*"
    + r"|" + HELPERS
)

for section in ("wallpaper", "theme"):
    config.setdefault(section, {})
    existing = config[section].get("postHook", "")
    if isinstance(existing, str):
        cleaned = ours.sub("", existing).strip()
        config[section]["postHook"] = f"{cleaned} && {hook_cmd}" if cleaned else hook_cmd

os.makedirs(os.path.dirname(cli_path), exist_ok=True)
with open(cli_path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
"##;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Variant {
    Full,
    Mini,
}

impl Variant {
    fn name(self) -> &'static str {
        match self {
            Variant::Full => "full",
            Variant::Mini => "mini",
        }
    }

    fn parse(text: &str) -> Option<Self> {
        match text.trim() {
            "full" => Some(Variant::Full),
            "mini" => Some(Variant::Mini),
            _ => None,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Greeter {
    Sddm,
    Plasmalogin,
}

pub fn run(context: &Context) -> Result<(), Failure> {
    if !context.flag("INSTALL_SDDM", true) {
        output::skip("SDDM theme not selected.");
        return Ok(());
    }

    println!();
    println!();
    output::info("Configuring the Caelestia login screen");
    println!();

    let packaged = install_kind::is_packaged();
    // Both system paths the step owns are named so that a test, or a package that installs
    // the theme somewhere else, can point them at a tree of its own.
    let theme_dir = PathBuf::from(
        context
            .variable("CAELESTIA_SDDM_THEME_DIR")
            .unwrap_or_else(|| SYSTEM_THEME_DIR.to_string()),
    );
    let conf_dir = PathBuf::from(
        context
            .variable("CAELESTIA_SDDM_CONF_DIR")
            .unwrap_or_else(|| SYSTEM_CONF_DIR.to_string()),
    );

    let variant = match context.variable("SDDM_THEME_VARIANT") {
        Some(requested) => Variant::parse(&requested)
            .ok_or_else(|| format!("Unknown SDDM theme variant: {requested}"))?,
        None => installed_variant(&theme_dir).unwrap_or(Variant::Full),
    };

    let sync = theme_dir.join("scripts").join("sync.sh");
    let mut step = LoginScreen {
        context,
        packaged,
        theme_dir,
        conf_dir,
        variant,
        source: context.bundle.join("src").join("sddm"),
        theme_source: PathBuf::new(),
        font_source: PathBuf::new(),
        sync,
        all_ok: true,
        runnable: false,
    };
    step.resolve_sources()?;

    match display_manager() {
        Greeter::Plasmalogin => {
            step.configure_plasmalogin()?;
            step.register_sync("Login screen configured for Plasma Login.")?;
            return Ok(());
        }
        Greeter::Sddm => {}
    }

    step.install_dependencies();
    step.install_theme_files()?;
    step.check_required_files();
    step.runnable = step.verify_greeter();
    step.remember_template();
    step.select_theme()?;
    step.report_selections();

    step.register_sync("SDDM theme installed.")
}

// The installed theme says which variant it is: the mini theme ships its own singletons,
// which the full one takes from the shared tree.
// which the full one takes from the shared tree.
fn installed_variant(directory: &Path) -> Option<Variant> {
    if !directory.join("metadata.desktop").is_file() {
        return None;
    }
    if directory.join("singletons").is_dir() {
        Some(Variant::Mini)
    } else {
        Some(Variant::Full)
    }
}

fn theme_qt_version(metadata: &Path) -> Option<String> {
    fs::read_to_string(metadata)
        .ok()?
        .lines()
        .filter_map(|line| line.split_once('='))
        .filter(|(key, _)| key.trim().eq_ignore_ascii_case("QtVersion"))
        .filter_map(|(_, value)| value.trim().parse::<u32>().ok())
        .map(|version| version.to_string())
        .next_back()
}

fn greeter_binary(version: &str) -> String {
    if version == "5" {
        "sddm-greeter".to_string()
    } else {
        format!("sddm-greeter-qt{version}")
    }
}

// The greeter SDDM itself would run: the name it derives from the theme's QtVersion, looked
// up where a distribution installs it.
fn greeter_path(version: &str) -> Option<PathBuf> {
    let name = greeter_binary(version);
    if let Some(path) = process::locate(&name) {
        return Some(path);
    }
    GREETER_DIRS
        .iter()
        .map(|directory| Path::new(directory).join(&name))
        .find(|candidate| process::is_executable(candidate))
}

fn manager_from(
    alias: Option<&str>,
    plasmalogin_unit: bool,
    sddm_unit: bool,
    conf: bool,
    sddm_on_path: bool,
) -> Greeter {
    if let Some(alias) = alias {
        if alias.contains("plasmalogin") {
            return Greeter::Plasmalogin;
        }
        if alias.contains("sddm") {
            return Greeter::Sddm;
        }
    }

    if plasmalogin_unit {
        return Greeter::Plasmalogin;
    }
    if sddm_unit {
        return Greeter::Sddm;
    }
    if conf && !sddm_on_path {
        return Greeter::Plasmalogin;
    }
    Greeter::Sddm
}

fn display_manager() -> Greeter {
    let alias = process::capture(
        "readlink",
        &["-f", "/etc/systemd/system/display-manager.service"],
    );
    manager_from(
        alias.as_deref(),
        unit_loaded("plasmalogin.service"),
        unit_loaded("sddm.service"),
        Path::new("/etc/plasmalogin.conf").exists(),
        process::available("sddm"),
    )
}

fn unit_loaded(unit: &str) -> bool {
    process::succeeds("systemctl", &["is-active", unit], None)
        || process::succeeds("systemctl", &["is-enabled", unit], None)
}

fn elevated(program: &str, args: &[&str]) -> bool {
    privileges::elevated(program, args, None) == Ok(0)
}

fn elevated_quietly(program: &str, args: &[&str]) -> bool {
    privileges::elevated_quietly(program, args, None) == Ok(0)
}

struct LoginScreen<'a> {
    context: &'a Context,
    packaged: bool,
    theme_dir: PathBuf,
    conf_dir: PathBuf,
    variant: Variant,
    source: PathBuf,
    theme_source: PathBuf,
    font_source: PathBuf,
    sync: PathBuf,
    all_ok: bool,
    runnable: bool,
}

impl LoginScreen<'_> {
    fn resolve_sources(&mut self) -> Result<(), Failure> {
        self.theme_source = if self.packaged {
            if !self.theme_dir.join("theme.conf").is_file() {
                return Err(format!(
                    "The package's login screen theme is not installed at {}",
                    self.theme_dir.display()
                )
                .into());
            }
            self.theme_dir.clone()
        } else {
            let source = self.source.join("themes").join(self.variant.name());
            if !source.is_dir() {
                return Err(format!("SDDM theme source not found at {}", source.display()).into());
            }
            source
        };

        // The font is part of the lock screen package in a checkout, and of the theme the
        // package ships in an installed one.
        self.font_source = if self.packaged {
            self.theme_dir
                .join("assets")
                .join("google-sans-flex")
                .join("GoogleSansFlex.ttf")
        } else {
            self.context
                .bundle
                .join("src/kde/shells/caelestia.desktop/contents/fonts/GoogleSansFlex.ttf")
        };
        Ok(())
    }

    fn configure_plasmalogin(&mut self) -> Result<(), Failure> {
        if self.packaged {
            self.sync = self.theme_dir.join("scripts").join("sync.sh");
            if !process::is_executable(&self.sync) {
                return Err(format!(
                    "The package's login screen helper is not installed at {}",
                    self.sync.display()
                )
                .into());
            }
        } else {
            self.sync = PathBuf::from(LOCAL_SYNC);
            let source = self.source.join("sync.sh").to_string_lossy().to_string();
            let target = self.sync.to_string_lossy().to_string();
            elevated("install", &["-d", "-m", "0755", "/usr/local/bin"]);
            if !elevated("install", &["-m", "0755", &source, &target]) {
                return Err(format!("Could not install the sync helper to {target}").into());
            }
            output::ok(&format!("Login screen sync helper installed to {target}"));
        }

        let sync = self.sync.to_string_lossy().to_string();
        match privileges::elevated(&sync, &[], None) {
            Ok(0) => output::ok("Initial login screen sync complete."),
            _ => {
                output::warn("Initial login screen sync had warnings (non-fatal):");
                self.all_ok = false;
            }
        }
        Ok(())
    }

    fn install_dependencies(&mut self) {
        if self.packaged {
            output::skip("The display manager's dependencies belong to the package.");
            return;
        }

        let wanted: &[&str] = match distro::detect() {
            Distro::Arch => &ARCH_DEPS,
            Distro::Fedora => &FEDORA_DEPS,
            Distro::Debian => &DEBIAN_DEPS,
            Distro::Unknown => {
                output::warn(&format!(
                    "Unsupported distribution ({}). SDDM Qt6 dependencies must be installed manually.",
                    distro::detect().name()
                ));
                self.all_ok = false;
                return;
            }
        };

        let missing = pkg::missing(wanted);
        if !missing.is_empty() {
            output::info(&format!(
                "Installing SDDM dependencies: {}",
                missing.join(" ")
            ));
            if !pkg::install_all(&missing) {
                output::warn("Could not install every SDDM dependency.");
                self.all_ok = false;
                return;
            }
        }
        output::ok("Dependencies met.");
    }

    fn install_theme_files(&mut self) -> Result<(), Failure> {
        if self.packaged {
            output::skip("The theme files belong to the package.");
            return Ok(());
        }

        let theme_dir = self.theme_dir.to_string_lossy().to_string();
        if self.theme_dir.exists() && !elevated("rm", &["-rf", &theme_dir]) {
            return Err(format!("Could not replace the theme installed at {theme_dir}").into());
        }

        let scripts = self.theme_dir.join("scripts").to_string_lossy().to_string();
        if !elevated("mkdir", &["-p", &scripts]) {
            return Err(format!("Could not create {scripts}").into());
        }

        // `cp -r "$source"/* "$dir"/`, with the glob spelled out: a dotfile is not part of
        // the theme, and VCS metadata in one must not land in /usr.
        let entries = fs::read_dir(&self.theme_source)
            .map_err(|error| format!("cannot read {}: {error}", self.theme_source.display()))?;
        for entry in entries.filter_map(Result::ok) {
            let name = entry.file_name();
            if name.to_string_lossy().starts_with('.') {
                continue;
            }
            let from = entry.path().to_string_lossy().to_string();
            let to = format!("{theme_dir}/");
            if !elevated("cp", &["-a", &from, &to]) {
                return Err(format!("Could not copy {from} into {theme_dir}").into());
            }
        }

        let sync_source = self.source.join("sync.sh").to_string_lossy().to_string();
        if !elevated("cp", &[&sync_source, &scripts]) {
            return Err(format!("Could not install the sync helper into {scripts}").into());
        }

        let assets = self
            .theme_dir
            .join("assets")
            .join("google-sans-flex")
            .to_string_lossy()
            .to_string();
        elevated("mkdir", &["-p", &assets]);

        if self.font_source.is_file() {
            let font = self.font_source.to_string_lossy().to_string();
            if !elevated("cp", &[&font, &format!("{assets}/GoogleSansFlex.ttf")]) {
                return Err("Could not install the theme's font".into());
            }
        } else {
            output::warn(&format!(
                "GoogleSansFlex.ttf not found at {}, theme text may not render correctly.",
                self.font_source.display()
            ));
            self.all_ok = false;
        }

        if self.variant == Variant::Mini {
            let shapes = self.source.join("themes/full/components/shapes");
            if shapes.is_dir() {
                let target = self
                    .theme_dir
                    .join("components")
                    .join("shapes")
                    .to_string_lossy()
                    .to_string();
                elevated("mkdir", &["-p", &target]);
                for entry in fs::read_dir(&shapes)
                    .into_iter()
                    .flatten()
                    .filter_map(Result::ok)
                {
                    let name = entry.file_name();
                    if name.to_string_lossy().starts_with('.') {
                        continue;
                    }
                    let from = entry.path().to_string_lossy().to_string();
                    if !elevated("cp", &["-a", &from, &format!("{target}/")]) {
                        return Err(format!("Could not copy {from} into {target}").into());
                    }
                }
            } else {
                output::warn(&format!(
                    "Shape components not found at {}, mini theme will not render correctly.",
                    shapes.display()
                ));
                self.all_ok = false;
            }
        }

        for (kind, mode) in [("d", "755"), ("f", "644")] {
            if !elevated(
                "find",
                &[&theme_dir, "-type", kind, "-exec", "chmod", mode, "{}", "+"],
            ) {
                return Err(format!("Could not set the theme's {kind} permissions").into());
            }
        }
        if !elevated("chmod", &["755", &self.sync.to_string_lossy()]) {
            return Err("Could not make the sync helper executable".into());
        }

        output::ok(&format!(
            "Theme files installed to {theme_dir} ({} variant)",
            self.variant.name()
        ));
        Ok(())
    }

    fn check_required_files(&mut self) {
        for required in REQUIRED {
            if !self.theme_dir.join(required).exists() {
                output::warn(&format!(
                    "{}/{required} is missing: SDDM will ignore this theme and show the default.",
                    self.theme_dir.display()
                ));
                self.all_ok = false;
            }
        }
    }

    // A theme whose greeter is not installed cannot start, and a login screen that cannot
    // start is worse than the default one, so the selection is what this gates.
    fn verify_greeter(&mut self) -> bool {
        let metadata = self.theme_dir.join("metadata.desktop");
        let Some(version) = theme_qt_version(&metadata) else {
            output::warn(&format!(
                "{} does not declare a QtVersion, so SDDM would run this Qt 6 theme under its Qt 5 greeter.",
                metadata.display()
            ));
            return false;
        };

        match greeter_path(&version) {
            Some(path) => {
                output::ok(&format!(
                    "Theme runs under {} (Qt {version}).",
                    path.file_name()
                        .map(|name| name.to_string_lossy().to_string())
                        .unwrap_or_default()
                ));
                true
            }
            None => {
                output::warn(&format!(
                    "SDDM has no {} to run the theme with.",
                    greeter_binary(&version)
                ));
                false
            }
        }
    }

    fn remember_template(&mut self) {
        let templates = paths::home()
            .join(".config")
            .join("caelestia")
            .join("templates");
        let _ = fs::create_dir_all(&templates);

        let template = self.theme_source.join("theme.conf.template");
        if template.is_file() {
            match copy::file(&template, &templates.join("sddm-theme.conf")) {
                Ok(_) => output::ok("Template config created."),
                Err(error) => {
                    output::warn(&format!("Could not create the template config: {error}"));
                    self.all_ok = false;
                }
            }
        }
    }

    fn select_theme(&mut self) -> Result<(), Failure> {
        if self.packaged {
            output::skip("The theme selection belongs to the package.");
            if !self.runnable {
                output::warn(
                    "The package selects the theme anyway. Point [Theme] Current at another theme until the greeter above is installed.",
                );
            }
            return Ok(());
        }

        if !self.runnable {
            output::warn(
                "The theme is installed but left unselected: a login screen that cannot start is worse than the default one.",
            );
            output::warn("Install the greeter above, then run 'caelestia login-screen'.");
            self.remove_selection();
            return Ok(());
        }

        let directory = self.conf_dir.to_string_lossy().to_string();
        let drop_in = self.conf_dir.join(DROP_IN).to_string_lossy().to_string();
        let old_drop_in = self
            .conf_dir
            .join(OLD_DROP_IN)
            .to_string_lossy()
            .to_string();

        elevated("mkdir", &["-p", &directory]);
        let Some(work) = TempDir::new("caelestia-sddm") else {
            return Err("Could not create a working directory for the drop-in".into());
        };
        let staged = work.path().join(DROP_IN);
        fs::write(&staged, DROP_IN_BODY)
            .map_err(|error| format!("cannot write the drop-in: {error}"))?;
        if !elevated(
            "install",
            &["-m", "0644", &staged.to_string_lossy(), &drop_in],
        ) {
            return Err(format!("Could not write {drop_in}").into());
        }
        elevated("rm", &["-f", &old_drop_in]);
        output::ok("SDDM config drop-in created.");

        self.remember_selection();
        Ok(())
    }

    // The selection is recorded once, so that uninstall can put back what was there before
    // this install ever touched it - including that there was nothing.
    fn remember_selection(&mut self) {
        if !process::available("kwriteconfig6") {
            return;
        }

        let backup = paths::state_dir().join("caelestia").join(BACKUP);
        if !backup.is_file() && process::available("kreadconfig6") {
            if let Some(parent) = backup.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let previous = process::capture(
                "kreadconfig6",
                &[
                    "--file",
                    "/etc/sddm.conf",
                    "--group",
                    "Theme",
                    "--key",
                    "Current",
                ],
            )
            .unwrap_or_default();
            let previous = if previous.is_empty() {
                "#none".to_string()
            } else {
                previous
            };
            let _ = fs::write(&backup, format!("{previous}\n"));
        }

        if elevated_quietly(
            "kwriteconfig6",
            &[
                "--file",
                "/etc/sddm.conf",
                "--group",
                "Theme",
                "--key",
                "Current",
                THEME_NAME,
            ],
        ) {
            output::ok("Theme selected in /etc/sddm.conf as well.");
        } else {
            output::warn("Could not write to /etc/sddm.conf; the drop-in is the only selection.");
        }
    }

    fn remove_selection(&mut self) {
        let backup = paths::state_dir().join("caelestia").join(BACKUP);

        for name in [DROP_IN, OLD_DROP_IN] {
            let drop_in = self.conf_dir.join(name);
            if drop_in.is_file() {
                elevated("rm", &["-f", &drop_in.to_string_lossy()]);
                output::ok(&format!("Removed the SDDM theme drop-in: {name}"));
            }
        }

        if !process::available("kwriteconfig6") {
            return;
        }

        let current = if backup.is_file() {
            fs::read_to_string(&backup)
                .unwrap_or_default()
                .trim()
                .to_string()
        } else {
            let current = process::capture(
                "kreadconfig6",
                &[
                    "--file",
                    "/etc/sddm.conf",
                    "--group",
                    "Theme",
                    "--key",
                    "Current",
                ],
            )
            .unwrap_or_default();
            if current != THEME_NAME {
                return;
            }
            current
        };

        let mut args = vec![
            "--file",
            "/etc/sddm.conf",
            "--group",
            "Theme",
            "--key",
            "Current",
        ];
        if current == "#none" {
            args.push("--delete");
        } else {
            args.push(&current);
        }
        let _ = elevated_quietly("kwriteconfig6", &args);

        let _ = fs::remove_file(&backup);
        output::ok("Restored the login screen theme selection.");
    }

    fn report_selections(&mut self) {
        let mut files: Vec<PathBuf> = Vec::new();
        for directory in [Path::new("/usr/lib/sddm/sddm.conf.d"), &self.conf_dir] {
            if let Ok(entries) = fs::read_dir(directory) {
                files.extend(
                    entries
                        .filter_map(Result::ok)
                        .map(|entry| entry.path())
                        .filter(|path| path.extension().and_then(|e| e.to_str()) == Some("conf")),
                );
            }
        }
        files.push(PathBuf::from("/etc/sddm.conf"));
        files.sort();

        for file in files {
            let Some(current) = fs::read_to_string(&file).ok().and_then(|text| {
                text.lines()
                    .rfind(|line| {
                        line.split_once('=')
                            .map(|(key, _)| key.trim() == "Current")
                            .unwrap_or(false)
                    })
                    .map(|line| line.replace(' ', ""))
            }) else {
                continue;
            };
            output::info(&format!("{}: {current}", file.display()));
        }
    }

    fn register_sync(&mut self, label: &str) -> Result<(), Failure> {
        let hook = format!("sudo {} --posthook", self.sync.display());
        let cli_json = paths::home()
            .join(".config")
            .join("caelestia")
            .join("cli.json");

        if process::available("python3") {
            write_posthook(&cli_json, &hook)?;
            output::ok("Posthook registered in cli.json");
        } else {
            output::warn(
                "python3 not found, skipping posthook registration. Wallpaper and color changes will not auto-sync to the login screen.",
            );
            self.all_ok = false;
        }

        // The rule is checked before it is installed: a malformed file in sudoers.d stops
        // sudo working for the whole machine, and $USER is only an environment variable, so
        // the name comes from id instead.
        let user = std::env::var("SUDO_USER")
            .ok()
            .filter(|user| !user.is_empty())
            .or_else(|| process::capture("id", &["-un"]))
            .unwrap_or_default();
        if !is_a_user_name(&user) {
            output::warn(&format!(
                "Could not tell which user the login screen sync belongs to (got '{user}')."
            ));
            self.all_ok = false;
            return Ok(());
        }

        let Some(work) = TempDir::new("caelestia-sudoers") else {
            return Err("Could not create a working directory for the sudoers rule".into());
        };
        let rule = work.path().join("rule");
        fs::write(
            &rule,
            format!("{user} ALL=(root) NOPASSWD: {}\n", self.sync.display()),
        )
        .map_err(|error| format!("cannot write the sudoers rule: {error}"))?;

        if !elevated("visudo", &["-cf", &rule.to_string_lossy()]) {
            output::warn(&format!(
                "The generated sudoers rule for {} did not validate; leaving sudoers alone.",
                self.sync.display()
            ));
            self.all_ok = false;
            return Ok(());
        }

        if elevated(
            "install",
            &[
                "-m",
                "0440",
                "-o",
                "root",
                "-g",
                "root",
                &rule.to_string_lossy(),
                SUDOERS_FILE,
            ],
        ) {
            output::ok(&format!(
                "Sudoers drop-in written for {}.",
                self.sync.display()
            ));
        } else {
            output::warn(&format!(
                "Could not write {SUDOERS_FILE}; the login screen will not follow the theme."
            ));
            self.all_ok = false;
        }

        if self.all_ok {
            output::ok(label);
        } else {
            output::warn("Login screen installed with warnings. Review the output above.");
        }
        Ok(())
    }
}

fn is_a_user_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn write_posthook(path: &Path, hook: &str) -> Result<(), Failure> {
    let target = path.to_string_lossy().to_string();
    let mut command = std::process::Command::new("python3");
    command
        .args(["-", &target, hook])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let mut child = command
        .spawn()
        .map_err(|error| format!("could not run python3 to register the posthook: {error}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(POSTHOOK_EDITOR.as_bytes())
            .map_err(|error| format!("could not hand python3 the posthook editor: {error}"))?;
    }
    let status = child
        .wait()
        .map_err(|error| format!("python3 did not finish: {error}"))?;
    if !status.success() {
        return Err(format!("could not register the posthook in {target}").into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_variant_is_read_from_the_installed_theme() {
        let work = TempDir::new("caelestia-login-test").expect("a temporary directory");
        let full = work.path().join("full");
        let mini = work.path().join("mini");
        fs::create_dir_all(&full).expect("the full theme");
        fs::create_dir_all(mini.join("singletons")).expect("the mini theme");
        fs::write(full.join("metadata.desktop"), b"[SddmGreeterTheme]\n").expect("the metadata");
        fs::write(mini.join("metadata.desktop"), b"[SddmGreeterTheme]\n").expect("the metadata");

        assert_eq!(installed_variant(&full), Some(Variant::Full));
        assert_eq!(installed_variant(&mini), Some(Variant::Mini));
        assert_eq!(
            installed_variant(&work.path().join("none")),
            None,
            "a directory holding no theme names no variant"
        );
        assert_eq!(
            installed_variant(work.path()),
            None,
            "and neither does one whose metadata is not there yet"
        );
    }

    #[test]
    fn a_variant_name_is_taken_only_when_it_is_one() {
        assert_eq!(Variant::parse("full"), Some(Variant::Full));
        assert_eq!(Variant::parse(" mini "), Some(Variant::Mini));
        assert_eq!(Variant::parse("FULL"), None);
        assert_eq!(Variant::parse(""), None);
        assert_eq!(Variant::parse("huge"), None);
    }

    #[test]
    fn the_qt_version_is_read_the_way_sddm_routes_on_it() {
        let work = TempDir::new("caelestia-login-test").expect("a temporary directory");
        let metadata = work.path().join("metadata.desktop");
        let undeclared = work.path().join("undeclared.desktop");

        fs::write(&metadata, "[SddmGreeterTheme]\nQtVersion=6\n").expect("the metadata");
        assert_eq!(theme_qt_version(&metadata), Some("6".to_string()));

        fs::write(
            &metadata,
            "[SddmGreeterTheme]\nQtVersion = 5\nName=Caelestia\n",
        )
        .expect("the metadata");
        assert_eq!(theme_qt_version(&metadata), Some("5".to_string()));

        fs::write(&undeclared, "[SddmGreeterTheme]\nName=Caelestia\n").expect("the metadata");
        assert_eq!(
            theme_qt_version(&undeclared),
            None,
            "a theme that declares none is read as Qt 5, not as a version"
        );
        assert_eq!(theme_qt_version(&work.path().join("absent")), None);
    }

    #[test]
    fn the_greeter_binary_is_the_name_that_version_needs() {
        assert_eq!(greeter_binary("5"), "sddm-greeter");
        assert_eq!(greeter_binary("6"), "sddm-greeter-qt6");
        assert_eq!(greeter_binary("7"), "sddm-greeter-qt7");
    }

    #[test]
    fn the_boot_alias_decides_the_display_manager_over_every_other_signal() {
        assert_eq!(
            manager_from(
                Some("/usr/lib/systemd/system/plasmalogin.service"),
                false,
                true,
                false,
                true
            ),
            Greeter::Plasmalogin,
            "the alias beats a still-enabled SDDM"
        );
        assert_eq!(
            manager_from(
                Some("/usr/lib/systemd/system/sddm.service"),
                true,
                false,
                false,
                true
            ),
            Greeter::Sddm,
            "and beats a still-enabled Plasma Login"
        );
    }

    #[test]
    fn without_an_alias_the_display_manager_is_the_one_that_is_loaded() {
        assert_eq!(
            manager_from(None, true, false, false, true),
            Greeter::Plasmalogin
        );
        assert_eq!(manager_from(None, false, true, false, false), Greeter::Sddm);
        assert_eq!(
            manager_from(None, true, true, false, true),
            Greeter::Plasmalogin,
            "Plasma Login is asked about first, as the newer of the two"
        );
        assert_eq!(
            manager_from(None, false, false, true, false),
            Greeter::Plasmalogin,
            "a Plasma Login config with no sddm binary is Plasma Login"
        );
        assert_eq!(
            manager_from(None, false, false, true, true),
            Greeter::Sddm,
            "but not when sddm is installed"
        );
        assert_eq!(
            manager_from(None, false, false, false, true),
            Greeter::Sddm,
            "nothing to go on is SDDM, which is what is installed by default"
        );
    }

    #[test]
    fn a_login_name_is_checked_before_it_reaches_the_sudoers_file() {
        for good in ["camus", "build.user", "user-name", "user_name", "u123"] {
            assert!(is_a_user_name(good), "{good} is a login name");
        }
        for bad in ["", "two words", "a:b", "a;rm -rf /", "a\nb", "$USER"] {
            assert!(!is_a_user_name(bad), "{bad:?} is not a login name");
        }
    }

    #[cfg(unix)]
    #[test]
    fn the_posthook_keeps_a_hook_the_user_wrote_and_does_not_stack_ours() {
        if !process::available("python3") {
            return;
        }

        let work = TempDir::new("caelestia-posthook-test").expect("a temporary directory");
        let cli = work.path().join("cli.json");
        let ours = "sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh --posthook";

        fs::write(
            &cli,
            format!(
                "{{\n    \"wallpaper\": {{\"postHook\": \"my-own-tool --posthook && {ours}\"}},\n    \
                 \"theme\": {{\"postHook\": \"{ours}\"}},\n    \"unrelated\": {{\"keep\": true}}\n}}\n"
            ),
        )
        .expect("the config");

        write_posthook(
            &cli,
            "sudo /usr/local/bin/caelestia-greeter-sync --posthook",
        )
        .expect("the posthook is registered");

        let written = fs::read_to_string(&cli).expect("the config");
        let edit = |section: &str| {
            let start = written
                .find(&format!("\"{section}\""))
                .expect("the section");
            let rest = &written[start..];
            let hook = rest.find("\"postHook\"").expect("the hook");
            let rest = &rest[hook + 10..];
            let open = rest.find('"').expect("the value");
            let rest = &rest[open + 1..];
            let close = rest.find('"').expect("the end of the value");
            rest[..close].to_string()
        };

        assert_eq!(
            edit("wallpaper"),
            "my-own-tool --posthook && sudo /usr/local/bin/caelestia-greeter-sync --posthook",
            "another tool's hook stays in front, and the old helper is replaced"
        );
        assert_eq!(
            edit("theme"),
            "sudo /usr/local/bin/caelestia-greeter-sync --posthook",
            "the helper left by the other display manager does not survive as a second hook"
        );
        assert!(
            written.contains("\"keep\": true"),
            "a key this installer has never heard of is left alone"
        );

        let once = fs::read_to_string(&cli).expect("the config");
        write_posthook(
            &cli,
            "sudo /usr/local/bin/caelestia-greeter-sync --posthook",
        )
        .expect("the posthook is registered again");
        assert_eq!(
            once,
            fs::read_to_string(&cli).expect("the config"),
            "a second run is idempotent"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_posthook_edit_into_a_directory_that_is_not_there_makes_it() {
        if !process::available("python3") {
            return;
        }

        let work = TempDir::new("caelestia-posthook-test").expect("a temporary directory");
        let cli = work.path().join("caelestia").join("cli.json");

        write_posthook(
            &cli,
            "sudo /usr/local/bin/caelestia-greeter-sync --posthook",
        )
        .expect("the posthook is registered");

        let written = fs::read_to_string(&cli).expect("the config");
        assert!(written.contains("wallpaper"), "{written}");
        assert!(written.contains("theme"), "{written}");
    }
}
