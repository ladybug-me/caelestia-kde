use std::fs;
use std::path::{Path, PathBuf};

use crate::copy;
use crate::install_kind;
use crate::output;
use crate::paths;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

const CACHE: &str = "caelestia-kde";
const CAELESTIA_CONFIGS: [&str; 4] = ["btop", "foot", "kitty", "micro"];
const EXTRA_CONFIGS: [&str; 2] = ["fish", "fastfetch"];
const BACKED_UP: [&str; 7] = [
    "btop",
    "fastfetch",
    "fish",
    "foot",
    "kitty",
    "micro",
    "thunar",
];
const THUNAR_FILES: [&str; 2] = ["thunar-volman.xml", "uca.xml"];
const BRIDGE_DESTINATIONS: [&str; 4] = [
    ".local/bin",
    ".local/share/applications",
    ".config/systemd/user",
    ".local/share/kwin/scripts",
];
const SHELL_RCS: [(&str, &str); 3] = [
    (".bashrc", "bashrc"),
    (".zshrc", "zshrc"),
    (".config/fish/config.fish", "fish_config"),
];

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    output::info("Deploying configuration files");
    println!();

    let home = paths::home();
    let backup = backup_dir(context);
    let deployed = paths::cache_dir().join(CACHE).join("deployed");
    let dots = context.bundle.join("src").join("dots");
    let extra = context.bundle.join("src").join("dots-extra");

    for directory in [&backup, &deployed] {
        fs::create_dir_all(directory)
            .map_err(|error| format!("cannot use {}: {error}", directory.display()))?;
    }

    if !has_content(&dots) {
        return Err(missing_dotfiles(context, &dots));
    }

    output::info("Recording previous login shell...");
    record_shell(&backup);

    output::info("Backing up pre-install configs...");
    backup_configs(&home, &backup);

    output::info("Deploying Caelestia configs...");
    for config in CAELESTIA_CONFIGS {
        deploy(
            &dots.join(config),
            &home.join(".config").join(config),
            &deployed,
            &backup,
        );
    }

    deploy_thunar(context, &dots, &home);

    output::info("Deploying extra configs...");
    for config in EXTRA_CONFIGS {
        if config == "fish" && !context.flag("INSTALL_FISH", true) {
            output::skip("fish config deployment disabled by user choice");
            continue;
        }
        deploy(
            &extra.join(config),
            &home.join(".config").join(config),
            &deployed,
            &backup,
        );
    }

    deploy_starship(&dots, &home, &backup, &deployed);

    output::info("Deploying bridge files (bin, applications, systemd, kwin script)...");
    deploy_bridge(context, &home);

    output::ok("Config deployment complete.");
    Ok(())
}

fn missing_dotfiles(context: &Context, dots: &Path) -> Failure {
    if install_kind::is_packaged() {
        format!(
            "Missing dotfiles in {}. The package should have installed them; reinstall it.",
            dots.display()
        )
        .into()
    } else {
        format!(
            "Missing src/dots content. Run: caelestia-install step 02a-submodules --bundle \"{}\"",
            context.bundle.display()
        )
        .into()
    }
}

fn has_content(directory: &Path) -> bool {
    fs::read_dir(directory)
        .map(|mut entries| entries.next().is_some())
        .unwrap_or(false)
}

// The backup a previous step recorded is the one the installed dotfiles belong to, so
// it is reused; anything else (a path outside the two roots, a stale record, an absent
// directory) falls back to a fresh one under the bundle, or under the cache when the
// bundle belongs to a package the user cannot write to.
pub fn backup_dir(context: &Context) -> PathBuf {
    if let Some(explicit) = context.variable("BACKUP_DIR") {
        return PathBuf::from(explicit);
    }

    let cache = paths::cache_dir().join(CACHE);
    if let Some(recorded) = recorded_backup(&cache, &context.bundle) {
        return recorded;
    }

    let root = if install_kind::is_packaged() {
        cache
    } else {
        context.bundle.clone()
    };
    root.join("backups")
        .join(crate::install_fs::timestamp().unwrap_or_else(|| "backup".to_string()))
}

fn recorded_backup(cache: &Path, bundle: &Path) -> Option<PathBuf> {
    let recorded = fs::read_to_string(cache.join("backup-dir.txt")).ok()?;
    let path = PathBuf::from(recorded.trim());
    let name = path.file_name()?.to_str()?;

    if !is_stamp(name) {
        return None;
    }
    if path != bundle.join("backups").join(name) && path != cache.join("backups").join(name) {
        return None;
    }
    if !path.is_dir() {
        return None;
    }
    Some(path)
}

fn is_stamp(name: &str) -> bool {
    let bytes = name.as_bytes();
    bytes.len() == 15
        && bytes[8] == b'_'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 8 || byte.is_ascii_digit())
}

