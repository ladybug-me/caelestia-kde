use std::fs;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};

use crate::distro::{self, Distro};
use crate::output;
use crate::paths;
use crate::pkg;
use crate::privileges;
use crate::process;
use crate::steps::Failure;

// The banner the shell version printed, kept so the two entry points look the same.
const BANNER: &str = r"   _____            _           _   _
  / ____|          | |         | | (_)
 | |     __ _  ___ | | ___  ___| |_ _  __ _
 | |    / _` |/ _ \| |/ _ \/ __| __| |/ _` |
 | |___| (_| | (_) | |  __/\__ \ |_| | (_| |
  \_____\__,_|\___/|_|\___||___/\__|_|\__,_|";

// The panel the installer's own desktop setup creates. Restoring it by name is the only way
// back to a usable desktop when there is no backup to restore from.
const STOCK_PANEL: &str = r"if (panels().length === 0) {
    var panel = new Panel;
    panel.alignment = 'center';
    panel.location = 'bottom';
    panel.hiding = 'dodgewindows';
    panel.height = 48;
    panel.addWidget('org.kde.plasma.kickoff');
    panel.addWidget('org.kde.plasma.icontasks');
    panel.addWidget('org.kde.plasma.systemtray');
    panel.addWidget('org.kde.plasma.digitalclock');
}";

// The cli.json posthook is written by a JSON reader rather than by hand: the sections belong to
// another tool and only the hook this installer added comes out. python3 is a documented
// dependency of a Caelestia install, and the same editor shape is used by the login screen step.
const POSTHOOK_CLEANER: &str = r##"
import json, os, re, sys

cli_path = sys.argv[1]
if not os.path.exists(cli_path):
    sys.exit(0)

with open(cli_path) as f:
    config = json.load(f)

ours = re.compile(
    r'\s*&&\s*sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook'
    r'|sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook\s*&&\s*'
    r'|sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook'
)

changed = False
for section in ("wallpaper", "theme"):
    hook = config.get(section, {}).get("postHook", "")
    if not hook:
        continue
    cleaned = ours.sub('', hook).strip()
    if cleaned != hook:
        changed = True
        if cleaned:
            config[section]["postHook"] = cleaned
        else:
            del config[section]["postHook"]

if changed:
    with open(cli_path, "w") as f:
        json.dump(config, f, indent=4)
"##;

// The three set of packages an install may have brought in, per distribution. They are the
// tools named in the package lists that are also ordinary desktop tools, which is why removing
// them is a question rather than a decision.
const ARCH_PACKAGES: &[&str] = &[
    "quickshell",
    "matugen",
    "foot",
    "eza",
    "fastfetch",
    "starship",
    "btop",
    "fuzzel",
    "swappy",
    "satty",
    "gpu-screen-recorder",
    "slurp",
    "grim",
    "wl-clipboard",
    "cliphist",
    "wl-clip-persist",
    "app2unit",
    "libcava",
    "brightnessctl",
    "ddcutil",
    "tesseract",
    "tesseract-data-eng",
    "bat",
    "ripgrep",
    "lazygit",
    "jq",
    "trash-cli",
    "inotify-tools",
    "imagemagick",
    "sassc",
    "xdg-utils",
    "xdg-user-dirs",
    "spectacle",
    "adw-gtk-theme",
    "papirus-icon-theme",
    "darkly",
    "darkly-bin",
    "ttf-jetbrains-mono-nerd",
    "ttf-material-symbols-variable",
    "ttf-rubik-vf",
    "ttf-cascadia-code-nerd",
];

const FEDORA_PACKAGES: &[&str] = &[
    "quickshell-git",
    "matugen",
    "foot",
    "eza",
    "fastfetch",
    "starship",
    "btop",
    "fuzzel",
    "swappy",
    "satty",
    "gpu-screen-recorder",
    "gpu-screen-recorder-ui",
    "slurp",
    "grim",
    "wl-clipboard",
    "cliphist",
    "wl-clip-persist",
    "app2unit",
    "libcava",
    "libcava-devel",
    "brightnessctl",
    "ddcutil",
    "tesseract",
    "tesseract-langpack-eng",
    "bat",
    "ripgrep",
    "jq",
    "trash-cli",
    "inotify-tools",
    "ImageMagick",
    "sassc",
    "xdg-utils",
    "xdg-user-dirs",
    "spectacle",
    "adw-gtk3-theme",
    "papirus-icon-theme",
    "darkly",
    "google-rubik-fonts",
];

const DEBIAN_PACKAGES: &[&str] = &[
    "quickshell",
    "matugen",
    "foot",
    "eza",
    "fastfetch",
    "starship",
    "btop",
    "fuzzel",
    "swappy",
    "satty",
    "gpu-screen-recorder",
    "slurp",
    "grim",
    "wl-clipboard",
    "cliphist",
    "wl-clip-persist",
    "app2unit",
    "cava",
    "libcava",
    "brightnessctl",
    "ddcutil",
    "tesseract-ocr",
    "tesseract-ocr-eng",
    "jq",
    "yq",
    "trash-cli",
    "inotify-tools",
    "imagemagick",
    "sassc",
    "xdg-utils",
    "kde-spectacle",
    "adw-gtk3",
    "adw-gtk3-theme",
    "papirus-icon-theme",
    "darkly",
];

struct Uninstaller {
    bundle: PathBuf,
    home: PathBuf,
    remove_packages: bool,
    family: Distro,
    backup: Option<PathBuf>,
    konsave_archive: Option<PathBuf>,
    konsave: Option<PathBuf>,
    theme_restored: bool,
    previous_lookandfeel: String,
    shell_rc_restored: bool,
}

pub fn run(bundle: &Path) -> Result<(), Failure> {
    let mut uninstaller = Uninstaller {
        bundle: bundle.to_path_buf(),
        home: paths::home(),
        remove_packages: false,
        family: distro::detect(),
        backup: None,
        konsave_archive: None,
        konsave: None,
        theme_restored: false,
        previous_lookandfeel: String::new(),
        shell_rc_restored: false,
    };

    uninstaller.greet()?;
    uninstaller.stop_services();
    uninstaller.remove_service_files();
    uninstaller.remove_shell_installation();
    uninstaller.remove_shell_state();
    uninstaller.remove_bridge_scripts();
    uninstaller.restore_or_remove_configs();
    uninstaller.revert_kde_settings();
    uninstaller.revert_shell_changes();
    uninstaller.remove_system_files();
    uninstaller.remove_packages();
    uninstaller.clean_caches();
    uninstaller.reload_kde();

    section("Uninstall Complete");
    println!();
    output::ok("Caelestia has been uninstalled.");
    println!();
    println!(
        "  Backups of your original configs are in:  {}/backups/",
        bundle.display()
    );
    println!();
    output::warn("Please log out and back in to fully apply all changes.");
    println!();

    if asked("Would you like to log out now?") {
        println!("Logging out...");
        let _ = process::succeeds(
            "qdbus6",
            &["org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"],
            None,
        );
    } else {
        println!("Exiting script. Please remember to log out manually later.");
    }
    Ok(())
}

impl Uninstaller {
    fn path(&self, relative: &str) -> PathBuf {
        self.home.join(relative)
    }

    // The distribution is asked for when nothing identifies it: the package list an uninstall
    // offers is per distribution, and guessing would offer the wrong one.
    fn greet(&mut self) -> Result<(), Failure> {
        if self.family == Distro::Unknown {
            println!("Could not detect distribution. Select base:");
            println!("  1) Arch-based   2) Fedora-based   3) Debian-based   4) Exit");
            match prompt("Choice [1-4]:").trim() {
                "1" => self.family = Distro::Arch,
                "2" => self.family = Distro::Fedora,
                "3" => self.family = Distro::Debian,
                _ => return Err("Exiting.".into()),
            }
        }

        println!("{BANNER}");
        println!("+------------------------------------------------------------------+");
        println!("|                       CAELESTIA UNINSTALLER                       |");
        println!("+------------------------------------------------------------------+");
        println!();
        println!(" This will remove Caelestia shell files and configs.");
        println!(
            " Backups in {}/backups/ can be restored during uninstall.",
            self.bundle.display()
        );
        println!();

        self.prime_sudo()?;

        println!();
        if !asked("Are you sure you want to uninstall Caelestia?") {
            return Err("Uninstall canceled.".into());
        }

        println!();
        println!("Remove installed packages as well? This will uninstall");
        println!("tools like foot, btop, fastfetch, and others.");
        self.remove_packages = asked("Remove packages?");

        self.choose_backup()?;
        Ok(())
    }

    // A password is asked for once, here, rather than at the first file that needs root: an
    // uninstall that stops halfway for a credential leaves the system in between.
    fn prime_sudo(&self) -> Result<(), Failure> {
        if privileges::is_root() || std::env::var("CAELESTIA_SUDO_PRIMED").as_deref() == Ok("1") {
            return Ok(());
        }

        match privileges::elevated("true", &[], None) {
            Ok(0) => Ok(()),
            _ => Err("Failed to obtain sudo privileges.".into()),
        }
    }

    fn choose_backup(&mut self) -> Result<(), Failure> {
        let directory = self.bundle.join("backups");
        if !directory.is_dir() {
            return Ok(());
        }

        let mut backups: Vec<PathBuf> = fs::read_dir(&directory)
            .map(|entries| {
                entries
                    .flatten()
                    .map(|entry| entry.path())
                    .filter(|path| {
                        path.is_dir()
                            && path
                                .file_name()
                                .map(|name| is_stamp(&name.to_string_lossy()))
                                .unwrap_or(false)
                    })
                    .collect()
            })
            .unwrap_or_default();
        backups.sort();
        backups.reverse();

        if backups.is_empty() {
            return Ok(());
        }

        println!();
        println!("Available backups to restore from:");
        for (index, backup) in backups.iter().enumerate() {
            let mut tag = String::new();
            if konsave_archive(backup).is_none() {
                tag.push_str("");
            } else {
                tag.push_str(" [konsave]");
            }
            if let Some(previous) = read_line(&backup.join("previous_shell.txt")) {
                tag.push_str(&format!(
                    " [Shell: {}]",
                    Path::new(&previous)
                        .file_name()
                        .map(|name| name.to_string_lossy().to_string())
                        .unwrap_or(previous.clone())
                ));
            }
            println!("  {}) {}{tag}", index + 1, pretty_stamp(backup));
        }
        println!("  0) None (Do not restore from backup)");

        loop {
            let answer = prompt("Select a backup to restore [1]:");
            let answer = if answer.trim().is_empty() {
                "1".to_string()
            } else {
                answer.trim().to_string()
            };

            if answer == "0" {
                return Ok(());
            }

            let Ok(choice) = answer.parse::<usize>() else {
                println!("Invalid selection.");
                continue;
            };
            if choice < 1 || choice > backups.len() {
                println!("Invalid selection.");
                continue;
            }

            let selected = backups[choice - 1].clone();
            let archive = konsave_archive(&selected);

            // A konsave archive restores the KDE profile but is not a clean desktop either, so
            // the warning runs for both kinds of backup.
            if selected
                .join(".config")
                .join("quickshell")
                .join("caelestia")
                .join("shell.qml")
                .is_file()
            {
                println!();
                output::warn("The selected backup contains Caelestia configurations.");
                println!("   Restoring this backup will NOT revert to a clean KDE desktop!");
                println!("    Instead, it will restore a previous Caelestia state.");
                if !asked("Are you sure you want to restore this backup?") {
                    println!("  Backup selection canceled. Please select again.");
                    continue;
                }
            }

            self.backup = Some(selected);
            self.konsave_archive = archive;
            if let Some(previous) = read_line(
                &self
                    .backup
                    .clone()
                    .unwrap()
                    .join("previous_lookandfeel.txt"),
            ) {
                self.previous_lookandfeel = previous;
            }
            return Ok(());
        }
    }

    fn restore_or_remove(&self, name: &str, target: &Path, backup_subdir: &str) {
        let backup_path = self
            .backup
            .as_ref()
            .map(|backup| backup.join(backup_subdir).join(name))
            .filter(|path| path.exists());

        // A single item the installer owned can be dropped; a whole directory cannot, because
        // these are shared user configs the user keeps editing after install - deleting one
        // because no backup exists destroys work that has nothing to do with Caelestia.
        if backup_path.is_none() && target.is_dir() {
            output::skip(&format!(
                "No backup for {name} - left in place (remove {} manually if you want it gone)",
                target.display()
            ));
            return;
        }

        let existed = target.exists();
        if existed {
            let _ = remove_tree(target);
        }

        match backup_path {
            Some(backup) => {
                if copy_tree(&backup, target) {
                    output::ok(&format!("Restored {name} from backup"));
                } else {
                    output::warn(&format!(
                        "Failed to restore {name} from backup - {} is now missing",
                        target.display()
                    ));
                }
            }
            None => output::skip(&format!("No backup for {name} - removed without restore")),
        }
    }

    fn stop_services(&self) {
        section("Step 1 - Stop and Disable Services");

        for service in [
            "qs-kwin-bridge",
            "cliphist",
            "ydotoold",
            "kde-material-you-colors",
        ] {
            let unit = format!("{service}.service");
            if unit_is_enabled_or_active(&unit) {
                let _ =
                    process::succeeds("systemctl", &["--user", "disable", "--now", &unit], None);
                output::ok(&format!("Disabled user service: {service}"));
            } else {
                output::skip(&format!("User service not active: {service}"));
            }
        }

        if unit_is_enabled_or_active("caelestia-update-checker.timer") {
            let _ = process::succeeds(
                "systemctl",
                &[
                    "--user",
                    "disable",
                    "--now",
                    "caelestia-update-checker.timer",
                ],
                None,
            );
            let _ = process::succeeds(
                "systemctl",
                &[
                    "--user",
                    "disable",
                    "--now",
                    "caelestia-update-checker.service",
                ],
                None,
            );
            output::ok("Disabled user timer: caelestia-update-checker");
        }

        if system_unit_is_enabled_or_active("keyd") {
            let _ = privileges::elevated("systemctl", &["disable", "--now", "keyd"], None);
            output::ok("Disabled system service: keyd");
        } else {
            output::skip("keyd not active");
        }

        let _ = process::succeeds("pkill", &["-f", "caelestia shell"], None);
        let _ = process::succeeds("pkill", &["-f", "quickshell.*caelestia"], None);
        output::ok("Stopped any running shell processes");
    }

    fn remove_service_files(&self) {
        section("Step 2 - Remove Service and Autostart Files");

        let systemd = self.path(".config/systemd/user");
        for service in [
            "qs-kwin-bridge.service",
            "cliphist.service",
            "ydotoold.service",
            "kde-material-you-colors.service",
            "caelestia-update-checker.service",
            "caelestia-update-checker.timer",
        ] {
            let path = systemd.join(service);
            if path.is_file() && fs::remove_file(&path).is_ok() {
                output::ok(&format!("Removed: {}", path.display()));
            }
        }

        let _ = process::succeeds(
            "systemctl",
            &["--user", "disable", "--now", "caelestia-shell.service"],
            None,
        );
        let shell_unit = systemd.join("caelestia-shell.service");
        if shell_unit.is_file() && fs::remove_file(&shell_unit).is_ok() {
            output::ok("Removed: caelestia-shell.service");
        }

        // A wants/ link whose unit is gone is what an old install leaves behind: the link
        // survives the unit being replaced by the autostart entry.
        if let Ok(entries) = fs::read_dir(&systemd) {
            for wants in entries.flatten().filter(|entry| {
                entry.path().is_dir() && entry.file_name().to_string_lossy().ends_with(".wants")
            }) {
                let link = wants.path().join("caelestia-shell.service");
                if fs::symlink_metadata(&link).is_ok()
                    && !link.exists()
                    && fs::remove_file(&link).is_ok()
                {
                    output::ok(&format!(
                        "Removed an enable link whose unit is gone: {}",
                        link.display()
                    ));
                }
            }
        }

        let autostart = self.path(".config/autostart/caelestiashell.desktop");
        if autostart.is_file() {
            let _ = process::succeeds(
                "systemctl",
                &["--user", "disable", "app-caelestiashell@autostart.service"],
                None,
            );
            let _ = fs::remove_file(&autostart);
            output::ok("Removed the retired autostart entry: caelestiashell.desktop");
        }

        let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
    }

    fn remove_shell_installation(&self) {
        section("Step 3 - Remove Shell Installation");

        for relative in [
            ".config/quickshell/caelestia",
            ".local/lib/caelestia",
            ".local/share/caelestia-shell",
            ".local/share/caelestia",
        ] {
            let path = self.path(relative);
            if path.is_dir() && remove_tree(&path) {
                output::ok(&format!("Removed {}", display_home(&path, &self.home)));
            }
        }

        // Only the entry the installer wrote: the file names the Wayland interfaces the shell
        // needs, and another shell's desktop file does not.
        for name in ["quickshell.desktop", "org.quickshell.desktop"] {
            let path = self.path(".local/share/applications").join(name);
            if path.is_file() && file_mentions(&path, "X-KDE-Wayland-Interfaces") {
                let _ = fs::remove_file(&path);
                output::ok(&format!("Removed ~/.local/share/applications/{name}"));
            }
        }

        for module in ["Caelestia", "M3Shapes"] {
            let path = self.path(".local/lib/qt6/qml").join(module);
            if path.is_dir() && remove_tree(&path) {
                output::ok(&format!("Removed QML module: {module}"));
            }
        }
    }

    fn remove_shell_state(&self) {
        section("Step 3b - Remove Shell State");

        for name in ["stolen-shortcuts.json", "stolen-screen-edges.json"] {
            let path = self.path(".config/caelestia").join(name);
            if path.is_file() && fs::remove_file(&path).is_ok() {
                output::ok(&format!(
                    "Removed stranded recovery file: ~/.config/caelestia/{name}"
                ));
            }
        }
        let _ = fs::remove_file(self.path(".config/caelestia/status_icons_order.txt"));

        for relative in [".cache/Caelestia", ".cache/caelestia-shell"] {
            let path = self.path(relative);
            if path.is_dir() && remove_tree(&path) {
                output::ok(&format!("Removed {}", path.display()));
            }
        }

        for (relative, message) in [
            (".config/Caelestia", "Removed legacy ~/.config/Caelestia"),
            (
                ".local/share/plasma/shells/caelestia.desktop",
                "Removed ~/.local/share/plasma/shells/caelestia.desktop",
            ),
        ] {
            let path = self.path(relative);
            if path.is_dir() && remove_tree(&path) {
                output::ok(message);
            }
        }

        if process::available("kpackagetool6") {
            let _ = process::succeeds(
                "kpackagetool6",
                &[
                    "-t",
                    "Plasma/Wallpaper",
                    "-r",
                    "net.dosowisko.PlasmaApplicationWallpaper",
                ],
                None,
            );
        }

        let wallpaper = self
            .path(".local/share/plasma/wallpapers")
            .join("net.dosowisko.PlasmaApplicationWallpaper");
        if wallpaper.is_dir() && remove_tree(&wallpaper) {
            output::ok("Removed Plasma wallpaper plugin: net.dosowisko.PlasmaApplicationWallpaper");
        }

        let _ = fs::remove_file(
            paths::cache_dir()
                .join("caelestia-kde")
                .join("wallpaper-plugin-installed"),
        );
    }

    fn remove_bridge_scripts(&self) {
        section("Step 4 - Remove Bridge Scripts");

        let bin = self.path(".local/bin");
        if let Ok(entries) = fs::read_dir(self.bundle.join("src").join("bin")) {
            for entry in entries.flatten() {
                let target = bin.join(entry.file_name());
                if target.is_file() && fs::remove_file(&target).is_ok() {
                    output::ok(&format!("Removed: {}", target.display()));
                }
            }
        }

        for name in [
            "kcolorpicker",
            "qs-kwin-bridge.py",
            "caelestia-shortcuts",
            "caelestia-keyd-run",
            "ydotoold-wrapper",
            "caelestia-autostart.sh",
            "caelestia-cliphist",
        ] {
            let target = bin.join(name);
            if target.is_file() && fs::remove_file(&target).is_ok() {
                output::ok(&format!("Removed: {}", target.display()));
            }
        }

        let script = self.path(".local/share/kwin/scripts/quickshell-kde-bridge");
        if script.is_dir() && remove_tree(&script) {
            output::ok("Removed KWin script: quickshell-kde-bridge");
        }
    }

    fn restore_or_remove_configs(&self) {
        section("Step 5 - Restore or Remove Config Directories");

        for config in [
            "btop",
            "fastfetch",
            "fish",
            "foot",
            "kitty",
            "micro",
            "thunar",
        ] {
            let path = self.path(".config").join(config);
            if path.exists() {
                self.restore_or_remove(config, &path, ".config");
            }
        }

        let starship = self.path(".config/starship.toml");
        if starship.is_file() {
            self.restore_or_remove("starship.toml", &starship, ".config");
        }
    }

    fn revert_kde_settings(&mut self) {
        section("Step 6 - Revert KDE Settings");

        for (file, groups, key) in [
            ("plasmarc", &["OSD"][..], "Enabled"),
            ("plasmarc", &["OSD"][..], "ShowOnActiveScreen"),
        ] {
            kwrite(file, groups, key, "true");
        }
        kwrite("kdeglobals", &["KDE"], "OSDEnabled", "true");
        kwrite(
            "plasmanotifyrc",
            &["Notifications"],
            "LoudnessChangedOSD",
            "true",
        );
        kwrite("powerdevilrc", &["BrightnessControl"], "showOSD", "true");
        kwrite("powerdevilrc", &["AC"], "brightnessosd", "true");
        kwrite("kmixrc", &["Global"], "ShowOSD", "true");
        output::ok("Re-enabled KDE OSD notifications");

        if let Some(archive) = self.konsave_archive.clone() {
            if self.ensure_konsave() {
                output::info("Restoring KDE settings from konsave archive...");
                let bin = self.konsave.clone().unwrap_or_default();
                let bin = bin.to_string_lossy().to_string();
                let archive = archive.to_string_lossy().to_string();
                if process::run_visible(&bin, &["-i", &archive], None) == Some(0)
                    && process::run_visible(&bin, &["-a", "caelestia-preinstall"], None) == Some(0)
                {
                    self.theme_restored = true;
                    output::ok("Restored KDE settings from konsave backup.");
                } else {
                    output::warn("konsave restore failed, falling back to manual restore paths.");
                    self.konsave_archive = None;
                }
            } else {
                output::warn("konsave is unavailable, falling back to manual restore paths.");
                self.konsave_archive = None;
            }
        }

        if self.konsave_archive.is_none() {
            self.restore_core_kde_configs();
        }

        // The desktop the installer replaced is only rebuilt when there is no backup to restore
        // it from, and only while a Plasma session is there to be told about it.
        if !self.theme_restored
            && process::succeeds("pgrep", &["-x", "plasmashell"], None)
            && let Some(qdbus) = process::locate("qdbus6").or_else(|| process::locate("qdbus"))
        {
            let qdbus = qdbus.to_string_lossy().to_string();
            if process::succeeds(
                &qdbus,
                &[
                    "org.kde.plasmashell",
                    "/PlasmaShell",
                    "evaluateScript",
                    STOCK_PANEL,
                ],
                None,
            ) {
                output::ok("Created a default bottom panel (no backup was available)");
            } else {
                output::warn(
                    "Could not create a default panel. Add one via Edit Mode if the desktop is empty.",
                );
            }
        }

        for (key, value) in [
            ("quickshell-kde-bridgeEnabled", "false"),
            ("krohnkiteEnabled", "false"),
            ("kwin_workspace_trackerEnabled", "false"),
        ] {
            kwrite("kwinrc", &["Plugins"], key, value);
        }
        output::ok(
            "Disabled KWin plugins: quickshell-kde-bridge, krohnkite, kwin_workspace_tracker",
        );

        for (group, key) in [
            ("caelestia-opacity", "Description"),
            ("caelestia-opacity", "types"),
            ("caelestia-opacity", "opacityinactive"),
            ("caelestia-opacity", "opacityinactiverule"),
            ("caelestia-dialogs", "Description"),
            ("caelestia-dialogs", "types"),
            ("caelestia-dialogs", "placement"),
            ("caelestia-dialogs", "placementrule"),
            ("caelestia-pip", "Description"),
            ("caelestia-pip", "title"),
            ("caelestia-pip", "titlematch"),
            ("caelestia-pip", "aboverule"),
        ] {
            kwrite_delete("kwinrulesrc", &[group], key);
        }
        self.prune_window_rules();

        kwrite_delete("plasmashellrc", &["Shell"], "ShellPackage");
        kwrite(
            "kscreenlockerrc",
            &["Greeter"],
            "Theme",
            "org.kde.breeze.desktop",
        );
        kwrite(
            "kscreenlockerrc",
            &["Greeter"],
            "WallpaperPlugin",
            "org.kde.image",
        );
        for (groups, key) in [
            (
                [
                    "Greeter",
                    "Wallpaper",
                    "net.dosowisko.PlasmaApplicationWallpaper",
                    "General",
                ],
                "command",
            ),
            (
                [
                    "Greeter",
                    "Wallpaper",
                    "net.dosowisko.PlasmaApplicationWallpaper",
                    "General",
                ],
                "fps",
            ),
        ] {
            kwrite_delete("kscreenlockerrc", &groups, key);
        }
        kwrite_delete(
            "kscreenlockerrc",
            &["Greeter", "LnF", "General"],
            "alwaysShowClock",
        );
        kwrite_delete(
            "kscreenlockerrc",
            &["Greeter", "LnF", "General"],
            "showMediaControls",
        );
        output::ok("Restored stock KDE lock screen configuration.");

        if !self.theme_restored {
            kwrite("kwinrc", &["Desktops"], "Number", "1");
            kwrite("kwinrc", &["Desktops"], "Rows", "1");
            for index in 1..=5 {
                kwrite(
                    "kwinrc",
                    &["Desktops"],
                    &format!("Name_{index}"),
                    &format!("Desktop {index}"),
                );
            }
            output::ok("Restored desktop count to 1");
        }

        for index in 1..=5 {
            kwrite(
                "kglobalshortcutsrc",
                &["kwin"],
                &format!("Switch to Desktop {index}"),
                &format!("none,none,Switch to Desktop {index}"),
            );
            kwrite(
                "kglobalshortcutsrc",
                &["kwin"],
                &format!("Window to Desktop {index}"),
                &format!("none,none,Move Window to Desktop {index}"),
            );
        }
        output::ok("Cleared installer workspace shortcuts from kglobalshortcutsrc");

        if let Some(backup) = &self.backup {
            let shortcuts = backup.join(".config/kglobalshortcutsrc");
            if shortcuts.is_file()
                && copy_file(&shortcuts, &self.path(".config/kglobalshortcutsrc"))
            {
                output::ok("Restored kglobalshortcutsrc from backup");
            }
        }

        for scheme in [
            "MaterialYou.colorscheme",
            "MaterialYouAlt.colorscheme",
            "TempMyou.profile",
        ] {
            let _ = fs::remove_file(self.path(".local/share/konsole").join(scheme));
        }
        for (directory, prefixes) in [(".local/share/color-schemes", ["MaterialYou", "Matugen"])] {
            for prefix in prefixes {
                remove_by_prefix(&self.path(directory), prefix);
            }
        }
        output::ok("Removed Konsole profiles generated by Caelestia");

        self.revert_darkly_gtk();
    }

    fn restore_core_kde_configs(&mut self) {
        let Some(backup) = self.backup.clone() else {
            self.reset_theme_to_breeze();
            return;
        };

        output::info("Restoring core KDE configuration files from backup...");
        let mut restored = 0;
        for config in [
            "kdeglobals",
            "ksplashrc",
            "plasmarc",
            "kwinrc",
            "kwinrulesrc",
            "kcminputrc",
            "plasma-org.kde.plasma.desktop-appletsrc",
        ] {
            let source = backup.join(".config").join(config);
            if source.is_file() && copy_file(&source, &self.path(".config").join(config)) {
                restored += 1;
            }
        }

        if restored > 0 {
            self.theme_restored = true;
            output::ok(&format!(
                "Restored {restored} core KDE configuration file(s) from backup (including wallpaper and splash when present)."
            ));
        } else {
            output::warn(
                "Selected backup did not contain expected core KDE config files. Falling back to Breeze defaults.",
            );
            self.reset_theme_to_breeze();
        }
    }

    fn reset_theme_to_breeze(&self) {
        output::info("No theme backup found. Reverting to default Breeze theme...");
        kwrite("plasmarc", &["Theme"], "name", "default");
        kwrite("kdeglobals", &["KDE"], "widgetStyle", "Breeze");
        kwrite("kdeglobals", &["General"], "ColorScheme", "BreezeLight");
        kwrite(
            "kwinrc",
            &["org.kde.kdecoration2"],
            "library",
            "org.kde.breeze",
        );
        kwrite("kwinrc", &["org.kde.kdecoration2"], "theme", "@breeze");
        kwrite("kcminputrc", &["Mouse"], "cursorTheme", "breeze_cursors");
        output::ok("Reset KDE theme settings to Breeze.");
    }

    // The rules index is a comma-separated list of group names: ours come out of it and every
    // other rule keeps its place.
    fn prune_window_rules(&self) {
        let ours = ["caelestia-opacity", "caelestia-dialogs", "caelestia-pip"];
        let Some(index) = kde_read("kwinrulesrc", &["General"], "rules") else {
            return;
        };

        let kept: Vec<String> = index
            .split(',')
            .map(|name| name.trim().to_string())
            .filter(|name| !name.is_empty() && !ours.contains(&name.as_str()))
            .collect();

        if !kept.is_empty() {
            kwrite("kwinrulesrc", &["General"], "rules", &kept.join(","));
            kwrite(
                "kwinrulesrc",
                &["General"],
                "count",
                &kept.len().to_string(),
            );
        } else {
            kwrite_delete("kwinrulesrc", &["General"], "rules");
            kwrite_delete("kwinrulesrc", &["General"], "count");
        }
        output::ok("Removed the Caelestia window rules from kwinrulesrc");
    }

    fn revert_darkly_gtk(&self) {
        let theme = paths::data_home().join("themes").join("Darkly");
        if theme.is_dir() {
            output::info(&format!(
                "Leaving {} in place (delete manually if you want).",
                theme.display()
            ));
        }

        for name in ["Darkly", "darkly"] {
            let _ = fs::remove_file(paths::data_home().join("plasma/desktoptheme").join(name));
        }

        let gtk4 = paths::config_dir().join("gtk-4.0");
        let backup = gtk4.join("gtk.css.created_by_darkly_installer.bak");
        if backup.is_file() {
            let _ = fs::rename(&backup, gtk4.join("gtk.css"));
        }

        if gtk4.join("gtk-darkly.css").is_file() || gtk4.join("darkly-gtk-assets").is_dir() {
            let _ = fs::remove_file(gtk4.join("gtk-darkly.css"));
            let _ = remove_tree(&gtk4.join("darkly-gtk-assets"));
            output::ok("Removed Darkly GTK libadwaita files");
        }

        if let Some(backup) = &self.backup {
            let konsolerc = backup.join(".config/konsolerc");
            if konsolerc.is_file() && copy_file(&konsolerc, &self.path(".config/konsolerc")) {
                output::ok("Restored konsolerc from backup");
            }
            let konsole = backup.join("local/konsole");
            if konsole.is_dir() {
                let _ = remove_tree(&self.path(".local/share/konsole"));
                if copy_tree(&konsole, &self.path(".local/share/konsole")) {
                    output::ok("Restored ~/.local/share/konsole from backup");
                }
            }
        }
    }

    fn revert_shell_changes(&mut self) {
        section("Step 7 - Revert Shell Changes");

        if self.backup.is_some() {
            for (key, relative) in [
                ("bashrc", ".bashrc"),
                ("zshrc", ".zshrc"),
                ("fish_config", ".config/fish/config.fish"),
            ] {
                if self.restore_shell_rc(key, &self.path(relative)) {
                    self.shell_rc_restored = true;
                }
            }
        }

        self.revert_login_shell();

        if self.shell_rc_restored {
            output::info(
                "Skipped shell rc line cleanup because original rc files were restored exactly from backup.",
            );
        } else {
            for (relative, prefixes) in [
                (".bashrc", &["export"][..]),
                (".zshrc", &["export"][..]),
                (".config/fish/config.fish", &["set -gx", "set -x"][..]),
            ] {
                let rc = self.path(relative);
                if rc.is_file() && strip_caelestia_env(&rc, prefixes) {
                    output::ok(&format!("Removed Caelestia env vars from {}", rc.display()));
                }
            }
        }

        let environment = self.path(".config/environment.d/caelestia.conf");
        if environment.is_file() && fs::remove_file(&environment).is_ok() {
            output::ok("Removed the Caelestia environment file");
        }

        let plasma_env = self.path(".config/plasma-workspace/env/caelestia.sh");
        if plasma_env.is_file() {
            let _ = fs::remove_file(&plasma_env);
            let _ = fs::remove_dir(self.path(".config/plasma-workspace/env"));
            output::ok("Removed the Caelestia Plasma session environment script");
        }
    }

    // What the install recorded about each rc file: it was there before (and is in the backup),
    // or it was not, in which case the installer's own file goes.
    fn restore_shell_rc(&self, key: &str, target: &Path) -> bool {
        let Some(backup) = &self.backup else {
            return false;
        };

        let state_file = backup.join("shellrc").join(format!("{key}.state"));
        let Ok(state) = fs::read_to_string(&state_file) else {
            return false;
        };

        match state.trim() {
            "present" => {
                let backup_file = backup.join("shellrc").join(key);
                if backup_file.is_file() && copy_file(&backup_file, target) {
                    output::ok(&format!("Restored {} from backup", target.display()));
                    return true;
                }
                false
            }
            "missing" => {
                let _ = fs::remove_file(target);
                output::ok(&format!(
                    "Removed {} (it did not exist before install)",
                    target.display()
                ));
                true
            }
            _ => false,
        }
    }

    fn revert_login_shell(&self) {
        let recorded = self
            .backup
            .as_ref()
            .and_then(|backup| read_line(&backup.join("previous_shell.txt")));

        let Some(recorded) = recorded else {
            // Nothing recorded means the install never changed it, so the shell it has now is
            // the user's own and is left alone.
            if let Some(current) = login_shell() {
                output::info(&format!(
                    "No shell backup was recorded, so the login shell ({current}) is left as it is."
                ));
            }
            return;
        };

        let restore = if shell_is_registered(&recorded) {
            recorded.clone()
        } else {
            output::warn(&format!(
                "Previous shell ({recorded}) is not listed in /etc/shells. Falling back to bash."
            ));
            bash_path()
        };

        let user = user_name();
        if privileges::elevated("chsh", &["-s", &restore, &user], None) == Ok(0) {
            output::ok(&format!("Login shell reverted to {restore}"));
        } else {
            output::warn(&format!(
                "Could not change login shell to {restore}. Run: chsh -s {restore}"
            ));
        }
    }

    fn ensure_konsave(&mut self) -> bool {
        if let Some(binary) = process::locate("konsave") {
            self.konsave = Some(binary);
            return true;
        }

        if !process::available("python3") {
            return false;
        }

        output::info("Installing konsave for KDE profile restore...");
        let venv = paths::cache_dir()
            .join("caelestia-kde")
            .join("konsave-venv");
        let binary = venv.join("bin").join("konsave");

        if !binary.is_file() {
            if !process::succeeds("python3", &["-m", "venv", &venv.to_string_lossy()], None) {
                return false;
            }
            let python = venv.join("bin").join("python");
            let python = python.to_string_lossy().to_string();
            let _ = process::succeeds(&python, &["-m", "pip", "install", "--upgrade", "pip"], None);
            if !process::succeeds(
                &python,
                &["-m", "pip", "install", "--upgrade", "konsave"],
                None,
            ) {
                return false;
            }
        }

        self.konsave = Some(binary.clone());
        binary.is_file()
    }

    fn remove_system_files(&self) {
        section("Step 8 - Remove System-level Files");

        for (path, message) in [
            (
                "/etc/keyd/quickshell.conf",
                "Removed /etc/keyd/quickshell.conf",
            ),
            (
                "/usr/share/sddm/themes/caelestia",
                "Removed SDDM theme: /usr/share/sddm/themes/caelestia",
            ),
        ] {
            let target = Path::new(path);
            if !target.exists() {
                continue;
            }
            if sudo_remove(target, target.is_dir()) {
                output::ok(message);
            }
            if path == "/etc/keyd/quickshell.conf" {
                let _ = privileges::elevated("rmdir", &["/etc/keyd"], None);
            }
        }

        for rule in [
            "/etc/udev/rules.d/70-uinput.rules",
            "/etc/udev/rules.d/80-uinput.rules",
        ] {
            let target = Path::new(rule);
            if target.is_file() && sudo_remove(target, false) {
                let _ = privileges::elevated("udevadm", &["control", "--reload-rules"], None);
                output::ok(&format!(
                    "Removed udev rule: {}",
                    target.file_name().unwrap_or_default().to_string_lossy()
                ));
            }
        }

        self.revert_ccache_flag();
        self.restore_login_screen();

        for target in [
            "/usr/local/bin/caelestia-greeter-sync",
            "/usr/local/bin/sass",
            "/usr/local/bin/qdbus6",
            "/usr/local/bin/caelestia",
            "/usr/local/bin/wl-clip-persist",
            "/usr/local/bin/gpu-screen-recorder",
        ] {
            let path = Path::new(target);
            let is_link = fs::symlink_metadata(path)
                .map(|meta| meta.file_type().is_symlink())
                .unwrap_or(false);
            if (is_link || (target == "/usr/local/bin/caelestia-greeter-sync" && path.is_file()))
                && sudo_remove(path, false)
            {
                output::ok(&format!("Removed: {target}"));
            }
        }

        for library in [
            "/usr/lib/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so",
            "/usr/lib64/qt6/plugins/kwin/effects/plugins/kwin_workspace_tracker.so",
        ] {
            let path = Path::new(library);
            if path.is_file() && sudo_remove(path, false) {
                output::ok(&format!("Removed system KWin effect: {library}"));
            }
        }

        self.remove_posthooks();
        let _ = fs::remove_file(self.path(".config/caelestia/templates/sddm-theme.conf"));
        self.leave_input_group();
    }

    fn revert_ccache_flag(&self) {
        let flag = paths::state_dir().join("caelestia/ccache-enabled");
        if !flag.is_file() || !Path::new("/etc/makepkg.conf").is_file() {
            return;
        }

        let reverted = privileges::elevated(
            "sed",
            &[
                "-i",
                "s/\\(^\\|[[:space:]]\\)ccache\\([[:space:]]\\|$\\)/\\1!ccache\\2/",
                "/etc/makepkg.conf",
            ],
            None,
        ) == Ok(0);

        if reverted {
            let _ = fs::remove_file(&flag);
            output::ok("Reverted ccache in /etc/makepkg.conf");
        } else {
            output::warn(
                "Could not revert ccache in /etc/makepkg.conf; retaining ownership marker.",
            );
        }
    }

    // The login screen is a system configuration, so what the install changed there is put
    // back: the theme selection it recorded, the drop-ins it wrote, and its sync helper.
    fn restore_login_screen(&self) {
        for rule in [
            "/etc/sudoers.d/ydotoold-nopasswd",
            "/etc/sudoers.d/caelestia-sddm-sync",
        ] {
            let path = Path::new(rule);
            if path.is_file() && sudo_remove(path, false) {
                output::ok(&format!(
                    "Removed sudoers rule: {}",
                    path.file_name().unwrap_or_default().to_string_lossy()
                ));
            }
        }

        for dropin in [
            "/etc/sddm.conf.d/caelestia.conf",
            "/etc/sddm.conf.d/zz-caelestia.conf",
        ] {
            let path = Path::new(dropin);
            if path.is_file() && sudo_remove(path, false) {
                output::ok(&format!(
                    "Removed SDDM config drop-in: {}",
                    path.file_name().unwrap_or_default().to_string_lossy()
                ));
            }
        }

        let recorded = paths::state_dir().join("caelestia/sddm.conf.theme-current");
        if process::available("kwriteconfig6") {
            if let Some(previous) = read_line(&recorded) {
                let arguments: Vec<&str> = if previous == "#none" {
                    vec![
                        "--file",
                        "/etc/sddm.conf",
                        "--group",
                        "Theme",
                        "--key",
                        "Current",
                        "--delete",
                    ]
                } else {
                    vec![
                        "--file",
                        "/etc/sddm.conf",
                        "--group",
                        "Theme",
                        "--key",
                        "Current",
                        &previous,
                    ]
                };
                let _ = privileges::elevated("kwriteconfig6", &arguments, None);
                if previous == "#none" {
                    output::ok("Removed the login screen theme selection from /etc/sddm.conf");
                } else {
                    output::ok(&format!(
                        "Restored the login screen theme in /etc/sddm.conf ({previous})"
                    ));
                }
                let _ = fs::remove_file(&recorded);
            } else if kde_read("/etc/sddm.conf", &["Theme"], "Current").as_deref()
                == Some("caelestia")
            {
                let _ = privileges::elevated(
                    "kwriteconfig6",
                    &[
                        "--file",
                        "/etc/sddm.conf",
                        "--group",
                        "Theme",
                        "--key",
                        "Current",
                        "--delete",
                    ],
                    None,
                );
                output::ok("Removed the login screen theme selection from /etc/sddm.conf");
            }
        }

        if Path::new("/etc/plasmalogin.conf").is_file() && process::available("kwriteconfig6") {
            let _ = privileges::elevated(
                "kwriteconfig6",
                &[
                    "--file",
                    "/etc/plasmalogin.conf",
                    "--group",
                    "Greeter",
                    "--group",
                    "Wallpaper",
                    "--group",
                    "org.kde.image",
                    "--group",
                    "General",
                    "--key",
                    "Image",
                    "--delete",
                ],
                None,
            );
            output::ok("Removed the login screen wallpaper from /etc/plasmalogin.conf");
        }

        let home = passwd_home("plasmalogin");
        if let Some(home) = home.filter(|home| home != "/") {
            let home = PathBuf::from(home);
            let wallpapers = home.join("wallpapers/caelestia");
            if wallpapers.is_dir() && sudo_remove(&wallpapers, true) {
                output::ok("Removed the login screen's copy of the wallpaper");
            }
            for file in [
                "kdeglobals",
                "plasmarc",
                "kxkbrc",
                "kcminputrc",
                "plasma-localerc",
            ] {
                let path = home.join(".config").join(file);
                if path.is_file() {
                    let _ = sudo_remove(&path, false);
                }
            }
            let schemes = home.join(".local/share/color-schemes");
            if schemes.is_dir() {
                remove_by_prefix(&schemes, "Matugen");
                output::ok("Removed the login screen's copies of the color schemes");
            }
        }
    }

    fn remove_posthooks(&self) {
        let cli = self.path(".config/caelestia/cli.json");
        if !cli.is_file() || !process::available("python3") {
            return;
        }

        let target = cli.to_string_lossy().to_string();
        let mut command = std::process::Command::new("python3");
        command
            .args(["-", &target])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());

        let Ok(mut child) = command.spawn() else {
            return;
        };
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(POSTHOOK_CLEANER.as_bytes());
        }
        if child.wait().map(|status| status.success()).unwrap_or(false) {
            output::ok("Removed SDDM posthooks from cli.json");
        }
    }

    fn leave_input_group(&self) {
        let user = user_name();
        let Some(groups) = process::capture("groups", &[&user]) else {
            return;
        };
        if !groups.split_whitespace().any(|group| group == "input") {
            return;
        }

        if privileges::elevated("gpasswd", &["-d", &user, "input"], None) == Ok(0) {
            output::ok(&format!(
                "Removed {user} from 'input' group (takes effect on next login)"
            ));
        } else {
            output::warn(&format!(
                "Could not remove the user from input group. Run: sudo gpasswd -d {user} input"
            ));
        }
    }

    fn remove_packages(&self) {
        if !self.remove_packages {
            output::skip("Package removal skipped (user chose to keep packages)");
            return;
        }

        section("Step 9 - Remove Packages (Optional)");

        let listed: &[&str] = match self.family {
            Distro::Arch => ARCH_PACKAGES,
            Distro::Fedora => FEDORA_PACKAGES,
            Distro::Debian => DEBIAN_PACKAGES,
            Distro::Unknown => &[],
        };

        let installed: Vec<&str> = listed
            .iter()
            .copied()
            .filter(|package| pkg::present(package))
            .collect();

        if !listed.is_empty() {
            self.remove_selected_packages(&installed);
        }

        if process::available("caelestia") {
            let _ = privileges::elevated("pip3", &["uninstall", "-y", "caelestia"], None);
            let _ = process::succeeds("pip3", &["uninstall", "-y", "caelestia"], None);
            output::ok("Removed caelestia pip package");
        }

        if process::available("uv") {
            let _ = process::succeeds(
                "uv",
                &["tool", "uninstall", "kde-material-you-colors"],
                None,
            );
            output::ok("Removed uv tools: kde-material-you-colors");
        }

        if process::available("kpackagetool6")
            && process::succeeds(
                "kpackagetool6",
                &["-t", "KWin/Script", "-s", "krohnkite"],
                None,
            )
        {
            let _ = process::succeeds(
                "kpackagetool6",
                &["-t", "KWin/Script", "-r", "krohnkite"],
                None,
            );
            output::ok("Removed Krohnkite KWin script");
        }
    }

    fn remove_selected_packages(&self, installed: &[&str]) {
        if installed.is_empty() {
            output::skip("None of the listed packages are installed");
            return;
        }

        output::warn("Packages installed by caelestia that are also common desktop tools:");
        for (index, package) in installed.iter().enumerate() {
            println!("  {:>2}) {package}", index + 1);
        }
        println!("  Enter the numbers to remove (e.g. 1 3 5-9), 'all' for every package,");
        println!("  or press Enter to keep them all.");

        let answer = prompt("Selection [keep all]:");
        let answer = answer.trim().to_lowercase();
        let selected: Vec<&str> = if answer == "all" || answer == "a" {
            installed.to_vec()
        } else {
            select_indices(installed.len(), &answer)
                .into_iter()
                .filter_map(|index| installed.get(index).copied())
                .collect()
        };

        if selected.is_empty() {
            output::skip("Package removal skipped");
            return;
        }

        let removed = match self.family {
            Distro::Arch => {
                process::run_visible(
                    "yay",
                    &{
                        let mut args = vec!["-Rns", "--noconfirm"];
                        args.extend(selected.iter().copied());
                        args
                    },
                    None,
                ) == Some(0)
            }
            Distro::Fedora => {
                privileges::elevated(
                    "dnf",
                    &{
                        let mut args = vec!["remove", "-y"];
                        args.extend(selected.iter().copied());
                        args
                    },
                    None,
                ) == Ok(0)
            }
            Distro::Debian => {
                privileges::elevated(
                    "apt-get",
                    &{
                        let mut args = vec!["remove", "-y"];
                        args.extend(selected.iter().copied());
                        args
                    },
                    None,
                ) == Ok(0)
            }
            Distro::Unknown => false,
        };

        if removed {
            output::ok(&format!("Removed {} package(s)", selected.len()));
        } else {
            output::warn("Some packages could not be removed automatically. Check manually.");
        }
    }

    fn clean_caches(&self) {
        section("Step 10 - Clean Up Cache and Build Artifacts");

        for build in ["shell/build", "shell/plugin/build"] {
            let path = self.bundle.join(build);
            if path.is_dir() && remove_tree(&path) {
                output::ok(&format!("Removed build dir: {}", path.display()));
            }
        }

        let cache = paths::cache_dir().join("caelestia-kde");
        if cache.is_dir() {
            if asked(&format!("Remove installer cache at {}?", cache.display())) {
                if remove_tree(&cache) {
                    output::ok("Removed installer cache");
                }
            } else {
                output::skip(&format!("Kept installer cache at {}", cache.display()));
            }
        }

        let state = paths::state_dir().join("caelestia");
        if state.is_dir() && remove_tree(&state) {
            output::ok(&format!("Removed {}", state.display()));
        }
    }

    fn reload_kde(&self) {
        section("Step 11 - Reload KDE");

        let _ = process::succeeds("qdbus6", &["org.kde.KWin", "/KWin", "reconfigure"], None);
        let _ = process::succeeds(
            "systemctl",
            &["--user", "restart", "plasma-kglobalaccel.service"],
            None,
        );
        let _ = process::succeeds("kbuildsycoca6", &["--noincremental"], None);

        if process::available("lookandfeeltool") {
            if !self.previous_lookandfeel.is_empty() {
                output::info(&format!(
                    "Reapplying previous KDE look-and-feel: {}",
                    self.previous_lookandfeel
                ));
                if !process::succeeds(
                    "lookandfeeltool",
                    &["--apply", &self.previous_lookandfeel],
                    None,
                ) {
                    output::warn(&format!(
                        "Could not apply {} with lookandfeeltool.",
                        self.previous_lookandfeel
                    ));
                }
            } else if self.theme_restored {
                output::info(
                    "Skipping Breeze look-and-feel apply because theme was restored from backup.",
                );
            } else {
                let _ = process::succeeds(
                    "lookandfeeltool",
                    &["--apply", "org.kde.breeze.desktop"],
                    None,
                );
            }
        }

        output::ok("KDE reloaded");
    }
}

