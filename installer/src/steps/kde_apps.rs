use crate::distro::{self, Distro};
use crate::output;
use crate::pkg;
use crate::process;
use crate::steps::{Context, Failure};

pub fn run(context: &Context) -> Result<(), Failure> {
    println!();
    println!();
    output::info("Installing KDE theme applications");
    println!();

    if context.flag("INSTALL_KVANTUM", true) {
        if distro::detect() == Distro::Debian {
            if !pkg::install_first(&["qt6-style-kvantum", "kvantum"]) {
                return Err(Failure::Reported);
            }
            let _ = pkg::install_first(&["qt5-style-kvantum"]);
        } else {
            if !pkg::install_first(&["kvantum"]) {
                return Err(Failure::Reported);
            }
            let _ = pkg::install_first(&["kvantum-qt5"]);
        }
    } else {
        output::skip("Skipping Kvantum installation by user choice.");
    }

    let _ = process::succeeds(
        "kwriteconfig6",
        &[
            "--file", "plasmarc", "--group", "Theme", "--key", "name", "darkly",
        ],
        None,
    );

    println!("[OK]  KDE extra apps step complete.");
    Ok(())
}
