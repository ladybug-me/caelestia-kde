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

    pub fn scripts_dir(&self) -> PathBuf {
        self.root.join("scripts")
    }

    pub fn check_scripts(&self) -> Result<(), String> {
        let scripts = self.scripts_dir();
        if scripts.is_dir() {
            return Ok(());
        }
        Err(format!(
            "step scripts not found at {} - the installer cannot run any step",
            scripts.display()
        ))
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
        assert_eq!(
            bundle.scripts_dir(),
            PathBuf::from("/srv/caelestia/scripts")
        );
    }

    #[test]
    fn a_discovered_bundle_is_the_directory_holding_the_binary() {
        let bundle = Bundle::discover(None);
        let exe = std::env::current_exe().expect("the test binary has a path");
        assert_eq!(bundle.root(), exe.parent().expect("a parent directory"));
    }

    #[test]
    fn a_bundle_without_the_step_scripts_is_refused() {
        let missing = Bundle::discover(Some(PathBuf::from("/nonexistent/caelestia")));
        let problem = missing.check_scripts().unwrap_err();
        assert!(problem.contains("step scripts not found"), "{problem}");
    }

    #[test]
    fn this_checkout_is_a_valid_bundle() {
        let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let root = crate_dir
            .parent()
            .expect("installer/ has a parent")
            .to_path_buf();
        Bundle::discover(Some(root))
            .check_scripts()
            .expect("the checkout carries its scripts");
    }
}
