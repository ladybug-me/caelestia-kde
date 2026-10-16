use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::output;
use crate::process;
use crate::steps::{Context, Failure, wallpapers_dir};
use crate::tmp::TempDir;

const REPOSITORY: &str = "https://github.com/dharmx/walls.git";
const PACK_NAME: &str = "dharmx-digital";
const DEFAULT_IMAGE: &str = "a_couple_of_people_standing_on_a_mountain.png";
const EXTENSIONS: [&str; 5] = ["png", "jpg", "jpeg", "webp", "gif"];

pub fn run(context: &Context) -> Result<(), Failure> {
    let pack = wallpapers_dir(context).join(PACK_NAME);
    let default_image = pack.join(DEFAULT_IMAGE);

    output::info("Downloading wallpaper pack (dharmx/walls digital)...");

    if has_content(&pack) {
        output::ok(&format!(
            "Wallpaper pack already present at {}",
            pack.display()
        ));
        return Ok(());
    }

    if !process::available("git") {
        output::warn("git not found - skipping wallpaper pack download.");
        return Ok(());
    }

    let Some(downloaded) = fetch(&pack) else {
        return Ok(());
    };

    output::ok(&format!(
        "Downloaded {downloaded} wallpapers to {}",
        pack.display()
    ));

    if default_image.is_file() {
        output::info(&format!(
            "Default wallpaper available: {}",
            default_image.display()
        ));
    } else {
        output::warn(&format!(
            "Expected default wallpaper missing from the pack: {}",
            default_image.display()
        ));
    }
    Ok(())
}

fn fetch(pack: &Path) -> Option<usize> {
    let Some(library) = pack.parent() else {
        output::warn("The wallpaper library has no parent directory - skipping.");
        return None;
    };

    let Some(work) = TempDir::new("caelestia-wallpapers") else {
        output::warn("Could not create a working directory - skipping pack download.");
        return None;
    };
    let checkout = work.path().join("walls");
    let destination = checkout.to_string_lossy().to_string();

    if !process::succeeds(
        "git",
        &[
            "clone",
            "--depth",
            "1",
            "--filter=blob:none",
            "--sparse",
            REPOSITORY,
            &destination,
        ],
        None,
    ) {
        output::warn("Failed to clone the wallpaper repository - skipping pack download.");
        return None;
    }

    if !process::succeeds(
        "git",
        &["sparse-checkout", "set", "digital"],
        Some(&checkout),
    ) {
        output::warn("Failed to check out the digital wallpapers - skipping pack download.");
        return None;
    }

    let files = images_in(&checkout.join("digital"));
    if files.is_empty() {
        output::warn("Wallpaper pack came back empty - skipping.");
        return None;
    }

    if let Err(error) = stage(library, &files) {
        output::warn(&format!(
            "Failed to copy wallpapers into the library - skipping: {error}"
        ));
        return None;
    }

    Some(files.len())
}

fn stage(library: &Path, files: &[PathBuf]) -> io::Result<()> {
    let staging = library.join(format!(".{PACK_NAME}.tmp"));
    fs::create_dir_all(library)?;
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging)?;

    for file in files {
        let name = match file.file_name() {
            Some(name) => name,
            None => continue,
        };
        if let Err(error) = fs::copy(file, staging.join(name)) {
            let _ = fs::remove_dir_all(&staging);
            return Err(error);
        }
    }

    let _ = fs::remove_dir_all(library.join(PACK_NAME));
    fs::rename(&staging, library.join(PACK_NAME))
}

fn images_in(directory: &Path) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file())
        .filter(|path| {
            path.extension()
                .and_then(|extension| extension.to_str())
                .map(|extension| extension.to_ascii_lowercase())
                .is_some_and(|extension| EXTENSIONS.contains(&extension.as_str()))
        })
        .collect();
    files.sort();
    files
}

fn has_content(directory: &Path) -> bool {
    fs::read_dir(directory)
        .map(|mut entries| entries.next().is_some())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    #[test]
    fn only_image_files_are_taken_from_the_pack() {
        let work = TempDir::new("caelestia-wallpapers-test").expect("a temporary directory");
        for name in [
            "one.png",
            "two.JPG",
            "three.webp",
            "four.txt",
            "five",
            "six.jpeg",
        ] {
            std::fs::write(work.path().join(name), b"x").expect("a file");
        }
        std::fs::create_dir(work.path().join("seven.gif")).expect("a directory");

        let names: Vec<String> = images_in(work.path())
            .iter()
            .map(|path| path.file_name().unwrap().to_string_lossy().to_string())
            .collect();
        assert_eq!(
            names,
            ["one.png", "six.jpeg", "three.webp", "two.JPG"],
            "the extension decides, and the order is stable"
        );
    }

    #[test]
    fn an_empty_or_missing_pack_has_no_content() {
        let work = TempDir::new("caelestia-wallpapers-test").expect("a temporary directory");
        assert!(!has_content(&work.path().join("missing")));
        assert!(!has_content(work.path()));

        std::fs::write(work.path().join("one.png"), b"x").expect("a file");
        assert!(has_content(work.path()));
    }

    #[test]
    fn staging_replaces_the_pack_in_one_step() {
        let work = TempDir::new("caelestia-wallpapers-test").expect("a temporary directory");
        let library = work.path().join("Wallpapers");
        let old = library.join(PACK_NAME);
        std::fs::create_dir_all(&old).expect("the previous pack");
        std::fs::write(old.join("gone.png"), b"x").expect("a file");

        let source = work.path().join("source");
        std::fs::create_dir_all(&source).expect("a source directory");
        std::fs::write(source.join("kept.png"), b"x").expect("a file");
        std::fs::write(source.join("skipped.txt"), b"x").expect("a file");

        let files = images_in(&source);
        stage(&library, &files).expect("the pack is staged");

        assert!(library.join(PACK_NAME).join("kept.png").is_file());
        assert!(!library.join(PACK_NAME).join("gone.png").exists());
        assert!(!library.join(format!(".{PACK_NAME}.tmp")).exists());
    }
}
