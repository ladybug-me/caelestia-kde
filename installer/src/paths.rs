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
