use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::output;
use crate::paths;
use crate::process;
use crate::steps::{Context, Failure};

const PROFILE: &str = "caelestia-preinstall";

const KONSAVE_CONF: &str = r#"---
save:
    caelestia-preinstall:
        location: "$CONFIG_DIR"
        entries:
            - plasmarc
            - kdeglobals
            - kwinrc
            - kwinrulesrc
            - kcminputrc
            - plasmanotifyrc
            - powerdevilrc
            - kglobalshortcutsrc
            - kmixrc
            - ksplashrc
            - plasma-org.kde.plasma.desktop-appletsrc
            - konsolerc
export:
    caelestia-preinstall:
        location: "$SHARE_DIR"
        entries:
            - konsole
...
"#;

pub fn run(context: &Context) -> Result<(), Failure> {
    let home = paths::home();
    let cache = paths::cache_dir().join("caelestia-kde");
    let mut guard = KonsaveConf::new(&cache, &home);

    output::info("Backing up current KDE configuration with konsave...");
    fs::create_dir_all(&cache)
        .map_err(|error| format!("cannot use {}: {error}", cache.display()))?;

    let backup = context
        .bundle
        .join("backups")
        .join(crate::install_fs::timestamp().unwrap_or_else(|| "backup".to_string()));
    fs::create_dir_all(&backup)
        .map_err(|error| format!("cannot use {}: {error}", backup.display()))?;
    fs::write(
        cache.join("backup-dir.txt"),
        format!("{}\n", backup.display()),
    )
    .map_err(|error| format!("cannot record the backup directory: {error}"))?;

    save_previous_look_and_feel(&backup);

    let konsave = konsave_binary(&cache)?;

    guard
        .preserve()
        .map_err(|error| format!("cannot preserve the user's konsave configuration: {error}"))?;
    write_konsave_conf(&guard.user_conf)?;

    let _ = process::succeeds(&konsave, &["-r", PROFILE, "-f"], None);

    output::info(&format!("Saving konsave profile '{PROFILE}'..."));
    if !process::succeeds(&konsave, &["-s", PROFILE, "-f"], None) {
        return Err("Failed to save the current KDE profile.".into());
    }

    output::info(&format!(
        "Exporting konsave profile to {}...",
        backup.display()
    ));
    let destination = backup.to_string_lossy().to_string();
    if !process::succeeds(
        &konsave,
        &["-e", PROFILE, "-d", &destination, "-n", PROFILE, "-f"],
        None,
    ) {
        return Err("Failed to export the KDE profile backup.".into());
    }

    let archive = first_archive(&backup)
        .ok_or_else(|| "konsave completed but no .knsv archive was produced.".to_string())?;
    let name = archive
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    output::ok(&format!("KDE settings backed up to {name}"));
    Ok(())
}

struct KonsaveConf {
    user_conf: PathBuf,
    backup: PathBuf,
    had_user_conf: bool,
}

impl KonsaveConf {
    fn new(cache: &Path, home: &Path) -> Self {
        let user_conf = home.join(".config").join("konsave").join("conf.yaml");
        Self {
            had_user_conf: user_conf.is_file(),
            user_conf,
            backup: cache.join("konsave-conf.yaml.backup"),
        }
    }

    fn preserve(&mut self) -> io::Result<()> {
        if self.user_conf.is_file() {
            fs::create_dir_all(
                self.backup
                    .parent()
                    .map(Path::to_path_buf)
                    .unwrap_or_else(|| PathBuf::from(".")),
            )?;
            fs::copy(&self.user_conf, &self.backup)?;
            self.had_user_conf = true;
        }
        Ok(())
    }
}

impl Drop for KonsaveConf {
    fn drop(&mut self) {
        if self.backup.is_file() {
            if let Some(parent) = self.user_conf.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::copy(&self.backup, &self.user_conf);
        } else if !self.had_user_conf {
            let _ = fs::remove_file(&self.user_conf);
        }
    }
}

fn write_konsave_conf(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("cannot use {}: {error}", parent.display()))?;
    }
    fs::write(path, KONSAVE_CONF)
        .map_err(|error| format!("cannot write {}: {error}", path.display()))
}

