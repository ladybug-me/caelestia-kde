use crate::process;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Distro {
    Arch,
    Fedora,
    Debian,
    Unknown,
}

impl Distro {
    pub fn name(self) -> &'static str {
        match self {
            Distro::Arch => "arch",
            Distro::Fedora => "fedora",
            Distro::Debian => "debian",
            Distro::Unknown => "unknown",
        }
    }

    pub fn from_id(text: &str) -> Self {
        match text.trim() {
            "arch" => Distro::Arch,
            "fedora" => Distro::Fedora,
            "debian" => Distro::Debian,
            _ => Distro::Unknown,
        }
    }

    /// What to call the distribution on screen: the family, not the individual release, because
    /// that is all the installer cares about.
    pub fn label(self) -> &'static str {
        match self {
            Distro::Arch => "Arch-based Linux",
            Distro::Fedora => "Fedora",
            Distro::Debian => "Debian-based Linux",
            Distro::Unknown => "unknown distribution",
        }
    }
}

const ARCH_IDS: [&str; 5] = ["arch", "cachyos", "endeavouros", "manjaro", "artix"];
const FEDORA_IDS: [&str; 7] = [
    "fedora",
    "nobara",
    "bazzite",
    "rhel",
    "centos",
    "almalinux",
    "rocky",
];
const DEBIAN_IDS: [&str; 9] = [
    "debian",
    "ubuntu",
    "pop",
    "mint",
    "kali",
    "raspbian",
    "elementary",
    "zorin",
    "deepin",
];

pub fn detect() -> Distro {
    if let Ok(explicit) = std::env::var("BASE_DISTRO")
        && !explicit.trim().is_empty()
    {
        return Distro::from_id(&explicit);
    }

    let path =
        std::env::var("CAELESTIA_OS_RELEASE").unwrap_or_else(|_| "/etc/os-release".to_string());
    if let Ok(text) = std::fs::read_to_string(&path) {
        let (id, like) = parse_os_release(&text);
        let classified = classify(&id, &like);
        if classified != Distro::Unknown {
            return classified;
        }
    }

    if process::available("pacman") {
        Distro::Arch
    } else if process::available("dnf") {
        Distro::Fedora
    } else if process::available("apt-get") {
        Distro::Debian
    } else {
        Distro::Unknown
    }
}

fn parse_os_release(text: &str) -> (String, String) {
    let mut id = String::new();
    let mut like = String::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim().trim_matches(['"', '\'']).to_lowercase();
        match key.trim() {
            "ID" => id = value,
            "ID_LIKE" => like = value,
            _ => {}
        }
    }
    (id, like)
}

fn classify(id: &str, like: &str) -> Distro {
    let id = id.trim().to_lowercase();
    let like = like.trim().to_lowercase();

    if ARCH_IDS.contains(&id.as_str()) {
        return Distro::Arch;
    }
    if FEDORA_IDS.contains(&id.as_str()) {
        return Distro::Fedora;
    }
    if DEBIAN_IDS.contains(&id.as_str()) {
        return Distro::Debian;
    }

    for family in like.split_whitespace() {
        if family == "arch" {
            return Distro::Arch;
        }
        if family == "fedora" {
            return Distro::Fedora;
        }
        if family == "debian" || family == "ubuntu" {
            return Distro::Debian;
        }
    }

    Distro::Unknown
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_distribution_ids_the_installer_knows_are_classified() {
        assert_eq!(classify("arch", ""), Distro::Arch);
        assert_eq!(classify("cachyos", ""), Distro::Arch);
        assert_eq!(classify("fedora", ""), Distro::Fedora);
        assert_eq!(classify("nobara", ""), Distro::Fedora);
        assert_eq!(classify("debian", ""), Distro::Debian);
        assert_eq!(classify("ubuntu", ""), Distro::Debian);
        assert_eq!(classify("pop", ""), Distro::Debian);
        assert_eq!(classify("opensuse", ""), Distro::Unknown);
    }

    #[test]
    fn an_unknown_id_falls_back_to_what_it_is_like() {
        assert_eq!(classify("garuda", "arch"), Distro::Arch);
        assert_eq!(classify("unknown-os", "fedora"), Distro::Fedora);
        assert_eq!(classify("unknown-os", "debian ubuntu"), Distro::Debian);
        assert_eq!(classify("unknown-os", "suse"), Distro::Unknown);
    }

    #[test]
    fn os_release_is_read_for_the_id_and_what_it_is_like() {
        let text = "\
NAME=\"Arch Linux\"
ID=arch
ID_LIKE=\"arch\"
PRETTY_NAME=\"Arch Linux\"
";
        assert_eq!(
            parse_os_release(text),
            ("arch".to_string(), "arch".to_string())
        );

        let quoted = "ID=\"ubuntu\"\nID_LIKE='debian'\n";
        assert_eq!(
            parse_os_release(quoted),
            ("ubuntu".to_string(), "debian".to_string())
        );

        assert_eq!(
            parse_os_release("PRETTY_NAME=whatever\n"),
            (String::new(), String::new())
        );
    }

    #[test]
    fn a_distro_name_is_taken_as_given() {
        assert_eq!(Distro::from_id("arch"), Distro::Arch);
        assert_eq!(Distro::from_id(" fedora "), Distro::Fedora);
        assert_eq!(Distro::from_id("gentoo"), Distro::Unknown);
    }
}
