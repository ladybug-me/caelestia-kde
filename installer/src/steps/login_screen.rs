use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Stdio;

use crate::install_kind;
use crate::output;
use crate::paths;
use crate::privileges;
use crate::process;
use crate::steps::{Context, Failure};
use crate::tmp::TempDir;

const LOCAL_SYNC: &str = "/usr/local/bin/caelestia-greeter-sync";
const PACKAGED_SYNC: &str = "/usr/bin/caelestia-greeter-sync";
const SUDOERS_FILE: &str = "/etc/sudoers.d/caelestia-greeter-sync";
const OLD_SUDOERS_FILE: &str = "/etc/sudoers.d/caelestia-sddm-sync";

const POSTHOOK_EDITOR: &str = r##"
import json, os, re, sys

cli_path, hook_cmd = sys.argv[1], sys.argv[2]

config = {}
if os.path.exists(cli_path):
    with open(cli_path) as f:
        config = json.load(f)

HELPERS = r"sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook"
ours = re.compile(
    r"\s*&&\s*" + HELPERS
    + r"|" + HELPERS + r"\s*&&\s*"
    + r"|" + HELPERS
)

for section in ("wallpaper", "theme"):
    config.setdefault(section, {})
    existing = config[section].get("postHook", "")
    if isinstance(existing, str):
        cleaned = ours.sub("", existing).strip()
        config[section]["postHook"] = f"{cleaned} && {hook_cmd}" if cleaned else hook_cmd

os.makedirs(os.path.dirname(cli_path), exist_ok=True)
with open(cli_path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
"##;

pub fn run(context: &Context) -> Result<(), Failure> {
    if super::switches_off("05-login-screen", context) {
        output::skip("Login screen colours and wallpaper not selected.");
        return Ok(());
    }

    if !plasma_login() {
        output::skip(
            "This machine boots a display manager whose screen Caelestia cannot theme: its login \
             screen is left alone. The lock screen is drawn by Caelestia itself.",
        );
        return Ok(());
    }

    output::info("Matching the Plasma Login screen to the desktop");
    let mut step = LoginScreen {
        context,
        packaged: install_kind::is_packaged(),
        sync: PathBuf::new(),
        all_ok: true,
    };
    step.install_helper()?;
    step.run_helper();
    step.register_sync("Login screen configured for Plasma Login.")
}

fn plasma_login() -> bool {
    let alias = process::capture(
        "readlink",
        &["-f", "/etc/systemd/system/display-manager.service"],
    );
    manager_from(
        alias.as_deref(),
        unit_loaded("plasmalogin.service"),
        unit_loaded("sddm.service"),
        Path::new("/etc/plasmalogin.conf").exists(),
        process::available("sddm"),
    )
}

fn manager_from(
    alias: Option<&str>,
    plasmalogin_unit: bool,
    other_unit: bool,
    conf: bool,
    other_on_path: bool,
) -> bool {
    match alias {
        Some(alias) if alias.contains("plasmalogin") => return true,
        Some(alias) if alias.contains("sddm") => return false,
        _ => {}
    }
    if plasmalogin_unit {
        return true;
    }
    if other_unit {
        return false;
    }
    conf && !other_on_path
}

fn unit_loaded(unit: &str) -> bool {
    process::succeeds("systemctl", &["is-active", unit], None)
        || process::succeeds("systemctl", &["is-enabled", unit], None)
}

fn elevated(program: &str, args: &[&str]) -> bool {
    privileges::elevated(program, args, None) == Ok(0)
}

struct LoginScreen<'a> {
    context: &'a Context,
    packaged: bool,
    sync: PathBuf,
    all_ok: bool,
}