fn konsave_binary(cache: &Path) -> Result<String, String> {
    if let Some(found) = process::locate("konsave") {
        return Ok(found.to_string_lossy().to_string());
    }
    if !process::available("python3") {
        return Err("python3 is required to install konsave.".to_string());
    }

    output::info("Installing konsave for KDE profile backups...");
    let venv = cache.join("konsave-venv");
    let binary = venv.join("bin").join("konsave");

    if !process::is_executable(&binary) {
        let directory = venv.to_string_lossy().to_string();
        if !process::succeeds("python3", &["-m", "venv", &directory], None) {
            return Err("Failed to create a local virtual environment for konsave.".to_string());
        }
        let python = venv
            .join("bin")
            .join("python")
            .to_string_lossy()
            .to_string();
        let _ = process::succeeds(&python, &["-m", "pip", "install", "--upgrade", "pip"], None);
        if !process::succeeds(
            &python,
            &["-m", "pip", "install", "--upgrade", "konsave"],
            None,
        ) {
            return Err("Failed to install konsave.".to_string());
        }
    }

    if !process::is_executable(&binary) {
        return Err("konsave is still unavailable after installation.".to_string());
    }
    Ok(binary.to_string_lossy().to_string())
}

fn save_previous_look_and_feel(backup: &Path) {
    if !process::available("kreadconfig6") {
        return;
    }
    if let Some(previous) = process::capture(
        "kreadconfig6",
        &[
            "--file",
            "kdeglobals",
            "--group",
            "KDE",
            "--key",
            "LookAndFeelPackage",
        ],
    ) && !previous.is_empty()
    {
        let _ = fs::write(
            backup.join("previous_lookandfeel.txt"),
            format!("{previous}\n"),
        );
    }
}

fn first_archive(directory: &Path) -> Option<PathBuf> {
    let mut archives: Vec<PathBuf> = fs::read_dir(directory)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file()
                && path.extension().and_then(|extension| extension.to_str()) == Some("knsv")
        })
        .collect();
    archives.sort();
    archives.into_iter().next()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn the_konsave_configuration_names_the_profile_that_is_saved_and_exported() {
        assert!(KONSAVE_CONF.contains("    caelestia-preinstall:"));
        assert!(KONSAVE_CONF.contains(r#"location: "$CONFIG_DIR""#));
        assert!(KONSAVE_CONF.contains(r#"location: "$SHARE_DIR""#));
        assert!(KONSAVE_CONF.contains("            - konsolerc"));
        assert!(KONSAVE_CONF.ends_with("...\n"));
    }

    #[test]
    fn the_first_archive_is_the_first_one_in_order() {
        let work = TempDir::new("caelestia-backup-test").expect("a temporary directory");
        assert!(first_archive(work.path()).is_none());

        fs::write(work.path().join("b.knsv"), b"x").expect("an archive");
        fs::write(work.path().join("a.knsv"), b"x").expect("an archive");
        fs::write(work.path().join("notes.txt"), b"x").expect("a file");
        fs::create_dir(work.path().join("c.knsv")).expect("a directory");

        let found = first_archive(work.path()).expect("an archive");
        assert_eq!(found.file_name().unwrap(), "a.knsv");
    }

    #[test]
    fn a_configuration_the_user_had_is_put_back() {
        let work = TempDir::new("caelestia-backup-test").expect("a temporary directory");
        let home = work.path().join("home");
        let cache = work.path().join("cache");
        let user_conf = home.join(".config").join("konsave").join("conf.yaml");
        fs::create_dir_all(user_conf.parent().unwrap()).expect("the config directory");
        fs::write(&user_conf, "mine\n").expect("the user's configuration");

        {
            let mut guard = KonsaveConf::new(&cache, &home);
            guard.preserve().expect("the user's configuration is kept");
            fs::write(&user_conf, "ours\n").expect("the file we wrote");
        }

        assert_eq!(
            fs::read_to_string(&user_conf).expect("the configuration"),
            "mine\n",
            "the user's own configuration comes back"
        );
    }

    #[test]
    fn a_configuration_the_user_did_not_have_is_taken_away_again() {
        let work = TempDir::new("caelestia-backup-test").expect("a temporary directory");
        let home = work.path().join("home");
        let user_conf = home.join(".config").join("konsave").join("conf.yaml");
        fs::create_dir_all(user_conf.parent().unwrap()).expect("the config directory");

        {
            let guard = KonsaveConf::new(&work.path().join("cache"), &home);
            fs::write(&user_conf, "ours\n").expect("the file we wrote");
            assert!(!guard.had_user_conf);
        }

        assert!(!user_conf.exists(), "the file we wrote is removed again");
    }

    #[test]
    fn the_konsave_configuration_is_written_verbatim() {
        let work = TempDir::new("caelestia-backup-test").expect("a temporary directory");
        let user_conf = work.path().join("conf.yaml");
        write_konsave_conf(&user_conf).expect("the configuration is written");
        assert_eq!(
            fs::read_to_string(&user_conf).expect("the configuration"),
            KONSAVE_CONF
        );
    }
}