fn section(title: &str) {
    println!();
    println!("-------------------------------------------------------------");
    println!("  {title}");
    println!("-------------------------------------------------------------");
}

// The prompt the shell version printed: the question, then the answer read from the terminal -
// or from whatever the caller piped in.
fn prompt(text: &str) -> String {
    print!("{text} ");
    let _ = std::io::stdout().flush();
    read_stdin_line()
}

fn asked(text: &str) -> bool {
    let answer = prompt(&format!("{text} [y/N]:")).trim().to_lowercase();
    answer == "y" || answer == "yes"
}

fn read_stdin_line() -> String {
    let mut line = String::new();
    let _ = std::io::stdin().lock().read_line(&mut line);
    line
}

// A number, a comma or space separated list of them, or a range: "1 3 5-9".
pub fn select_indices(count: usize, input: &str) -> Vec<usize> {
    if count == 0 {
        return Vec::new();
    }

    let mut picked: Vec<usize> = Vec::new();
    for token in input.split(|letter: char| letter == ',' || letter.is_whitespace()) {
        if token.is_empty() {
            continue;
        }

        let (from, to) = match token.split_once('-') {
            Some((from, to)) => (from, to),
            None => (token, token),
        };
        let (Ok(from), Ok(to)) = (from.parse::<usize>(), to.parse::<usize>()) else {
            continue;
        };
        if from < 1 || from > count {
            continue;
        }

        for number in from..=to.min(count) {
            let index = number - 1;
            if !picked.contains(&index) {
                picked.push(index);
            }
        }
    }

    picked.sort_unstable();
    picked
}

