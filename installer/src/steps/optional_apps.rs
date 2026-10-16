use std::fs;
use std::path::Path;

use crate::download::{self, Verification};
use crate::output;
use crate::paths;
use crate::pkg;
use crate::process;
use crate::steps::{Context, Failure};

pub fn run(context: &Context) -> Result<(), Failure> {
    let source = context.bundle.join("src");
    let dots = source.join("dots");
    let extra = source.join("dots-extra");

    println!();
    println!("  Optional Components");
    println!();

    if context.flag("INSTALL_VSCODE", false) {
        println!("  Setting up VSCode/VSCodium integration...");
        let _ = pkg::install_first(&["code", "visual-studio-code-bin"]);
        let _ = pkg::install_first(&["codium", "vscodium-bin"]);

        for (config, binary) in [("Code", "code"), ("VSCodium", "codium")] {
            if !process::available(binary) {
                continue;
            }
            let user = paths::home().join(".config").join(config).join("User");
            deploy(
                &dots.join("vscode").join("settings.json"),
                &user.join("settings.json"),
            );
            deploy(
                &dots.join("vscode").join("keybindings.json"),
                &user.join("keybindings.json"),
            );

            let vsix = dots
                .join("vscode")
                .join("caelestia-vscode-integration")
                .join("caelestia-vscode-integration-1.2.0.vsix");
            if vsix.is_file() {
                let extension = vsix.to_string_lossy().to_string();
                let _ = process::succeeds(binary, &["--install-extension", &extension], None);
                println!("    Installed caelestia-vscode-integration into {binary}");
            } else {
                println!("    [WARN] caelestia-vscode-integration .vsix not found");
            }
        }
    }

    if context.flag("INSTALL_ZED", false) {
        println!("  Setting up Zed...");
        if crate::distro::detect() == crate::distro::Distro::Arch {
            let _ = pkg::install_first(&["zed", "zed-editor"]);
        } else {
            let _ = pkg::install_first(&["zed"]);
        }
        let zed = paths::home().join(".config").join("zed");
        deploy(
            &dots.join("zed").join("keymap.json"),
            &zed.join("keymap.json"),
        );
        deploy(
            &dots.join("zed").join("settings.json"),
            &zed.join("settings.json"),
        );
    }

    if context.flag("INSTALL_SPICETIFY", false) {
        println!("  Setting up Spicetify...");
        let _ = pkg::install_first(&["spicetify-cli"]);

        let extra_css = extra
            .join("spicetify")
            .join("Themes")
            .join("caelestia")
            .join("user.css");
        let theme_css = if extra_css.is_file() {
            extra_css
        } else {
            dots.join("spicetify")
                .join("Themes")
                .join("caelestia")
                .join("user.css")
        };
        deploy(
            &theme_css,
            &paths::home()
                .join(".config")
                .join("spicetify")
                .join("Themes")
                .join("caelestia")
                .join("user.css"),
        );

        if process::available("spicetify") {
            if !process::succeeds("spicetify", &["apply"], None) {
                output::warn("spicetify apply failed");
            }
        } else {
            output::warn("spicetify not found; theme deployed but not applied");
        }
    }

    if context.flag("INSTALL_DISCORD", false) {
        println!("  Installing Discord/Equibop...");
        if crate::distro::detect() == crate::distro::Distro::Arch {
            let _ = pkg::install_first(&["discord", "equibop-bin"]);
        } else {
            let _ = pkg::install_first(&["discord"]);
        }
    }

    if context.flag("INSTALL_TODOIST", false) {
        println!("  Installing Todoist AppImage...");
        install_todoist();
    }

    if context.flag("INSTALL_FIREFOX_THEME", false) {
        println!("  Setting up Firefox theming...");
        let _ = pkg::install_first(&["firefox"]);
        deploy_firefox(&dots);
    }

    output::ok("Optional components done.");
    Ok(())
}

fn install_todoist() {
    let appimage = paths::home()
        .join(".local")
        .join("bin")
        .join("todoist.AppImage");

    if process::is_executable(&appimage) {
        output::skip("Todoist already installed.");
        return;
    }
    if fs::create_dir_all(appimage.parent().unwrap_or(Path::new("."))).is_err() {
        output::warn("Could not create ~/.local/bin for the Todoist AppImage.");
        return;
    }

    println!("  Downloading Todoist AppImage...");
    let url = "https://todoist.com/linux_app/appimage";
    if !download::fetch(url, &appimage, &["-L", "--fail"]) {
        output::warn("Todoist download failed (network?). Skipping.");
        return;
    }

    match download::verify(url, &appimage) {
        Verification::Mismatch => {
            let _ = fs::remove_file(&appimage);
            output::warn("Checksum mismatch for the Todoist AppImage - not installing it.");
        }
        verification => {
            if verification == Verification::Unpublished {
                let digest = download::sha256(&appimage).unwrap_or_default();
                output::warn(&format!(
                    "Todoist publishes no checksum; the AppImage's SHA-256 is {digest}."
                ));
            }
            paths::make_executable(&appimage);
            output::ok(&format!("Todoist installed to {}", appimage.display()));
        }
    }
}

fn deploy_firefox(dots: &Path) {
    let profiles = paths::home().join(".mozilla").join("firefox");
    if !profiles.is_dir() {
        output::warn("No Firefox profile directory yet. Launch Firefox once, then re-run.");
        return;
    }

    let mut deployed = 0;
    let Ok(entries) = fs::read_dir(&profiles) else {
        output::warn("No Firefox profile found. Launch Firefox once, then re-run.");
        return;
    };

    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        let is_profile = path.is_dir()
            && (name.ends_with(".default")
                || name.ends_with(".default-release")
                || name.ends_with(".default-esr"));
        if !is_profile {
            continue;
        }
        deployed += 1;
        deploy(&dots.join("firefox").join("user.js"), &path.join("user.js"));
        deploy(
            &dots.join("firefox").join("userChrome.css"),
            &path.join("chrome").join("userChrome.css"),
        );
    }

    if deployed == 0 {
        output::warn("No Firefox profile found. Launch Firefox once, then re-run.");
    }
}

fn deploy(source: &Path, destination: &Path) {
    if !source.is_file() {
        println!("    [WARN] Missing optional file: {}", source.display());
        return;
    }
    if let Some(parent) = destination.parent()
        && fs::create_dir_all(parent).is_err()
    {
        println!("    [WARN] Could not create {}", parent.display());
        return;
    }
    match fs::copy(source, destination) {
        Ok(_) => println!("    Deployed: {}", destination.display()),
        Err(error) => println!(
            "    [WARN] Could not deploy {}: {error}",
            destination.display()
        ),
    }
}
