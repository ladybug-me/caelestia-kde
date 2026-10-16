use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::copy;
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};

const OSD_SETTINGS: [(&str, &str, &str); 7] = [
    ("plasmarc", "OSD", "Enabled"),
    ("plasmarc", "OSD", "ShowOnActiveScreen"),
    ("kdeglobals", "KDE", "OSDEnabled"),
    ("plasmanotifyrc", "Notifications", "LoudnessChangedOSD"),
    ("powerdevilrc", "BrightnessControl", "showOSD"),
    ("powerdevilrc", "AC", "brightnessosd"),
    ("kmixrc", "Global", "ShowOSD"),
];

const PANEL_SCRIPT: &str = "var p = panels(); \
                            for (var i = 0; i < p.length; i++) { p[i].remove(); }";

const APPLETSRC: &str = ".config/plasma-org.kde.plasma.desktop-appletsrc";
const AVATARS: &str = "/var/lib/AccountsService/icons";
const SCHEME_TIMEOUT: u64 = 10;

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    println!("  Caelestia  Live System Tweaks");
    println!();

    disable_kde_osd();

    // Both first-install tweaks ask the same question, and the desktop count is answered
    // before either writes: configuring the desktops sets the key the question reads.
    let configured_count = configured_desktops();
    let first_install = is_first_install(context, configured_count.as_deref());

    super::ensure_five_desktops(context)?;
    remove_panels(first_install);
    no_splash_screen();
    default_shell();
    default_scheme();
    user_avatar_symlinks();
    reload_kde();

    println!();
    output::ok("All system tweaks applied.");
    println!();
    Ok(())
}

fn configured_desktops() -> Option<String> {
    process::capture(
        "kreadconfig6",
        &["--file", "kwinrc", "--group", "Desktops", "--key", "Number"],
    )
    .filter(|count| !count.is_empty())
}

// A system that already has a desktop count of its own has been installed or tweaked
// before, so the tweaks that assume a stock desktop stand down.
fn first_install(marker: Option<&str>, configured_count: Option<&str>) -> bool {
    marker == Some("1") && matches!(configured_count, None | Some("1"))
}

fn is_first_install(context: &Context, configured_count: Option<&str>) -> bool {
    first_install(
        context.variable("CAELESTIA_FRESH_INSTALL").as_deref(),
        configured_count,
    )
}

fn set(config: &str, group: &str, key: &str, value: &str) -> bool {
    process::succeeds(
        "kwriteconfig6",
        &["--file", config, "--group", group, "--key", key, value],
        None,
    )
}

fn disable_kde_osd() {
    output::info("Disabling KDE OSD popups (volume/brightness)...");

    for (config, group, key) in OSD_SETTINGS {
        let _ = set(config, group, key, "false");
    }

    output::ok("KDE OSD popups disabled.");
}

fn remove_panels(first_install: bool) {
    if !first_install {
        output::skip("Not a first install - leaving Plasma panels alone.");
        return;
    }

    println!("  Removing KDE Plasma panels...");

    if process::succeeds(
        "qdbus6",
        &[
            "org.kde.plasmashell",
            "/PlasmaShell",
            "org.kde.PlasmaShell.evaluateScript",
            PANEL_SCRIPT,
        ],
        None,
    ) {
        output::ok("KDE panels removed.");
        return;
    }

    match rewrite_panel_config(&paths::home().join(APPLETSRC)) {
        Ok(removed) => {
            println!("Removed {removed} KDE panel(s)");
            output::ok("KDE panels removed.");
        }
        Err(problem) => output::warn(&format!(
            "Failed to remove KDE panels from config: {problem}"
        )),
    }
}