fn konsave_archive(backup: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(backup).ok()?;
    let mut archives: Vec<PathBuf> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file() && path.extension().map(|kind| kind == "knsv").unwrap_or(false)
        })
        .collect();
    archives.sort();
    archives.into_iter().next()
}

fn is_stamp(name: &str) -> bool {
    let (date, time) = match name.split_once('_') {
        Some(parts) => parts,
        None => return false,
    };
    date.len() == 8
        && time.len() == 6
        && date.bytes().all(|byte| byte.is_ascii_digit())
        && time.bytes().all(|byte| byte.is_ascii_digit())
}

fn pretty_stamp(backup: &Path) -> String {
    let Some(name) = backup
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
    else {
        return String::new();
    };
    let (date, time) = match name.split_once('_') {
        Some(parts) => parts,
        None => return name,
    };
    if date.len() != 8 || time.len() != 6 {
        return name;
    }
    format!(
        "{}-{}-{} {}:{}:{}",
        &date[0..4],
        &date[4..6],
        &date[6..8],
        &time[0..2],
        &time[2..4],
        &time[4..6]
    )
}

fn display_home(path: &Path, home: &Path) -> String {
    match path.strip_prefix(home) {
        Ok(relative) => format!("~/{}", relative.display()),
        Err(_) => path.display().to_string(),
    }
}

