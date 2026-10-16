// The install-kind contract: which layout this install has and where each of its directories
// is. Every step and the shell wrappers read the same answers from here.

use std::path::PathBuf;

use crate::paths;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    Source,
    Package,
}

pub fn kind() -> Kind {
    if let Ok(explicit) = std::env::var("CAELESTIA_INSTALL_KIND") {
        match explicit.trim() {
            "package" => return Kind::Package,
            "source" => return Kind::Source,
            _ => {}
        }
    }

    // A packaged install puts its files under the distribution's prefixes, and `/usr/local` is not
    // one of them: it is where a source build that ran `make install` lands.
    let packaged = std::env::current_exe()
        .map(|exe| {
            let exe = exe.to_string_lossy().replace('\\', "/");
            exe.starts_with("/usr/") && !exe.starts_with("/usr/local/")
        })
        .unwrap_or(false);
    if packaged {
        Kind::Package
    } else {
        Kind::Source
    }
}

pub fn is_packaged() -> bool {
    kind() == Kind::Package
}

impl Kind {
    /// What to call this install's layout on screen.
    pub fn label(self) -> &'static str {
        match self {
            Kind::Source => "source",
            Kind::Package => "package",
        }
    }
}

pub fn lib_dir() -> PathBuf {
    lib_dir_for(kind())
}

pub fn bin_dir() -> PathBuf {
    bin_dir_for(kind())
}

pub fn qml_import_path() -> String {
    qml_import_path_for(kind())
}

pub fn shell_config() -> PathBuf {
    shell_config_for(kind())
}

fn lib_dir_for(kind: Kind) -> PathBuf {
    match kind {
        Kind::Package => PathBuf::from("/usr/lib/caelestia"),
        Kind::Source => paths::home().join(".local").join("lib").join("caelestia"),
    }
}

fn bin_dir_for(kind: Kind) -> PathBuf {
    match kind {
        Kind::Package => PathBuf::from("/usr/bin"),
        Kind::Source => paths::home().join(".local").join("bin"),
    }
}

fn qml_import_path_for(kind: Kind) -> String {
    match kind {
        Kind::Package => "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia".to_string(),
        Kind::Source => {
            let home = paths::home();
            format!(
                "{}:{}",
                home.join(".local")
                    .join("lib")
                    .join("qt6")
                    .join("qml")
                    .display(),
                home.join(".config")
                    .join("quickshell")
                    .join("caelestia")
                    .display()
            )
        }
    }
}

fn shell_config_for(kind: Kind) -> PathBuf {
    match kind {
        Kind::Package => PathBuf::from("/etc/xdg/quickshell/caelestia/shell.qml"),
        Kind::Source => paths::home()
            .join(".config")
            .join("quickshell")
            .join("caelestia")
            .join("shell.qml"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The rule the environment and the binary's own location decide, kept apart from the
    /// reading of either so both cases can be asked about.
    fn packaged_from(exe: &str) -> bool {
        let exe = exe.replace('\\', "/");
        exe.starts_with("/usr/") && !exe.starts_with("/usr/local/")
    }

    #[test]
    fn a_packaged_install_is_the_distributions_own_prefixes() {
        assert!(packaged_from("/usr/bin/caelestia-install"));
        assert!(packaged_from("/usr/lib/caelestia/caelestia-install"));
        assert!(packaged_from("/usr/share/caelestia/bin/caelestia-install"));
    }

    #[test]
    fn a_build_installed_anywhere_else_is_a_source_install() {
        // The same rule as above, asked of the binary's own location.
        assert!(!packaged_from("/usr/local/bin/caelestia-install"));
        assert!(!packaged_from("/home/someone/.local/bin/caelestia-install"));
        assert!(!packaged_from("/opt/caelestia/caelestia-install"));
        assert!(!packaged_from("caelestia-install"));
    }

    #[test]
    fn a_packaged_install_reads_and_writes_the_system_locations() {
        assert_eq!(
            lib_dir_for(Kind::Package),
            PathBuf::from("/usr/lib/caelestia")
        );
        assert_eq!(bin_dir_for(Kind::Package), PathBuf::from("/usr/bin"));
        assert_eq!(
            qml_import_path_for(Kind::Package),
            "/usr/lib/qt6/qml:/etc/xdg/quickshell/caelestia"
        );
        assert_eq!(
            shell_config_for(Kind::Package),
            PathBuf::from("/etc/xdg/quickshell/caelestia/shell.qml")
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_source_install_reads_and_writes_the_users_own_locations() {
        let home = paths::home();
        assert_eq!(lib_dir_for(Kind::Source), home.join(".local/lib/caelestia"));
        assert_eq!(bin_dir_for(Kind::Source), home.join(".local/bin"));
        assert_eq!(
            shell_config_for(Kind::Source),
            home.join(".config/quickshell/caelestia/shell.qml")
        );

        let imports = qml_import_path_for(Kind::Source);
        assert!(imports.contains("/.local/lib/qt6/qml"), "{imports}");
        assert!(
            imports.contains("/.config/quickshell/caelestia"),
            "{imports}"
        );
    }
}