fn rewrite_panel_config(path: &Path) -> Result<usize, String> {
    if !path.is_file() {
        return Ok(0);
    }

    let contents = fs::read_to_string(path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    let lines: Vec<&str> = contents.lines().collect();

    let panels = panel_containments(&lines);
    if panels.is_empty() {
        return Ok(0);
    }

    let kept = without_panels(&lines, &panels);
    let rewritten = format!("{}\n", kept.join("\n"));
    fs::write(path, rewritten)
        .map_err(|error| format!("cannot write {}: {error}", path.display()))?;
    Ok(panels.len())
}

fn containment_index(line: &str) -> Option<&str> {
    let line = line.trim();
    let index = line.strip_prefix("[Containments][")?.strip_suffix(']')?;
    (!index.is_empty() && index.bytes().all(|byte| byte.is_ascii_digit())).then_some(index)
}

fn is_group_header(line: &str) -> bool {
    let line = line.trim();
    line.starts_with('[') && line.ends_with(']')
}

fn is_a_panel(line: &str) -> bool {
    let Some((key, value)) = line.trim().split_once('=') else {
        return false;
    };
    let key = key.trim().to_ascii_lowercase();
    let value = value.trim().to_ascii_lowercase();

    match key.as_str() {
        "formfactor" => value == "2" || value == "3",
        "plugin" => value == "org.kde.plasma.panel",
        _ => false,
    }
}

// A Plasma panel is a containment whose own keys say so: a form factor of two or three, or
// the panel plugin by name.
fn panel_containments(lines: &[&str]) -> BTreeSet<String> {
    let mut panels = BTreeSet::new();
    let mut current: Option<&str> = None;

    for line in lines {
        let text = line.trim();
        if let Some(index) = containment_index(text) {
            current = Some(index);
        } else if text.starts_with("[Containments][") {
            // A key of the containment that is being read: it keeps its own group.
        } else if is_group_header(text) {
            current = None;
        } else if let Some(index) = current
            && is_a_panel(text)
        {
            panels.insert(index.to_string());
        }
    }
    panels
}

// The panel's own group and every group under it, up to the next containment.
fn without_panels(lines: &[&str], panels: &BTreeSet<String>) -> Vec<String> {
    let mut kept = Vec::new();
    let mut removing = false;

    for line in lines {
        let text = line.trim();
        if let Some(index) = containment_index(text) {
            removing = panels.contains(index);
        } else if text.starts_with("[Containments][") {
            // A sub-group of the containment: it goes or stays with its parent.
        } else if is_group_header(text) {
            removing = false;
        }
        if !removing {
            kept.push(line.to_string());
        }
    }
    kept
}

fn no_splash_screen() {
    output::info("Turning off the Plasma startup splash...");
    let _ = set("ksplashrc", "KSplash", "Engine", "none");
    output::ok("Plasma splash screen disabled.");
}

fn default_shell() {
    let target = std::env::var("DEFAULT_SHELL")
        .ok()
        .filter(|shell| !shell.is_empty())
        .unwrap_or_else(|| "fish".to_string());
    output::info(&format!("Setting default shell to {target}..."));

    let Some(shell_path) = process::locate(&target).map(|path| path.to_string_lossy().to_string())
    else {
        output::warn(&format!(
            "{target} is not installed, skipping shell change."
        ));
        return;
    };

    let user = process::capture("id", &["-un"]).unwrap_or_default();
    let current = login_shell(&user)
        .or_else(|| {
            std::env::var("SHELL")
                .ok()
                .filter(|shell| !shell.is_empty())
        })
        .unwrap_or_default();

    if current == shell_path {
        output::info(&format!(
            "Shell is already set to {shell_path}. Skipping chsh."
        ));
    } else if privileges::quiet("chsh", &["-s", &shell_path, &user], None).is_err() {
        output::warn(&format!(
            "Failed to change shell without prompting. You may need to run \
             'sudo chsh -s {shell_path} {user}' manually."
        ));
    }

    configure_konsole(&shell_path);
    output::ok("Shell configuration applied.");
}

fn login_shell(user: &str) -> Option<String> {
    let entry = process::capture("getent", &["passwd", user]).or_else(|| from_passwd_file(user))?;
    entry
        .split(':')
        .nth(6)
        .filter(|shell| !shell.is_empty())
        .map(str::to_string)
}

fn from_passwd_file(user: &str) -> Option<String> {
    fs::read_to_string("/etc/passwd")
        .ok()?
        .lines()
        .find(|line| line.split(':').next() == Some(user))
        .map(str::to_string)
}

// Konsole keeps the shell of every profile it has, so the ones that exist are updated and a
// first profile is written only when there is none to update.
fn configure_konsole(shell_path: &str) {
    let directory = paths::home().join(".local").join("share").join("konsole");
    let _ = fs::create_dir_all(&directory);

    let profiles = profile_files(&directory);
    if !profiles.is_empty() {
        for profile in profiles {
            let _ = set(&profile.to_string_lossy(), "General", "Command", shell_path);
        }
        return;
    }

    let profile = directory.join("Profile 1.profile");
    let profile = profile.to_string_lossy().to_string();
    let _ = set(&profile, "General", "Name", "Profile 1");
    let _ = set(&profile, "General", "Command", shell_path);
    let _ = set(
        &paths::home()
            .join(".config")
            .join("konsolerc")
            .to_string_lossy(),
        "Desktop Entry",
        "DefaultProfile",
        "Profile 1.profile",
    );
}

fn profile_files(directory: &Path) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .filter(|path| path.extension().and_then(|extension| extension.to_str()) == Some("profile"))
        .collect();
    files.sort();
    files
}