fn read_line(path: &Path) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    let text = text.trim().to_string();
    if text.is_empty() { None } else { Some(text) }
}

fn file_mentions(path: &Path, needle: &str) -> bool {
    fs::read_to_string(path)
        .map(|text| {
            text.lines()
                .any(|line| line.trim_start().starts_with(&format!("{needle}=")))
        })
        .unwrap_or(false)
}

fn remove_tree(path: &Path) -> bool {
    fs::remove_dir_all(path).is_ok()
}

fn remove_by_prefix(directory: &Path, prefix: &str) -> bool {
    let Ok(entries) = fs::read_dir(directory) else {
        return false;
    };
    let mut removed = false;
    for entry in entries.flatten() {
        if entry.file_name().to_string_lossy().starts_with(prefix) {
            let path = entry.path();
            removed |= if path.is_dir() {
                remove_tree(&path)
            } else {
                fs::remove_file(&path).is_ok()
            };
        }
    }
    removed
}

fn copy_file(source: &Path, target: &Path) -> bool {
    if let Some(parent) = target.parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::copy(source, target).is_ok()
}

fn copy_tree(source: &Path, target: &Path) -> bool {
    crate::copy::tree(source, target).is_ok()
}

fn sudo_remove(path: &Path, tree: bool) -> bool {
    let target = path.to_string_lossy().to_string();
    if tree {
        privileges::elevated("rm", &["-rf", &target], None) == Ok(0)
    } else {
        privileges::elevated("rm", &["-f", &target], None) == Ok(0)
    }
}

