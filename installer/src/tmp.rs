use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

pub struct TempDir {
    path: PathBuf,
}

/// The next directory name in this process. The pid keeps it unique across processes; the counter
/// keeps it unique within one, so two calls at the same moment cannot be offered the same name.
static NEXT: AtomicU64 = AtomicU64::new(0);

impl TempDir {
    pub fn new(prefix: &str) -> Option<Self> {
        let base = std::env::var_os("TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        Self::new_in(&base, prefix)
    }

    // A directory made in a caller's own tree: staging that has to share a filesystem with
    // what it is about to be renamed onto.
    pub fn new_in(base: &Path, prefix: &str) -> Option<Self> {
        let serial = NEXT.fetch_add(1, Ordering::Relaxed);
        for attempt in 0..64u32 {
            let candidate = base.join(format!(
                "{prefix}.{}.{serial}.{attempt}",
                std::process::id()
            ));
            match std::fs::create_dir(&candidate) {
                Ok(()) => return Some(Self { path: candidate }),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(_) => return None,
            }
        }
        None
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        for _ in 0..20 {
            if std::fs::remove_dir_all(&self.path).is_ok() {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::TempDir;

    #[test]
    fn a_temporary_directory_is_created_and_removed_again() {
        let path = {
            let temporary = TempDir::new("caelestia-test").expect("a temporary directory");
            assert!(temporary.path().is_dir());
            temporary.path().to_path_buf()
        };
        assert!(!path.exists(), "the directory should be gone");
    }

    #[test]
    fn two_temporary_directories_do_not_collide() {
        let first = TempDir::new("caelestia-test").expect("a temporary directory");
        let second = TempDir::new("caelestia-test").expect("a temporary directory");
        assert_ne!(first.path(), second.path());
    }
}