fn record_shell(backup: &Path) {
    let Some(user) = process::capture("id", &["-un"]).filter(|name| !name.is_empty()) else {
        output::warn("Could not tell which user is installing - the login shell is not recorded.");
        return;
    };

    let entry = process::capture("getent", &["passwd", &user])
        .filter(|line| !line.is_empty())
        .or_else(|| from_passwd_file(&user));

    let shell = entry
        .as_deref()
        .and_then(|line| line.split(':').nth(6))
        .filter(|shell| !shell.is_empty());

    let Some(shell) = shell else {
        output::warn(&format!(
            "Could not read the login shell of {user} - it is not recorded for uninstall."
        ));
        return;
    };

    let _ = fs::write(backup.join("previous_shell.txt"), format!("{shell}\n"));
}

fn from_passwd_file(user: &str) -> Option<String> {
    fs::read_to_string("/etc/passwd")
        .ok()?
        .lines()
        .find(|line| line.split(':').next() == Some(user))
        .map(str::to_string)
}

fn backup_configs(home: &Path, backup: &Path) {
    let config = backup.join(".config");
    let local = backup.join("local");
    for directory in [&backup.join("shellrc"), &config, &local] {
        let _ = fs::create_dir_all(directory);
    }

    for name in BACKED_UP {
        let source = home.join(".config").join(name);
        if source.exists() {
            let _ = copy::tree(&source, &config.join(name));
        }
    }

    let konsolerc = home.join(".config").join("konsolerc");
    if konsolerc.is_file() {
        let _ = copy::file(&konsolerc, &config.join("konsolerc"));
    }

    let konsole = home.join(".local").join("share").join("konsole");
    if konsole.is_dir() {
        let _ = copy::tree(&konsole, &local.join("konsole"));
    }

    for (relative, name) in SHELL_RCS {
        let source = home.join(relative);
        let state = if source.is_file() {
            let _ = copy::file(&source, &backup.join("shellrc").join(name));
            "present"
        } else {
            "missing"
        };
        let _ = fs::write(
            backup.join("shellrc").join(format!("{name}.state")),
            format!("{state}\n"),
        );
    }
}

fn deploy(source: &Path, target: &Path, deployed: &Path, backup: &Path) {
    if !source.is_dir() {
        return;
    }

    let Some(name) = target
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
    else {
        return;
    };
    let stamp = deployed.join(format!("{name}.sha256"));

    if target.exists() && locally_modified(target, &stamp) {
        output::skip(&format!("Preserving locally modified config: {name}"));
        println!(
            "           Backup: {}",
            backup.join(".config").join(&name).display()
        );
        return;
    }

    let _ = fs::remove_dir_all(target);
    let _ = copy::tree(source, target);
    record_stamp(&stamp, target);
    println!("    Deployed: {name}");
}

fn deploy_thunar(context: &Context, dots: &Path, home: &Path) {
    if !context.flag("INSTALL_THUNAR", false) {
        output::skip("Thunar integration files disabled by user choice");
        return;
    }

    let source = dots.join("thunar");
    if !source.is_dir() {
        output::warn("Thunar integration files unavailable in src/dots/thunar");
        return;
    }

    let target = home.join(".config").join("thunar");
    let _ = fs::create_dir_all(&target);
    for file in THUNAR_FILES {
        if source.join(file).is_file() {
            let _ = copy::file(&source.join(file), &target.join(file));
            println!("    Deployed: thunar/{file}");
        } else {
            output::warn(&format!("Missing optional Thunar file: thunar/{file}"));
        }
    }
}

fn deploy_starship(dots: &Path, home: &Path, backup: &Path, deployed: &Path) {
    let target = home.join(".config").join("starship.toml");

    if target.is_file() {
        let _ = copy::file(&target, &backup.join(".config").join("starship.toml"));
    }

    let source = dots.join("starship.toml");
    if !source.is_file() {
        return;
    }

    let stamp = deployed.join("starship.toml.sha256");
    if target.exists() && locally_modified(&target, &stamp) {
        output::skip("Preserving locally modified config: starship.toml");
        println!(
            "           Backup: {}",
            backup.join(".config").join("starship.toml").display()
        );
        return;
    }

    let _ = fs::create_dir_all(home.join(".config"));
    let _ = copy::file(&source, &target);
    record_stamp(&stamp, &target);
    println!("    Deployed: starship.toml");
}

fn deploy_bridge(context: &Context, home: &Path) {
    for destination in BRIDGE_DESTINATIONS {
        let _ = fs::create_dir_all(home.join(destination));
    }

    let source = context.bundle.join("src").join("bin");
    if let Ok(entries) = fs::read_dir(&source) {
        for entry in entries.filter_map(Result::ok) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with(".cpp") || name.ends_with("CMakeLists.txt") || entry.path().is_dir() {
                continue;
            }

            let target = home.join(".local").join("bin").join(&name);
            // `cp --remove-destination`: a bridge file that is a symlink is replaced,
            // not written through.
            let _ = fs::remove_file(&target);
            let _ = copy::file(&entry.path(), &target);
        }
    }

    let applications = home.join(".local/share/applications");
    let _ = process::succeeds(
        "update-desktop-database",
        &[&applications.to_string_lossy()],
        None,
    );
    output::ok("Bridge files deployed.");
}