fn kwrite(file: &str, groups: &[&str], key: &str, value: &str) {
    let mut args = vec!["--file", file];
    for group in groups {
        args.push("--group");
        args.push(group);
    }
    args.push("--key");
    args.push(key);
    args.push(value);
    let _ = process::succeeds("kwriteconfig6", &args, None);
}

fn kwrite_delete(file: &str, groups: &[&str], key: &str) {
    let mut args = vec!["--file", file];
    for group in groups {
        args.push("--group");
        args.push(group);
    }
    args.push("--key");
    args.push(key);
    args.push("--delete");
    let _ = process::succeeds("kwriteconfig6", &args, None);
}

fn kde_read(file: &str, groups: &[&str], key: &str) -> Option<String> {
    let mut args = vec!["--file", file];
    for group in groups {
        args.push("--group");
        args.push(group);
    }
    args.push("--key");
    args.push(key);
    process::capture("kreadconfig6", &args).filter(|value| !value.is_empty())
}

fn unit_is_enabled_or_active(unit: &str) -> bool {
    process::succeeds(
        "systemctl",
        &["--user", "is-enabled", "--quiet", unit],
        None,
    ) || process::succeeds("systemctl", &["--user", "is-active", "--quiet", unit], None)
}

fn system_unit_is_enabled_or_active(unit: &str) -> bool {
    process::succeeds("systemctl", &["is-enabled", "--quiet", unit], None)
        || process::succeeds("systemctl", &["is-active", "--quiet", unit], None)
}