impl LoginScreen<'_> {
    fn install_helper(&mut self) -> Result<(), Failure> {
        self.sync = match self.context.variable("CAELESTIA_GREETER_SYNC") {
            Some(path) => PathBuf::from(path),
            None if self.packaged => PathBuf::from(PACKAGED_SYNC),
            None => PathBuf::from(LOCAL_SYNC),
        };

        if self.packaged {
            if !process::is_executable(&self.sync) {
                return Err(format!(
                    "The package's login screen helper is not installed at {}",
                    self.sync.display()
                )
                .into());
            }
            return Ok(());
        }

        let source = self.context.bundle.join("src/greeter/sync.sh");
        if !source.is_file() {
            return Err(format!(
                "The login screen sync helper is missing from the bundle: {}",
                source.display()
            )
            .into());
        }

        let directory = self
            .sync
            .parent()
            .ok_or_else(|| format!("{} is not a file path", self.sync.display()))?;
        elevated(
            "install",
            &["-d", "-m", "0755", &directory.to_string_lossy()],
        );
        if !elevated(
            "install",
            &[
                "-m",
                "0755",
                &source.to_string_lossy(),
                &self.sync.to_string_lossy(),
            ],
        ) {
            return Err(format!(
                "Could not install the sync helper to {}",
                self.sync.display()
            )
            .into());
        }
        output::ok(&format!(
            "Login screen sync helper installed to {}",
            self.sync.display()
        ));
        Ok(())
    }

    fn run_helper(&mut self) {
        match privileges::elevated(&self.sync.to_string_lossy(), &[], None) {
            Ok(0) => output::ok("Initial login screen sync complete."),
            _ => {
                output::warn("Initial login screen sync had warnings (non-fatal):");
                self.all_ok = false;
            }
        }
    }

    fn register_sync(&mut self, label: &str) -> Result<(), Failure> {
        let hook = format!("sudo {} --posthook", self.sync.display());
        let cli_json = paths::home()
            .join(".config")
            .join("caelestia")
            .join("cli.json");

        if process::available("python3") {
            write_posthook(&cli_json, &hook)?;
            output::ok("Posthook registered in cli.json");
        } else {
            output::warn(
                "python3 not found, skipping posthook registration. Wallpaper and color changes will not auto-sync to the login screen.",
            );
            self.all_ok = false;
        }

        let user = std::env::var("SUDO_USER")
            .ok()
            .filter(|user| !user.is_empty())
            .or_else(|| process::capture("id", &["-un"]))
            .unwrap_or_default();
        if !is_a_user_name(&user) {
            output::warn(&format!(
                "Could not tell which user the login screen sync belongs to (got '{user}')."
            ));
            self.all_ok = false;
            return Ok(());
        }

        let Some(work) = TempDir::new("caelestia-sudoers") else {
            return Err("Could not create a working directory for the sudoers rule".into());
        };
        let rule = work.path().join("rule");
        fs::write(
            &rule,
            format!("{user} ALL=(root) NOPASSWD: {}\n", self.sync.display()),
        )
        .map_err(|error| format!("cannot write the sudoers rule: {error}"))?;

        if !elevated("visudo", &["-cf", &rule.to_string_lossy()]) {
            output::warn(&format!(
                "The generated sudoers rule for {} did not validate; leaving sudoers alone.",
                self.sync.display()
            ));
            self.all_ok = false;
            return Ok(());
        }

        let _ = elevated("rm", &["-f", OLD_SUDOERS_FILE]);

        let dest = self
            .context
            .variable("CAELESTIA_GREETER_SUDOERS")
            .unwrap_or_else(|| SUDOERS_FILE.to_string());

        if elevated(
            "install",
            &[
                "-m",
                "0440",
                "-o",
                "root",
                "-g",
                "root",
                &rule.to_string_lossy(),
                &dest,
            ],
        ) {
            output::ok(&format!(
                "Sudoers drop-in written for {}.",
                self.sync.display()
            ));
        } else {
            output::warn(&format!(
                "Could not write {dest}; the login screen will not follow the theme."
            ));
            self.all_ok = false;
        }

        if self.all_ok {
            output::ok(label);
        } else {
            output::warn("Login screen configured with warnings. Review the output above.");
        }
        Ok(())
    }
}