fn locally_modified(target: &Path, stamp: &Path) -> bool {
    let expected = fs::read_to_string(stamp)
        .map(|recorded| recorded.trim().to_string())
        .unwrap_or_default();
    if expected.is_empty() {
        return false;
    }

    match checksum(target) {
        Some(current) => current != expected,
        None => {
            output::warn(&format!(
                "Could not checksum {} - deploying over it.",
                target.display()
            ));
            false
        }
    }
}

fn record_stamp(stamp: &Path, target: &Path) {
    if let Some(current) = checksum(target) {
        let _ = fs::write(stamp, format!("{current}\n"));
    }
}

fn checksum(path: &Path) -> Option<String> {
    if path.is_dir() {
        directory_checksum(path)
    } else if path.exists() {
        file_checksum(path)
    } else {
        Some("missing".to_string())
    }
}

fn file_checksum(path: &Path) -> Option<String> {
    let digest = process::capture("sha256sum", &[&path.to_string_lossy()])?;
    digest_of(&digest)
}

fn digest_of(line: &str) -> Option<String> {
    line.split_whitespace()
        .next()
        .map(str::to_string)
        .filter(|digest| !digest.is_empty())
}

// The same value the shell recorded: sha256sum of every file in the directory, in order,
// hashed together. The paths go in relative to the directory, as `find .` printed them.
fn directory_checksum(directory: &Path) -> Option<String> {
    let mut files = Vec::new();
    collect_files(directory, Path::new("."), &mut files)?;
    files.sort();

    let work = TempDir::new("caelestia-config-checksum")?;
    let listing = work.path().join("listing");
    let mut joined = String::new();
    for relative in &files {
        let digest =
            process::capture_in("sha256sum", &[&relative.to_string_lossy()], Some(directory))?;
        joined.push_str(&digest);
        joined.push('\n');
    }

    fs::write(&listing, joined).ok()?;
    file_checksum(&listing)
}

fn collect_files(directory: &Path, prefix: &Path, files: &mut Vec<PathBuf>) -> Option<()> {
    let mut entries: Vec<_> = fs::read_dir(directory)
        .ok()?
        .filter_map(Result::ok)
        .collect();
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        let file_type = entry.file_type().ok()?;
        let relative = prefix.join(entry.file_name());
        if file_type.is_dir() {
            collect_files(&entry.path(), &relative, files)?;
        } else if file_type.is_file() {
            files.push(relative);
        }
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn only_a_backup_stamp_names_a_backup_directory() {
        assert!(is_stamp("20240101_120000"));
        assert!(!is_stamp("20240101_12000"));
        assert!(!is_stamp("2024010_120000"));
        assert!(!is_stamp("20240101-120000"));
        assert!(!is_stamp("backup"));
        assert!(!is_stamp("20240101120000"));
    }

    #[test]
    fn the_file_list_is_relative_and_in_one_order() {
        let work = TempDir::new("caelestia-configs-test").expect("a temporary directory");
        fs::create_dir_all(work.path().join("nested")).expect("a nested directory");
        fs::write(work.path().join("b.conf"), b"b").expect("a file");
        fs::write(work.path().join("a.conf"), b"a").expect("a file");
        fs::write(work.path().join("nested").join("c.conf"), b"c").expect("a file");

        let mut files = Vec::new();
        collect_files(work.path(), Path::new("."), &mut files).expect("the tree is walked");
        files.sort();

        let listed: Vec<String> = files
            .iter()
            .map(|path| path.to_string_lossy().replace('\\', "/"))
            .collect();
        assert_eq!(listed, ["./a.conf", "./b.conf", "./nested/c.conf"]);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_is_not_a_file_the_checksum_covers() {
        let work = TempDir::new("caelestia-configs-test").expect("a temporary directory");
        fs::write(work.path().join("real.conf"), b"real").expect("a file");
        std::os::unix::fs::symlink("real.conf", work.path().join("link.conf")).expect("a symlink");

        let mut files = Vec::new();
        collect_files(work.path(), Path::new("."), &mut files).expect("the tree is walked");

        assert_eq!(files.len(), 1, "{files:?}");
    }

    #[test]
    fn a_digest_line_is_read_down_to_its_hash() {
        assert_eq!(digest_of("abc123  ./btop.conf"), Some("abc123".to_string()));
        assert_eq!(digest_of(""), None);
    }

    #[test]
    fn a_directory_that_cannot_be_read_has_no_checksum() {
        let work = TempDir::new("caelestia-configs-test").expect("a temporary directory");
        assert!(
            collect_files(&work.path().join("absent"), Path::new("."), &mut Vec::new()).is_none()
        );
    }

    #[test]
    fn a_path_that_is_not_there_checksums_as_missing() {
        let work = TempDir::new("caelestia-configs-test").expect("a temporary directory");
        assert_eq!(
            checksum(&work.path().join("absent")),
            Some("missing".to_string())
        );
    }
}