fn login_shell() -> Option<String> {
    let user = user_name();
    if user.is_empty() {
        return None;
    }
    process::capture("getent", &["passwd", &user])
        .and_then(|entry| entry.split(':').nth(6).map(str::to_string))
        .filter(|shell| !shell.is_empty())
}

fn shell_is_registered(shell: &str) -> bool {
    fs::read_to_string("/etc/shells")
        .map(|text| text.lines().any(|line| line.trim() == shell))
        .unwrap_or(false)
}

fn bash_path() -> String {
    process::locate("bash")
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|| "/bin/bash".to_string())
}

fn user_name() -> String {
    std::env::var("USER")
        .ok()
        .filter(|user| !user.is_empty())
        .or_else(|| process::capture("id", &["-un"]))
        .unwrap_or_default()
}

fn passwd_home(user: &str) -> Option<String> {
    process::capture("getent", &["passwd", user])
        .and_then(|entry| entry.split(':').nth(5).map(str::to_string))
        .filter(|home| !home.is_empty())
}

// The environment lines the install wrote are the only thing taken out of a shell's startup
// file: everything else in it is the user's.
fn strip_caelestia_env(rc: &Path, prefixes: &[&str]) -> bool {
    let Ok(text) = fs::read_to_string(rc) else {
        return false;
    };
    let before = text.clone();

    let kept: Vec<&str> = text
        .lines()
        .filter(|line| {
            let trimmed = line.trim_start();
            !prefixes.iter().any(|prefix| {
                trimmed.starts_with(&format!("{prefix} QML2_IMPORT_PATH"))
                    || trimmed.starts_with(&format!("{prefix} CAELESTIA_LIB_DIR"))
            }) || !trimmed.contains("caelestia")
        })
        .collect();

    let updated = format!("{}\n", kept.join("\n"));
    if updated == before {
        return false;
    }
    fs::write(rc, updated).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_selection_reads_numbers_lists_and_ranges() {
        assert_eq!(select_indices(5, "1"), [0]);
        assert_eq!(select_indices(5, "1,3"), [0, 2]);
        assert_eq!(select_indices(5, "1 3"), [0, 2]);
        assert_eq!(select_indices(5, "2-4"), [1, 2, 3]);
        assert_eq!(select_indices(5, "1 3-5,2"), [0, 1, 2, 3, 4]);
    }

    #[test]
    fn a_selection_ignores_what_it_cannot_use() {
        assert_eq!(select_indices(3, ""), Vec::<usize>::new());
        assert_eq!(select_indices(3, "0"), Vec::<usize>::new());
        assert_eq!(select_indices(3, "9"), Vec::<usize>::new());
        assert_eq!(select_indices(3, "x"), Vec::<usize>::new());
        assert_eq!(select_indices(0, "1"), Vec::<usize>::new());
    }

    #[test]
    fn a_range_stops_at_the_last_item() {
        assert_eq!(select_indices(2, "1-9"), [0, 1]);
    }

    #[test]
    fn a_backup_directory_is_the_stamp_the_installer_writes() {
        assert!(is_stamp("20260101_120000"));
        assert!(!is_stamp("20260101_12000"));
        assert!(!is_stamp("2026010_120000"));
        assert!(!is_stamp("backup"));
        assert_eq!(
            pretty_stamp(Path::new("/b/20260101_120000")),
            "2026-01-01 12:00:00"
        );
        assert_eq!(pretty_stamp(Path::new("/b/whatever")), "whatever");
    }

    #[test]
    fn an_environment_line_the_install_wrote_is_taken_out_and_the_rest_stays() {
        let work =
            crate::tmp::TempDir::new("caelestia-uninstall-test").expect("a temporary directory");
        let rc = work.path().join(".bashrc");
        fs::write(
            &rc,
            "# mine\nexport PATH=$HOME/.local/bin:$PATH\nexport QML2_IMPORT_PATH=$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia\nexport CAELESTIA_LIB_DIR=$HOME/.local/lib/caelestia\nexport EDITOR=vim\n",
        )
        .expect("a shell rc");

        assert!(strip_caelestia_env(&rc, &["export"]));
        let text = fs::read_to_string(&rc).expect("the file is still there");
        assert!(text.contains("# mine"));
        assert!(text.contains("EDITOR=vim"));
        assert!(!text.contains("QML2_IMPORT_PATH"));
        assert!(!text.contains("CAELESTIA_LIB_DIR"));
        assert!(
            !strip_caelestia_env(&rc, &["export"]),
            "a second pass has nothing to do"
        );
    }

    #[test]
    fn every_package_list_an_uninstall_offers_is_a_list_of_names() {
        for (name, list) in [
            ("arch", ARCH_PACKAGES),
            ("fedora", FEDORA_PACKAGES),
            ("debian", DEBIAN_PACKAGES),
        ] {
            assert!(!list.is_empty(), "the {name} list is empty");
            let mut sorted = list.to_vec();
            sorted.sort_unstable();
            sorted.dedup();
            assert_eq!(sorted.len(), list.len(), "{name} names a package twice");
        }
    }

    #[test]
    fn the_stock_panel_script_is_the_one_that_builds_a_panel() {
        assert!(STOCK_PANEL.contains("new Panel"));
        assert!(STOCK_PANEL.contains("org.kde.plasma.kickoff"));
    }
}