fn is_a_user_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn write_posthook(path: &Path, hook: &str) -> Result<(), Failure> {
    let target = path.to_string_lossy().to_string();
    let mut command = std::process::Command::new("python3");
    command
        .args(["-", &target, hook])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let mut child = command
        .spawn()
        .map_err(|error| format!("could not run python3 to register the posthook: {error}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(POSTHOOK_EDITOR.as_bytes())
            .map_err(|error| format!("could not hand python3 the posthook editor: {error}"))?;
    }
    let status = child
        .wait()
        .map_err(|error| format!("python3 did not finish: {error}"))?;
    if !status.success() {
        return Err(format!("could not register the posthook in {target}").into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_boot_alias_decides_the_display_manager_over_every_other_signal() {
        assert!(
            manager_from(
                Some("/usr/lib/systemd/system/plasmalogin.service"),
                false,
                true,
                false,
                true
            ),
            "the alias beats a still-enabled SDDM"
        );
        assert!(
            !manager_from(
                Some("/usr/lib/systemd/system/sddm.service"),
                true,
                false,
                false,
                true
            ),
            "and beats a still-enabled Plasma Login"
        );
    }

    #[test]
    fn without_an_alias_the_display_manager_is_the_one_that_is_loaded() {
        assert!(manager_from(None, true, false, false, true));
        assert!(!manager_from(None, false, true, false, false));
        assert!(
            manager_from(None, true, true, false, true),
            "Plasma Login is asked about first"
        );
        assert!(
            manager_from(None, false, false, true, false),
            "a Plasma Login config with no sddm binary is Plasma Login"
        );
        assert!(
            !manager_from(None, false, false, true, true),
            "but not when sddm is installed"
        );
        assert!(!manager_from(None, false, false, false, true));
    }

    #[test]
    fn a_rule_is_only_written_for_a_name_sudo_would_accept() {
        assert!(is_a_user_name("camus"));
        assert!(is_a_user_name("a.b-c_d"));
        assert!(!is_a_user_name(""));
        assert!(!is_a_user_name("two words"));
        assert!(!is_a_user_name("root\nALL=(ALL) NOPASSWD: ALL"));
    }

    #[test]
    fn the_posthook_is_added_once_and_replaces_the_one_before_it() {
        let work = TempDir::new("caelestia-login-posthook").expect("a temporary directory");
        let cli = work.path().join(".config/caelestia/cli.json");
        let first = "sudo /usr/local/bin/caelestia-greeter-sync --posthook";

        write_posthook(&cli, first).expect("the hook is registered");
        let once = fs::read_to_string(&cli).expect("the file is written");
        assert_eq!(once.matches(first).count(), 2, "both sections: {once}");

        write_posthook(&cli, first).expect("the hook is registered again");
        let twice = fs::read_to_string(&cli).expect("the file is written");
        assert_eq!(
            twice.matches(first).count(),
            2,
            "a second run does not stack a second hook: {twice}"
        );
    }

    #[test]
    fn a_hook_left_by_an_older_install_is_replaced_rather_than_kept() {
        let work = TempDir::new("caelestia-login-posthook-old").expect("a temporary directory");
        let cli = work.path().join(".config/caelestia/cli.json");
        fs::create_dir_all(cli.parent().expect("a parent")).expect("the directory");
        fs::write(
            &cli,
            r#"{"wallpaper": {"postHook": "sudo /usr/share/sddm/themes/caelestia/scripts/sync.sh --posthook"}}"#,
        )
        .expect("the file");

        write_posthook(
            &cli,
            "sudo /usr/local/bin/caelestia-greeter-sync --posthook",
        )
        .expect("the hook is registered");
        let text = fs::read_to_string(&cli).expect("the file is written");
        assert!(!text.contains("sync.sh"), "the old hook is gone: {text}");
        assert!(text.contains("caelestia-greeter-sync"), "{text}");
    }
}