fn default_scheme() {
    output::info("Setting default Caelestia color scheme...");

    if process::available("caelestia") {
        let current = process::capture("caelestia", &["scheme", "get", "-n"]).unwrap_or_default();
        if !current.is_empty() && current != "dynamic" {
            output::info(&format!(
                "Keeping user-selected Caelestia color scheme ({current})."
            ));
            output::ok("Default Caelestia color scheme kept.");
            return;
        }

        let wallpaper = paths::state_dir()
            .join("caelestia")
            .join("wallpaper")
            .join("path.txt");
        if let Some(image) = fs::read_to_string(&wallpaper)
            .ok()
            .map(|image| image.trim().to_string())
            && Path::new(&image).is_file()
        {
            let _ = process::status_with_timeout(
                "caelestia",
                &["wallpaper", "-f", &image],
                SCHEME_TIMEOUT,
            );
        }
        let _ = process::status_with_timeout(
            "caelestia",
            &["scheme", "set", "-n", "dynamic"],
            SCHEME_TIMEOUT,
        );
    }
    output::ok("Default Caelestia color scheme set.");
}

fn user_avatar_symlinks() {
    let home = paths::home();
    let face_icon = home.join(".face.icon");

    if fs::symlink_metadata(&face_icon).is_ok() {
        output::info("~/.face.icon already exists. Skipping avatar setup.");
        return;
    }

    output::info("Setting up user profile picture symlinks...");

    let user = std::env::var("USER")
        .ok()
        .filter(|user| !user.is_empty())
        .or_else(|| process::capture("id", &["-un"]))
        .unwrap_or_default();
    let avatar = PathBuf::from(AVATARS).join(&user);

    if !avatar.is_file() {
        output::info(&format!(
            "No AccountsService avatar found at {}. Skipping.",
            avatar.display()
        ));
        return;
    }

    for link in [home.join(".face"), face_icon.clone()] {
        if copy::symlink(&link, &avatar).is_err() {
            output::warn(&format!("Could not link {} to the avatar.", link.display()));
            return;
        }
        output::info(&format!(
            "Linked {} -> {}",
            avatar.display(),
            link.display()
        ));
    }
    output::ok("User profile picture symlinks configured.");
}

