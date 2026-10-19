use std::path::{Path, PathBuf};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Bundle {
    root: PathBuf,
}

impl Bundle {
    pub fn discover(explicit: Option<PathBuf>) -> Self {
        if let Some(root) = explicit {
            return Self { root };
        }
        let root = std::env::current_exe()
            .ok()
            .and_then(|exe| exe.parent().map(Path::to_path_buf))
            .unwrap_or_else(|| PathBuf::from("."));
        Self { root }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }
}

#[cfg(test)]
mod tests {
    use super::Bundle;
    use std::path::{Path, PathBuf};

    #[test]
    fn an_explicit_bundle_is_used_as_given() {
        let bundle = Bundle::discover(Some(PathBuf::from("/srv/caelestia")));
        assert_eq!(bundle.root(), Path::new("/srv/caelestia"));
    }

    #[test]
    fn a_discovered_bundle_is_the_directory_holding_the_binary() {
        let bundle = Bundle::discover(None);
        let exe = std::env::current_exe().expect("the test binary has a path");
        assert_eq!(bundle.root(), exe.parent().expect("a parent directory"));
    }
}
