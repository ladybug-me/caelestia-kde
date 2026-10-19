use std::path::PathBuf;

pub fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub fn cache_dir() -> PathBuf {
    option("XDG_CACHE_HOME").unwrap_or_else(|| home().join(".cache"))
}

pub fn data_home() -> PathBuf {
    option("XDG_DATA_HOME").unwrap_or_else(|| home().join(".local").join("share"))
}

pub fn config_dir() -> PathBuf {
    option("XDG_CONFIG_HOME").unwrap_or_else(|| home().join(".config"))
}

pub fn state_dir() -> PathBuf {
    option("XDG_STATE_HOME").unwrap_or_else(|| home().join(".local").join("state"))
}

pub fn shorten(path: &std::path::Path) -> String {
    shorten_from(path, &home())
}

fn shorten_from(path: &std::path::Path, home: &std::path::Path) -> String {
    if home == std::path::Path::new("/") {
        return path.display().to_string();
    }
    match path.strip_prefix(home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => path.display().to_string(),
    }
}

fn option(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
}

#[cfg(unix)]
pub fn make_executable(path: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;

    if let Ok(metadata) = std::fs::metadata(path) {
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o755);
        let _ = std::fs::set_permissions(path, permissions);
    }
}

#[cfg(not(unix))]
pub fn make_executable(_path: &std::path::Path) {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn a_path_under_the_home_is_written_from_the_home() {
        let home = Path::new("/home/tester");
        assert_eq!(shorten_from(Path::new("/home/tester/x/y"), home), "~/x/y");
        assert_eq!(shorten_from(home, home), "~");
        assert_eq!(shorten_from(Path::new("/etc/x"), home), "/etc/x");
        assert_eq!(
            shorten_from(Path::new("/home/tester2/x"), home),
            "/home/tester2/x"
        );
        assert_eq!(
            shorten_from(Path::new("/usr/bin"), Path::new("/")),
            "/usr/bin"
        );
    }
}