fn reload_kde() {
    output::info("Reloading KWin and plasma-kglobalaccel...");
    let _ = process::succeeds("qdbus6", &["org.kde.KWin", "/KWin", "reconfigure"], None);
    let _ = process::succeeds(
        "systemctl",
        &["--user", "restart", "plasma-kglobalaccel.service"],
        None,
    );
    output::ok("KDE daemons reloaded.");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(text: &str) -> Vec<&str> {
        text.lines().collect()
    }

    #[test]
    fn a_containment_group_is_read_from_its_header_only() {
        assert_eq!(containment_index("[Containments][12]"), Some("12"));
        assert_eq!(containment_index("  [Containments][3]  "), Some("3"));
        assert_eq!(containment_index("[Containments][3][Applets][7]"), None);
        assert_eq!(containment_index("[Containments][]"), None);
        assert_eq!(containment_index("[Containments][abc]"), None);
        assert_eq!(containment_index("[General]"), None);
        assert_eq!(containment_index("plugin = org.kde.plasma.panel"), None);
    }

    #[test]
    fn a_panel_says_so_in_its_own_keys() {
        assert!(is_a_panel("formfactor=2"));
        assert!(is_a_panel("formfactor = 3"));
        assert!(is_a_panel("FormFactor = 2"));
        assert!(is_a_panel("plugin=org.kde.plasma.panel"));
        assert!(is_a_panel("Plugin = org.kde.plasma.Panel"));

        assert!(!is_a_panel("formfactor = 0"), "a desktop is not a panel");
        assert!(!is_a_panel("formfactor = 1"));
        assert!(!is_a_panel("formfactor = 20"));
        assert!(!is_a_panel("formfactor = 2 # bottom"));
        assert!(!is_a_panel("plugin = org.kde.plasma.folder"));
        assert!(!is_a_panel("NotAFormFactor = 2"));
        assert!(!is_a_panel("name=formfactor = 2"));
        assert!(!is_a_panel("no assignment here"));
    }

    #[test]
    fn the_panel_is_the_containment_whose_keys_say_so() {
        let config = lines(
            "[Containments][1]\n\
             plugin=org.kde.plasma.folder\n\
             \n\
             [Containments][1][Wallpaper][org.kde.image][General]\n\
             Image=file:///wall.png\n\
             \n\
             [Containments][2]\n\
             plugin=org.kde.plasma.panel\n\
             formfactor=2\n\
             \n\
             [Containments][2][Applets][3]\n\
             plugin=org.kde.plasma.systemtray\n\
             \n\
             [Containments][4]\n\
             formfactor=3\n\
             \n\
             [Containments][5]\n\
             formfactor=0\n",
        );

        let panels = panel_containments(&config);
        assert_eq!(
            panels.iter().collect::<Vec<_>>(),
            ["2", "4"],
            "the two panels, and neither the desktop nor the wallpaper containment"
        );
    }

    #[test]
    fn removing_a_panel_takes_its_sub_groups_and_leaves_the_rest() {
        let config = lines(
            "[Containments][1]\n\
             plugin=org.kde.plasma.folder\n\
             \n\
             [Containments][2]\n\
             plugin=org.kde.plasma.panel\n\
             \n\
             [Containments][2][Applets][3]\n\
             plugin=org.kde.plasma.digitalclock\n\
             \n\
             [Containments][2][Applets][3][Configuration]\n\
             \n\
             [Containments][4]\n\
             plugin=org.kde.plasma.folder\n\
             \n\
             [General]\n\
             \n\
             [ScreenMapping]\n",
        );
        let panels = panel_containments(&config);
        let kept = without_panels(&config, &panels);

        assert_eq!(
            kept,
            [
                "[Containments][1]",
                "plugin=org.kde.plasma.folder",
                "",
                "[Containments][4]",
                "plugin=org.kde.plasma.folder",
                "",
                "[General]",
                "",
                "[ScreenMapping]",
            ],
            "the panel, its applets and their configuration all go"
        );
    }

    #[test]
    fn a_config_without_a_panel_is_left_byte_for_byte() {
        let config = lines("[Containments][1]\nplugin=org.kde.plasma.folder\n");
        let panels = panel_containments(&config);

        assert!(panels.is_empty());
        assert_eq!(without_panels(&config, &panels), config);
    }

    #[test]
    fn a_rewritten_config_ends_in_one_newline() {
        let config = lines("[Containments][1]\nplugin=org.kde.plasma.panel");
        let kept = without_panels(&config, &panel_containments(&config));
        let rewritten = format!("{}\n", kept.join("\n"));

        assert_eq!(
            rewritten, "\n",
            "a file the removal emptied is still a file, not a missing one"
        );
    }

    #[test]
    fn the_first_install_answer_needs_both_the_marker_and_a_stock_desktop() {
        for (marker, count, expected) in [
            (Some("1"), None, true),
            (Some("1"), Some("1"), true),
            (Some("1"), Some("3"), false),
            (Some("1"), Some("5"), false),
            (Some("0"), None, false),
            (Some("0"), Some("1"), false),
            (None, None, false),
            (None, Some("1"), false),
        ] {
            assert_eq!(
                first_install(marker, count),
                expected,
                "marker {marker:?} with a desktop count of {count:?}"
            );
        }
    }
}
