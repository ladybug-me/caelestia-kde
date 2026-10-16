use std::path::{Path, PathBuf};
use std::process::Command;

mod common;

const BINARY: &str = env!("CARGO_BIN_EXE_caelestia-install");

struct Fixture {
    root: PathBuf,
}

impl Fixture {
    fn new(name: &str) -> Self {
        let root =
            std::env::temp_dir().join(format!("caelestia-steps.{name}.{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("a fixture directory");
        Self { root }
    }

    fn path(&self, name: &str) -> PathBuf {
        self.root.join(name)
    }

    fn library(&self) -> PathBuf {
        self.path("Wallpapers")
    }

    #[cfg(unix)]
    fn cache_file(&self, name: &str) -> PathBuf {
        self.path("cache").join("caelestia-kde").join(name)
    }

    #[cfg(unix)]
    fn text(&self, name: &str) -> String {
        self.path(name).to_string_lossy().to_string()
    }

    fn step(&self, id: &str, path: &Path, extra: &[(&str, &str)]) -> Output {
        self.in_bundle(id, path, None, extra)
    }

    #[cfg(unix)]
    fn step_in(&self, id: &str, path: &Path, bundle: &Path, extra: &[(&str, &str)]) -> Output {
        self.in_bundle(id, path, Some(bundle), extra)
    }

    fn in_bundle(
        &self,
        id: &str,
        path: &Path,
        bundle: Option<&Path>,
        extra: &[(&str, &str)],
    ) -> Output {
        let mut command = Command::new(BINARY);
        command.args(["step", id]);
        if let Some(bundle) = bundle {
            command.arg("--bundle").arg(bundle);
        }
        command
            .env("PATH", path)
            .env("HOME", &self.root)
            .env("XDG_CACHE_HOME", self.path("cache"))
            .env("CAELESTIA_WALLPAPERS_DIR", self.library())
            .env_remove("XDG_PICTURES_DIR")
            .env_remove("TMPDIR");
        for (key, value) in extra {
            command.env(key, value);
        }
        let output = command.output().expect("the installer runs");
        Output {
            code: output.status.code(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        }
    }

    fn empty_path(&self) -> PathBuf {
        let path = self.path("empty-bin");
        std::fs::create_dir_all(&path).expect("a directory for the path");
        path
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

struct Output {
    code: Option<i32>,
    stdout: String,
    stderr: String,
}

#[test]
fn a_step_that_does_not_exist_is_a_usage_error() {
    let fixture = Fixture::new("unknown");
    let output = fixture.step("not-a-step", &fixture.empty_path(), &[]);
    assert_eq!(output.code, Some(2));
    assert!(
        output.stderr.contains("no step is called"),
        "{}",
        output.stderr
    );
}

#[test]
fn asking_a_step_for_help_prints_the_usage() {
    let output = Command::new(BINARY)
        .args(["step", "--help"])
        .output()
        .expect("the installer runs");
    assert_eq!(output.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("caelestia-install step"), "{stdout}");
}

#[test]
fn the_wallpaper_pack_is_left_alone_when_it_is_already_there() {
    let fixture = Fixture::new("present");
    let pack = fixture.library().join("dharmx-digital");
    std::fs::create_dir_all(&pack).expect("the pack");
    std::fs::write(
        pack.join("a_couple_of_people_standing_on_a_mountain.png"),
        b"x",
    )
    .expect("the default wallpaper");

    let output = fixture.step("03a-wallpapers", &fixture.empty_path(), &[]);
    assert_eq!(output.code, Some(0));
    assert!(
        output.stdout.contains("Wallpaper pack already present"),
        "{}",
        output.stdout
    );
}

#[test]
fn no_git_on_the_path_skips_the_download_without_failing() {
    let fixture = Fixture::new("no-git");
    let output = fixture.step("03a-wallpapers", &fixture.empty_path(), &[]);
    assert_eq!(output.code, Some(0));
    assert!(
        output
            .stdout
            .contains("git not found - skipping wallpaper pack download."),
        "{}",
        output.stdout
    );
    assert!(!fixture.library().exists(), "nothing should be written");
}

#[cfg(unix)]
fn stub_git(fixture: &Fixture, body: &str) -> PathBuf {
    stub_program(fixture, "git", body)
}

#[cfg(unix)]
fn stub_program(fixture: &Fixture, name: &str, body: &str) -> PathBuf {
    use std::os::unix::fs::PermissionsExt;

    let directory = fixture.path("bin");
    std::fs::create_dir_all(&directory).expect("a directory for the stub");
    let program = directory.join(name);
    std::fs::write(&program, format!("#!/bin/sh\n{body}\n")).expect("the stub");
    let mut permissions = std::fs::metadata(&program).expect("the stub").permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&program, permissions).expect("an executable stub");

    let system = std::env::var("PATH").unwrap_or_default();
    PathBuf::from(format!("{}:{system}", directory.display()))
}

#[cfg(unix)]
#[test]
fn the_pack_is_fetched_through_a_sparse_checkout() {
    let fixture = Fixture::new("fetch");
    let path = stub_git(
        &fixture,
        r#"for arg in "$@"; do dest="$arg"; done
case "$1" in
    clone)
        mkdir -p "$dest/digital"
        : > "$dest/digital/one.png"
        : > "$dest/digital/two.JPG"
        : > "$dest/digital/notes.txt"
        ;;
esac
exit 0"#,
    );

    let output = fixture.step("03a-wallpapers", &path, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("Downloaded 2 wallpapers to"),
        "{}",
        output.stdout
    );

    let pack = fixture.library().join("dharmx-digital");
    assert!(pack.join("one.png").is_file());
    assert!(pack.join("two.JPG").is_file());
    assert!(!pack.join("notes.txt").exists(), "only images are taken");
    assert!(
        !fixture.library().join(".dharmx-digital.tmp").exists(),
        "the staging directory is gone"
    );
    assert!(
        output
            .stdout
            .contains("Expected default wallpaper missing from the pack"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
const KONSAVE_STUB: &str = r#"mode=""
dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -e) mode=export ;;
        -s) mode=save ;;
        -d) dir="$2" ;;
    esac
    shift
done
if [ "${STUB_FAIL_SAVE:-0}" = "1" ] && [ "$mode" = "save" ]; then
    exit 1
fi
if [ "$mode" = "export" ]; then
    : > "$dir/caelestia-preinstall.knsv"
fi
exit 0"#;

#[cfg(unix)]
#[test]
fn the_backup_exports_a_profile_and_puts_the_users_configuration_back() {
    let fixture = Fixture::new("backup");
    let path = stub_program(&fixture, "konsave", KONSAVE_STUB);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");
    let user_conf = fixture.path(".config/konsave/conf.yaml");
    std::fs::create_dir_all(user_conf.parent().expect("a parent")).expect("the config directory");
    std::fs::write(&user_conf, "mine\n").expect("the user's configuration");

    let output = fixture.step_in("00-backup-themes", &path, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Saving konsave profile 'caelestia-preinstall'..."),
        "{}",
        output.stdout
    );
    assert!(
        output
            .stdout
            .contains("KDE settings backed up to caelestia-preinstall.knsv"),
        "{}",
        output.stdout
    );

    let backups: Vec<_> = std::fs::read_dir(bundle.join("backups"))
        .expect("the backups directory")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .collect();
    assert_eq!(backups.len(), 1, "one backup directory");
    assert!(
        backups[0].join("caelestia-preinstall.knsv").is_file(),
        "the exported profile is in the backup"
    );

    let recorded = std::fs::read_to_string(fixture.cache_file("backup-dir.txt"))
        .expect("the backup directory is recorded");
    assert_eq!(recorded.trim(), backups[0].display().to_string());

    assert_eq!(
        std::fs::read_to_string(&user_conf).expect("the user's configuration"),
        "mine\n",
        "what the user had is what the user keeps"
    );
}

#[cfg(unix)]
#[test]
fn a_configuration_we_wrote_ourselves_is_taken_away_again() {
    let fixture = Fixture::new("backup-clean");
    let path = stub_program(&fixture, "konsave", KONSAVE_STUB);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");

    let output = fixture.step_in("00-backup-themes", &path, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        !fixture.path(".config/konsave/conf.yaml").exists(),
        "the configuration we wrote is removed again"
    );
}

#[cfg(unix)]
#[test]
fn a_failed_save_fails_the_step_and_still_restores_the_configuration() {
    let fixture = Fixture::new("backup-fails");
    let path = stub_program(&fixture, "konsave", KONSAVE_STUB);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");
    let user_conf = fixture.path(".config/konsave/conf.yaml");
    std::fs::create_dir_all(user_conf.parent().expect("a parent")).expect("the config directory");
    std::fs::write(&user_conf, "mine\n").expect("the user's configuration");

    let output = fixture.step_in(
        "00-backup-themes",
        &path,
        &bundle,
        &[("STUB_FAIL_SAVE", "1")],
    );
    assert_eq!(output.code, Some(1));
    assert!(
        output
            .stderr
            .contains("Failed to save the current KDE profile."),
        "{}",
        output.stderr
    );
    assert_eq!(
        std::fs::read_to_string(&user_conf).expect("the user's configuration"),
        "mine\n"
    );
}

#[cfg(unix)]
#[test]
fn the_system_update_can_be_skipped_without_touching_the_system() {
    let fixture = Fixture::new("skip-update");
    let output = fixture.step(
        "00a-system-update",
        &fixture.empty_path(),
        &[("SKIP_SYSTEM_UPDATE", "true")],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Skipping full system update (SKIP_SYSTEM_UPDATE=true)."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn an_unknown_distribution_skips_the_update_with_a_warning() {
    let fixture = Fixture::new("unknown-distro");
    let output = fixture.step(
        "00a-system-update",
        &fixture.empty_path(),
        &[("BASE_DISTRO", "unknown")],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Distro not set properly, skipping system update."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_stale_session_mark_from_another_session_is_cleared() {
    let fixture = Fixture::new("stale-session");
    let state = fixture.path("state/caelestia");
    std::fs::create_dir_all(&state).expect("the state directory");
    let stamp = state.join("stale-session");
    std::fs::write(&stamp, "1234 5678\n").expect("a stale mark");

    let output = fixture.step(
        "00a-system-update",
        &fixture.empty_path(),
        &[
            ("SKIP_SYSTEM_UPDATE", "true"),
            (
                "XDG_STATE_HOME",
                &fixture.path("state").display().to_string(),
            ),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(!stamp.exists(), "the stale mark is cleared");
}

#[cfg(unix)]
#[test]
fn prerequisites_that_are_present_are_reported_as_present() {
    let fixture = Fixture::new("prereqs");
    let mut path = PathBuf::new();
    for program in ["yq", "jq", "g++", "apt-get"] {
        path = stub_program(&fixture, program, "exit 0");
    }

    let output = fixture.step("01-ensure-prereqs", &path, &[("BASE_DISTRO", "debian")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Prerequisites are already installed."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
const CURL_STUB: &str = r#"dest=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; dest="$1" ;;
        http*) url="$1" ;;
    esac
    shift
done
case "$url" in
    *.sha256) exit 22 ;;
esac
[ -n "$dest" ] || exit 1
printf 'appimage' > "$dest"
exit 0"#;

#[cfg(unix)]
#[test]
fn no_optional_component_asked_for_is_no_work() {
    let fixture = Fixture::new("optional-none");
    let output = fixture.step("11-optional-apps", &fixture.empty_path(), &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("Optional components done."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_todoist_download_that_fails_is_reported_and_skipped() {
    let fixture = Fixture::new("optional-todoist-fail");
    let path = stub_program(&fixture, "curl", "exit 1");

    let output = fixture.step("11-optional-apps", &path, &[("INSTALL_TODOIST", "true")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Todoist download failed (network?). Skipping."),
        "{}",
        output.stdout
    );
    assert!(!fixture.path(".local/bin/todoist.AppImage").exists());
}

#[cfg(unix)]
#[test]
fn a_todoist_appimage_without_a_published_checksum_is_installed_with_a_warning() {
    let fixture = Fixture::new("optional-todoist");
    let path = stub_program(&fixture, "curl", CURL_STUB);

    let output = fixture.step("11-optional-apps", &path, &[("INSTALL_TODOIST", "true")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("Todoist publishes no checksum"),
        "{}",
        output.stdout
    );
    assert!(
        output.stdout.contains("Todoist installed to"),
        "{}",
        output.stdout
    );

    let installed = fixture.path(".local/bin/todoist.AppImage");
    assert!(installed.is_file());
    use std::os::unix::fs::PermissionsExt;
    let mode = std::fs::metadata(&installed)
        .expect("the file")
        .permissions()
        .mode();
    assert_eq!(mode & 0o111, 0o111, "the AppImage is made executable");
}

#[cfg(unix)]
#[test]
fn firefox_theming_without_a_profile_says_what_to_do() {
    let fixture = Fixture::new("optional-firefox");
    let output = fixture.step(
        "11-optional-apps",
        &fixture.empty_path(),
        &[
            ("INSTALL_FIREFOX_THEME", "true"),
            ("BASE_DISTRO", "unknown"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("No Firefox profile directory yet. Launch Firefox once, then re-run."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_failed_clone_leaves_the_library_as_it_was() {
    let fixture = Fixture::new("clone-fails");
    let path = stub_git(&fixture, "exit 1");

    let pack = fixture.library().join("dharmx-digital");
    std::fs::create_dir_all(fixture.library()).expect("the library");

    let output = fixture.step("03a-wallpapers", &path, &[]);
    assert_eq!(output.code, Some(0));
    assert!(
        output
            .stdout
            .contains("Failed to clone the wallpaper repository"),
        "{}",
        output.stdout
    );
    assert!(!pack.exists());
}

#[cfg(unix)]
struct WindowRules {
    path: PathBuf,
    program: PathBuf,
    config: PathBuf,
    calls: PathBuf,
}

#[cfg(unix)]
fn config_tools(fixture: &Fixture) -> WindowRules {
    let bin = fixture.path("bin");
    std::fs::create_dir_all(&bin).expect("a directory for the stubs");
    let tools = common::config_tools(&fixture.root, &bin);

    common::stub(
        &bin,
        "qdbus6",
        "#!/bin/sh\nprintf '%s %s\\n' 'qdbus6' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    let path = PathBuf::from(format!("{}:{system}", bin.display()));

    WindowRules {
        path,
        program: tools.program,
        config: tools.config,
        calls: tools.calls,
    }
}

#[cfg(unix)]
fn run_window_rules(fixture: &Fixture, tools: &WindowRules, extra: &[(&str, &str)]) -> Output {
    let program = tools.program.to_str().expect("a path");
    let config = tools.config.to_str().expect("a path");
    let calls = tools.calls.to_str().expect("a path");

    let mut environment: Vec<(&str, &str)> = vec![
        ("XDG_CONFIG_HOME", config),
        ("KW_RULES", program),
        ("KW_CALLS", calls),
    ];
    environment.extend_from_slice(extra);
    fixture.step("04a-window-rules", &tools.path, &environment)
}

#[cfg(unix)]
fn writer_calls(tools: &WindowRules) -> Vec<String> {
    common::calls(&common::ConfigTools {
        program: tools.program.clone(),
        config: tools.config.clone(),
        calls: tools.calls.clone(),
    })
    .into_iter()
    .filter(|line| line.starts_with("kwriteconfig6 "))
    .map(|line| line.trim_start_matches("kwriteconfig6 ").to_string())
    .collect()
}

#[cfg(unix)]
fn frozen_writes(opacity: &str, index: &str) -> Vec<String> {
    let count = index.split(',').count();
    [
        "--file kwinrulesrc --group caelestia-opacity --key Description Caelestia: window opacity",
        "--file kwinrulesrc --group caelestia-opacity --key types 33",
    ]
    .into_iter()
    .map(str::to_string)
    .chain([
        format!("--file kwinrulesrc --group caelestia-opacity --key opacityinactive {opacity}"),
        "--file kwinrulesrc --group caelestia-opacity --key opacityinactiverule 2".to_string(),
        "--file kwinrulesrc --group caelestia-dialogs --key Description Caelestia: center dialogs"
            .to_string(),
        "--file kwinrulesrc --group caelestia-dialogs --key types 32".to_string(),
        "--file kwinrulesrc --group caelestia-dialogs --key placement 5".to_string(),
        "--file kwinrulesrc --group caelestia-dialogs --key placementrule 2".to_string(),
        "--file kwinrulesrc --group caelestia-pip --key Description Caelestia: pin picture-in-picture"
            .to_string(),
        "--file kwinrulesrc --group caelestia-pip --key title Picture(-| )in(-| )[Pp]icture"
            .to_string(),
        "--file kwinrulesrc --group caelestia-pip --key titlematch 3".to_string(),
        "--file kwinrulesrc --group caelestia-pip --key above true".to_string(),
        "--file kwinrulesrc --group caelestia-pip --key aboverule 2".to_string(),
        format!("--file kwinrulesrc --group General --key rules {index}"),
        format!("--file kwinrulesrc --group General --key count {count}"),
    ])
    .collect()
}

#[cfg(unix)]
const FRESH_INDEX: &str = "caelestia-opacity,caelestia-dialogs,caelestia-pip";

#[cfg(unix)]
#[test]
fn a_fresh_run_writes_the_frozen_table_in_order() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-fresh");
    let tools = config_tools(&fixture);

    let output = run_window_rules(&fixture, &tools, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        writer_calls(&tools),
        frozen_writes("95", FRESH_INDEX),
        "every key of the three groups, then the index"
    );
    assert!(
        output.stdout.contains("Window rules applied."),
        "{}",
        output.stdout
    );
    assert!(
        output.stdout.contains("Rule index names 3 group(s)."),
        "{}",
        output.stdout
    );

    let written = std::fs::read_to_string(tools.config.join("kwinrulesrc")).expect("the file");
    for pair in [
        "opacityinactive=95",
        "types=33",
        "types=32",
        "placement=5",
        "title=Picture(-| )in(-| )[Pp]icture",
        "above=true",
        "aboverule=2",
    ] {
        assert!(written.contains(pair), "{pair} is missing from {written}");
    }
    assert_eq!(written.matches("[caelestia-").count(), 3, "{written}");
}

#[cfg(unix)]
#[test]
fn a_second_run_finds_nothing_to_do() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-again");
    let tools = config_tools(&fixture);

    let _ = run_window_rules(&fixture, &tools, &[]);
    std::fs::write(&tools.calls, "").expect("a fresh call log");
    let output = run_window_rules(&fixture, &tools, &[]);

    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(writer_calls(&tools).is_empty(), "nothing should be written");
    assert!(
        output.stdout.contains("Window rules already in place."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_user_rule_keeps_its_place_in_the_index() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-user");
    let tools = config_tools(&fixture);
    std::fs::write(
        tools.config.join("kwinrulesrc"),
        "\
[General]
rules=user-rule
count=1
Order=user-rule

[user-rule]
Description=Keep this window put
wmclass=keepme

[$Version]
update_info=kwinrules.upd:fix-rule-order
",
    )
    .expect("the user's rules file");

    let output = run_window_rules(&fixture, &tools, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let index = "user-rule,caelestia-opacity,caelestia-dialogs,caelestia-pip";
    assert!(
        writer_calls(&tools).contains(&format!(
            "--file kwinrulesrc --group General --key rules {index}"
        )),
        "{:?}",
        writer_calls(&tools)
    );
    let written = std::fs::read_to_string(tools.config.join("kwinrulesrc")).expect("the file");
    assert!(
        written.contains("wmclass=keepme"),
        "the user's rule survives"
    );
    assert!(
        written.contains("Order=user-rule"),
        "their order key survives"
    );
    assert!(
        !written.contains("$Version,"),
        "the metadata group never enters the index: {written}"
    );
    assert!(
        written.contains("rules=user-rule,caelestia-opacity,caelestia-dialogs,caelestia-pip"),
        "{written}"
    );
}

#[cfg(unix)]
#[test]
fn the_reload_comes_once_and_last() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-reload");
    let tools = config_tools(&fixture);

    let _ = run_window_rules(&fixture, &tools, &[]);
    let calls = std::fs::read_to_string(&tools.calls).expect("the call log");
    let lines: Vec<&str> = calls.lines().collect();

    assert_eq!(
        lines
            .iter()
            .filter(|line| line.starts_with("qdbus6 "))
            .count(),
        1,
        "one reload, after every write: {calls}"
    );
    assert_eq!(
        lines.last().map(|line| line.starts_with("qdbus6 ")),
        Some(true),
        "{calls}"
    );
}

#[cfg(unix)]
#[test]
fn the_inactive_opacity_comes_from_the_environment() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-opacity");
    let tools = config_tools(&fixture);

    let _ = run_window_rules(&fixture, &tools, &[("WINDOW_OPACITY", "80")]);
    assert!(
        writer_calls(&tools).contains(
            &"--file kwinrulesrc --group caelestia-opacity --key opacityinactive 80".to_string()
        ),
        "{:?}",
        writer_calls(&tools)
    );
}

#[cfg(unix)]
#[test]
fn a_silent_rejection_is_reported_as_failed() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-rejected");
    let tools = config_tools(&fixture);

    let output = run_window_rules(&fixture, &tools, &[("KW_SILENT_REJECT", "1")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("could not be written"),
        "{}",
        output.stdout
    );
    assert!(
        output.stdout.contains("Window rules not fully applied"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_missing_writer_warns_instead_of_failing() {
    let fixture = Fixture::new("rules-no-writer");
    let bare = fixture.path("bare");
    std::fs::create_dir_all(&bare).expect("a directory for the bare path");

    let output = fixture.step("04a-window-rules", &bare, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("kwriteconfig6 not found - skipping window rules."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn the_step_can_be_switched_off() {
    if !process_available("python3") {
        return;
    }
    let fixture = Fixture::new("rules-off");
    let tools = config_tools(&fixture);

    let output = run_window_rules(&fixture, &tools, &[("APPLY_WINDOW_RULES", "false")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("Skipping window rules"),
        "{}",
        output.stdout
    );
    assert!(writer_calls(&tools).is_empty(), "and writes nothing");
}

#[cfg(unix)]
fn process_available(program: &str) -> bool {
    std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .any(|directory| {
            !directory.is_empty() && std::path::Path::new(directory).join(program).is_file()
        })
}

#[cfg(unix)]
fn stub_in(directory: &Path, name: &str, body: &str) -> PathBuf {
    use std::os::unix::fs::PermissionsExt;

    std::fs::create_dir_all(directory).expect("a directory for the stub");
    let path = directory.join(name);
    std::fs::write(&path, body).expect("a stub");
    let mut permissions = std::fs::metadata(&path).expect("the stub").permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&path, permissions).expect("an executable stub");
    path
}

#[cfg(unix)]
struct KdeTools {
    path: PathBuf,
    calls: PathBuf,
    state: PathBuf,
}

#[cfg(unix)]
fn kde_tools(fixture: &Fixture) -> KdeTools {
    let bin = fixture.path("bin");
    let calls = fixture.path("calls.log");
    std::fs::write(&calls, "").expect("the call log");

    stub_in(
        &bin,
        "kwriteconfig6",
        "#!/bin/sh\nprintf '%s %s\\n' 'kwriteconfig6' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "systemctl",
        "#!/bin/sh\nprintf '%s %s\\n' 'systemctl' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "qdbus6",
        "#!/bin/sh\nprintf '%s %s\\n' 'qdbus6' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "lookandfeeltool",
        "#!/bin/sh\ncase \"$1\" in
    --list) [ -n \"$KW_LNF\" ] && printf '%s\\n' \"$KW_LNF\" ;;
    --apply) printf 'applied %s\\n' \"$2\" >> \"$KW_CALLS\" ;;
esac
exit 0",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    KdeTools {
        path: PathBuf::from(format!("{}:{system}", bin.display())),
        calls,
        state: fixture.path("state"),
    }
}

#[cfg(unix)]
fn run_kde_theme(fixture: &Fixture, tools: &KdeTools, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let state = tools.state.to_str().expect("a path");
    let mut environment: Vec<(&str, &str)> = vec![
        ("KW_CALLS", calls),
        ("XDG_STATE_HOME", state),
        ("XDG_DATA_HOME", calls),
    ];
    environment.extend_from_slice(extra);

    let bundle = fixture.path("bundle");
    fixture.step_in("04-deploy-kde", &tools.path, &bundle, &environment)
}

#[cfg(unix)]
fn recorded(tools: &KdeTools, program: &str) -> Vec<String> {
    std::fs::read_to_string(&tools.calls)
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with(program))
        .map(|line| line.trim_start_matches(program).trim().to_string())
        .collect()
}

#[cfg(unix)]
#[test]
fn the_darkly_settings_are_written_once_each() {
    let fixture = Fixture::new("kde-darkly");
    let tools = kde_tools(&fixture);

    let output = run_kde_theme(&fixture, &tools, &[("KW_LNF", "Darkly")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let writes = recorded(&tools, "kwriteconfig6");
    for expected in [
        "--file plasmarc --group Theme --key name darkly",
        "--file kdeglobals --group KDE --key widgetStyle darkly",
        "--file kdeglobals --group General --key ColorScheme Darkly",
        "--file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze",
        "--file kwinrc --group org.kde.kdecoration2 --key theme Breeze",
    ] {
        assert!(writes.contains(&expected.to_string()), "{writes:?}");
    }
    assert!(
        recorded(&tools, "systemctl").contains(&"--user enable --now cliphist.service".to_string()),
        "{:?}",
        recorded(&tools, "systemctl")
    );
    assert!(
        output.stdout.contains("KDE settings applied."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn opting_out_of_darkly_leaves_the_theme_alone() {
    let fixture = Fixture::new("kde-no-darkly");
    let tools = kde_tools(&fixture);

    let output = run_kde_theme(&fixture, &tools, &[("APPLY_DARKLY", "false")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("Skipping Darkly theme"),
        "{}",
        output.stdout
    );
    assert!(
        !recorded(&tools, "kwriteconfig6")
            .iter()
            .any(|call| call.contains("widgetStyle")),
        "no application style should be chosen"
    );
}

#[cfg(unix)]
#[test]
fn the_runner_feeds_the_history_and_serves_the_persister() {
    let fixture = Fixture::new("kde-cliphist");
    let tools = kde_tools(&fixture);
    let _ = run_kde_theme(&fixture, &tools, &[]);

    let runner = fixture.path(".local/bin/caelestia-cliphist");
    assert!(runner.is_file(), "the runner is installed");

    let watchers = fixture.path("watchers.log");
    let persister = fixture.path("persister.log");
    let bin = fixture.path("runner-bin");
    stub_in(
        &bin,
        "wl-paste",
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$KW_WATCHERS\"\nexit 0\n",
    );
    stub_in(&bin, "cliphist", "#!/bin/sh\nexit 0\n");
    stub_in(
        &bin,
        "wl-clip-persist",
        "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$KW_PERSISTER\"\nexit 0\n",
    );

    let watchers_path = watchers.to_str().expect("a path").to_string();
    let persister_path = persister.to_str().expect("a path").to_string();
    let output = Command::new(&runner)
        .env(
            "PATH",
            format!(
                "{}:{}",
                bin.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        )
        .env("KW_WATCHERS", &watchers_path)
        .env("KW_PERSISTER", &persister_path)
        .output()
        .expect("the runner runs");
    assert_eq!(
        output.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let fed = std::fs::read_to_string(&watchers).unwrap_or_default();
    assert!(fed.contains("--type text --watch cliphist store"), "{fed}");
    assert!(fed.contains("--type image --watch cliphist store"), "{fed}");

    let serve = std::fs::read_to_string(&persister).unwrap_or_default();
    let lines: Vec<&str> = serve.lines().collect();
    assert_eq!(
        lines.first().map(|line| line.contains("--clipboard")),
        Some(true),
        "{lines:?}"
    );
    assert_eq!(
        lines.get(1).map(|line| line.contains("regular")),
        Some(true),
        "{lines:?}"
    );
    assert_eq!(
        lines
            .get(2)
            .map(|line| line.contains("--all-mime-type-regex")),
        Some(true),
        "{lines:?}"
    );
    assert_eq!(
        lines
            .get(3)
            .map(|line| line.contains("application/x-krita-")
                && line.contains("image/x-inkscape-svg")),
        Some(true),
        "the filter reaches the tool as one argument: {lines:?}"
    );
    assert_eq!(lines.len(), 4, "{lines:?}");
}

#[cfg(unix)]
#[test]
fn a_missing_helper_is_reported() {
    let fixture = Fixture::new("kde-cliphist-missing");
    let tools = kde_tools(&fixture);
    let _ = run_kde_theme(&fixture, &tools, &[]);

    let runner = fixture.path(".local/bin/caelestia-cliphist");
    let bin = fixture.path("runner-bin");
    stub_in(&bin, "wl-paste", "#!/bin/sh\nexit 0\n");
    stub_in(&bin, "cliphist", "#!/bin/sh\nexit 0\n");

    let output = Command::new(&runner)
        .env("PATH", bin.display().to_string())
        .output()
        .expect("the runner runs");
    assert_eq!(output.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("missing: wl-clip-persist"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
fn the_wallpaper_in_use_is_kept_and_matched_to_the_logout_screen() {
    let fixture = Fixture::new("kde-wallpaper-keep");
    let tools = kde_tools(&fixture);
    let chosen = fixture.path("Pictures/My Walls/mine.png");
    std::fs::create_dir_all(chosen.parent().expect("a parent")).expect("the pictures directory");
    std::fs::write(&chosen, b"png").expect("the wallpaper");

    let state = fixture.path("state/caelestia/wallpaper");
    std::fs::create_dir_all(&state).expect("the state directory");
    std::fs::write(state.join("path.txt"), format!("{}\n", chosen.display())).expect("the record");

    let output = run_kde_theme(&fixture, &tools, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Keeping the wallpaper in use: mine.png"),
        "{}",
        output.stdout
    );

    let log = std::fs::read_to_string(&tools.calls).expect("the call log");
    assert!(log.contains("d.writeConfig('Image'"), "{log}");
    assert!(
        log.contains("My\\u0020Walls"),
        "a space reaches the script escaped, not raw: {log}"
    );
    assert!(
        log.contains("file:///"),
        "and the slashes are left as they are: {log}"
    );
}

#[cfg(unix)]
#[test]
fn the_default_wallpaper_is_recorded_and_given_to_the_logout_screen() {
    let fixture = Fixture::new("kde-wallpaper-default");
    let tools = kde_tools(&fixture);

    let fallback = fixture.path("bundle/shell/assets/wallpaper.webp");
    std::fs::create_dir_all(fallback.parent().expect("a parent")).expect("the assets directory");
    std::fs::write(&fallback, b"webp").expect("the fallback wallpaper");

    let output = run_kde_theme(&fixture, &tools, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Setting default wallpaper to wallpaper.webp"),
        "{}",
        output.stdout
    );

    let recorded_path = fixture.path("state/caelestia/wallpaper/path.txt");
    assert_eq!(
        std::fs::read_to_string(&recorded_path)
            .expect("the record")
            .trim(),
        fallback.display().to_string()
    );

    let writes = recorded(&tools, "kwriteconfig6");
    assert!(
        writes.contains(
            &"--file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image"
                .to_string()
        ),
        "{writes:?}"
    );
    assert!(
        writes
            .iter()
            .any(|call| call.contains("--group Greeter --group Wallpaper")),
        "{writes:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_missing_wallpaper_leaves_the_desktop_alone() {
    let fixture = Fixture::new("kde-wallpaper-none");
    let tools = kde_tools(&fixture);

    let output = run_kde_theme(&fixture, &tools, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(recorded(&tools, "qdbus6").is_empty(), "nothing to set");
    assert!(!fixture.path("state/caelestia/wallpaper/path.txt").exists());
}

#[cfg(unix)]
struct Autostart {
    path: PathBuf,
    calls: PathBuf,
}

#[cfg(unix)]
fn autostart_tools(fixture: &Fixture) -> Autostart {
    let bin = fixture.path("bin");
    let calls = fixture.path("calls.log");
    std::fs::write(&calls, "").expect("the call log");

    stub_in(
        &bin,
        "systemctl",
        "#!/bin/sh\nprintf '%s %s\\n' 'systemctl' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(&bin, "update-desktop-database", "#!/bin/sh\nexit 0\n");
    stub_in(&bin, "kbuildsycoca6", "#!/bin/sh\nexit 0\n");
    stub_in(
        &bin,
        "quickshell",
        "#!/bin/sh\n[ \"${KW_FAIL_QUICKSHELL:-}\" = 1 ] && exit 1\nexit 0\n",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    Autostart {
        path: PathBuf::from(format!("{}:{system}", bin.display())),
        calls,
    }
}

#[cfg(unix)]
fn run_autostart(fixture: &Fixture, tools: &Autostart, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let mut environment: Vec<(&str, &str)> = vec![("KW_CALLS", calls)];
    environment.extend_from_slice(extra);
    let bundle = fixture.path("bundle");
    fixture.step_in("10-autostart", &tools.path, &bundle, &environment)
}

#[cfg(unix)]
fn autostart_calls(tools: &Autostart) -> Vec<String> {
    std::fs::read_to_string(&tools.calls)
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with("systemctl"))
        .map(|line| line.trim_start_matches("systemctl").trim().to_string())
        .collect()
}

#[cfg(unix)]
#[test]
fn a_source_install_writes_the_launcher_the_unit_and_the_interface_declaration() {
    let fixture = Fixture::new("autostart-source");
    let tools = autostart_tools(&fixture);
    let shell_config = fixture.path(".config/quickshell/caelestia/shell.qml");
    std::fs::create_dir_all(shell_config.parent().expect("a parent")).expect("the config tree");
    std::fs::write(&shell_config, b"// shell").expect("the entrypoint");

    let source = fixture.path("bundle/assets/org.quickshell.desktop");
    std::fs::create_dir_all(source.parent().expect("a parent")).expect("the assets directory");
    std::fs::write(
        &source,
        "[Desktop Entry]\nExec=/usr/bin/quickshell\nX-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1\n",
    )
    .expect("the asset");

    let output = run_autostart(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let launcher = fixture.path(".local/bin/caelestia-autostart.sh");
    assert!(launcher.is_file(), "the launcher is installed");
    let script = std::fs::read_to_string(&launcher).expect("the launcher");
    assert!(
        script.contains("exec \"") && script.contains("\" -n -p \""),
        "it starts the entrypoint the install named: {script}"
    );
    assert!(
        script.contains(&shell_config.display().to_string()),
        "and the entrypoint is the one this install has: {script}"
    );

    let unit = fixture.path(".config/systemd/user/caelestia-shell.service");
    let unit_text = std::fs::read_to_string(&unit).expect("the unit");
    assert!(unit_text.contains("ExecStart=%h/.local/bin/caelestia-autostart.sh"));
    assert!(unit_text.contains("Before=xdg-desktop-autostart.target"));

    let calls = autostart_calls(&tools);
    assert!(
        calls.contains(&"--user reset-failed caelestia-shell.service".to_string()),
        "a failed unit is cleared before it is used: {calls:?}"
    );
    assert!(
        calls.contains(&"--user enable caelestia-shell.service".to_string()),
        "{calls:?}"
    );

    let declaration = fixture.path(".local/share/applications/quickshell.desktop");
    let declaration_text = std::fs::read_to_string(&declaration).expect("the declaration");
    assert!(declaration_text.contains("X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1"));

    let preview = fixture.path(".local/share/applications/org.quickshell.desktop");
    let preview_text = std::fs::read_to_string(&preview).expect("the preview declaration");
    assert!(
        preview_text.contains("Exec=/") && !preview_text.contains("Exec=/usr/bin/quickshell"),
        "the exec line points at the resolved binary: {preview_text}"
    );
    assert!(
        output.stdout.contains("Autostart entries configured."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_packaged_install_takes_the_users_own_copies_out_of_the_way() {
    let fixture = Fixture::new("autostart-package");
    let tools = autostart_tools(&fixture);
    let unit = fixture.path(".config/systemd/user/caelestia-shell.service");
    let launcher = fixture.path(".local/bin/caelestia-autostart.sh");
    std::fs::create_dir_all(unit.parent().expect("a parent")).expect("the unit directory");
    std::fs::create_dir_all(launcher.parent().expect("a parent")).expect("the bin directory");
    std::fs::write(&unit, b"stale").expect("a stale unit");
    std::fs::write(&launcher, b"stale").expect("a stale launcher");

    let output = run_autostart(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "package")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(!unit.exists(), "the user's copy of the unit goes");
    assert!(!launcher.exists(), "and the user's copy of the launcher");
    assert!(
        output.stdout.contains("the package's is the one to use"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn the_retired_entries_and_a_dead_enable_link_do_not_survive() {
    let fixture = Fixture::new("autostart-retire");
    let tools = autostart_tools(&fixture);
    let shell_config = fixture.path(".config/quickshell/caelestia/shell.qml");
    std::fs::create_dir_all(shell_config.parent().expect("a parent")).expect("the config tree");
    std::fs::write(&shell_config, b"// shell").expect("the entrypoint");

    let retired = fixture.path(".config/autostart/caelestiashell.desktop");
    std::fs::create_dir_all(retired.parent().expect("a parent")).expect("the autostart directory");
    std::fs::write(&retired, b"[Desktop Entry]").expect("the retired entry");

    let wants = fixture.path(".config/systemd/user/graphical-session.target.wants");
    std::fs::create_dir_all(&wants).expect("the wants directory");
    let dead = wants.join("caelestia-shell.service");
    std::os::unix::fs::symlink(fixture.path("gone"), &dead).expect("a dead link");

    let material_you = fixture.path(".config/systemd/user/kde-material-you-colors.service");
    std::fs::write(&material_you, b"[Unit]").expect("the material-you unit");
    let scheme = fixture.path(".local/share/color-schemes/MaterialYou.colors");
    std::fs::create_dir_all(scheme.parent().expect("a parent")).expect("the schemes directory");
    std::fs::write(&scheme, b"[Colors]").expect("a generated scheme");

    let output = run_autostart(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert!(!retired.exists(), "the retired autostart entry goes");
    assert!(!dead.exists(), "a dead enable link goes");
    assert!(!material_you.exists(), "the material-you unit goes");
    assert!(!scheme.exists(), "and the scheme it generated");

    let calls = autostart_calls(&tools);
    assert!(
        calls.contains(&"--user disable app-caelestiashell@autostart.service".to_string()),
        "{calls:?}"
    );
    assert!(
        calls.contains(&"--user disable --now kde-material-you-colors.service".to_string()),
        "{calls:?}"
    );
}

#[cfg(unix)]
#[test]
fn the_isolated_autostart_step_is_idempotent() {
    let fixture = Fixture::new("autostart-again");
    let tools = autostart_tools(&fixture);
    let shell_config = fixture.path(".config/quickshell/caelestia/shell.qml");
    std::fs::create_dir_all(shell_config.parent().expect("a parent")).expect("the config tree");
    std::fs::write(&shell_config, b"// shell").expect("the entrypoint");

    let launcher = fixture.path(".local/bin/caelestia-autostart.sh");
    let unit = fixture.path(".config/systemd/user/caelestia-shell.service");
    let declaration = fixture.path(".local/share/applications/quickshell.desktop");

    let first = run_autostart(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(first.code, Some(0), "{}", first.stderr);
    let before = [
        std::fs::read(&launcher).expect("the launcher"),
        std::fs::read(&unit).expect("the unit"),
        std::fs::read(&declaration).expect("the declaration"),
    ];

    let second = run_autostart(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(second.code, Some(0), "{}", second.stderr);
    let after = [
        std::fs::read(&launcher).expect("the launcher"),
        std::fs::read(&unit).expect("the unit"),
        std::fs::read(&declaration).expect("the declaration"),
    ];

    assert_eq!(
        before, after,
        "repeating the step keeps the files it generates byte for byte"
    );
}

#[cfg(unix)]
#[test]
fn without_quickshell_the_step_refuses_to_configure_anything() {
    let fixture = Fixture::new("autostart-no-quickshell");
    let bare = fixture.path("bare");
    std::fs::create_dir_all(&bare).expect("a directory for the bare path");

    let output = fixture.step(
        "10-autostart",
        &bare,
        &[("CAELESTIA_INSTALL_KIND", "source")],
    );
    assert_eq!(output.code, Some(1));
    assert!(
        output
            .stderr
            .contains("Quickshell is not installed or is not available in PATH."),
        "{}",
        output.stderr
    );
    assert!(
        !fixture
            .path(".config/systemd/user/caelestia-shell.service")
            .exists()
    );
}

#[cfg(unix)]
fn desktop_calls(fixture: &Fixture) -> Vec<String> {
    std::fs::read_to_string(fixture.path("calls.log"))
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with("kwriteconfig6 "))
        .filter(|line| line.contains("--group Desktops --key"))
        .map(|line| line.trim_start_matches("kwriteconfig6 ").to_string())
        .collect()
}

#[cfg(unix)]
#[test]
fn a_fresh_install_without_a_desktop_count_gets_five_named_desktops() {
    let fixture = Fixture::new("desktops-fresh");
    let tools = services_tools(&fixture);

    let output = run_services(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "1"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let written = desktop_calls(&fixture);
    assert!(
        written.contains(&"--file kwinrc --group Desktops --key Number 5".to_string()),
        "{written:?}"
    );
    assert!(
        written.contains(&"--file kwinrc --group Desktops --key Rows 1".to_string()),
        "the desktops are laid out in one row: {written:?}"
    );
    assert!(
        written.contains(&"--file kwinrc --group Desktops --key Name_5 Desktop 5".to_string()),
        "every desktop is named: {written:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_fresh_install_at_kwins_own_default_of_one_gets_five() {
    let fixture = Fixture::new("desktops-default");
    let tools = services_tools(&fixture);

    let output = run_services(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "1"),
            ("KW_DESKTOPS", "1"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let written = desktop_calls(&fixture);
    assert!(
        written.contains(&"--file kwinrc --group Desktops --key Number 5".to_string()),
        "a kwinrc carrying KWin's own default is not a user's configuration: {written:?}"
    );
    assert!(
        written.contains(&"--file kwinrc --group Desktops --key Name_1 Desktop 1".to_string()),
        "{written:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_fresh_install_keeps_a_desktop_count_the_user_chose() {
    let fixture = Fixture::new("desktops-chosen");
    let tools = services_tools(&fixture);

    let output = run_services(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "1"),
            ("KW_DESKTOPS", "3"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        desktop_calls(&fixture),
        Vec::<String>::new(),
        "the desktops a user configured are left alone"
    );
    assert!(
        output
            .stdout
            .contains("Keeping the existing 3 virtual desktops."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn an_update_never_touches_the_desktop_count() {
    for count in ["1", ""] {
        let fixture = Fixture::new("desktops-update");
        let tools = services_tools(&fixture);

        let output = run_services(
            &fixture,
            &tools,
            &[
                ("CAELESTIA_INSTALL_KIND", "package"),
                ("CAELESTIA_FRESH_INSTALL", "0"),
                ("KW_DESKTOPS", count),
            ],
        );
        assert_eq!(output.code, Some(0), "{}", output.stderr);
        assert_eq!(
            desktop_calls(&fixture),
            Vec::<String>::new(),
            "an update must not be read as an install"
        );
        assert!(
            output.stdout.contains("Not an install"),
            "{}",
            output.stdout
        );
    }
}

#[cfg(unix)]
fn run_tweaks(fixture: &Fixture, tools: &Services, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let state = fixture.path("state").to_string_lossy().to_string();
    let mut environment: Vec<(&str, &str)> = vec![("KW_CALLS", calls), ("XDG_STATE_HOME", &state)];
    environment.extend_from_slice(extra);
    let bundle = fixture.path("bundle");
    fixture.step_in("09-system-tweaks", &tools.path, &bundle, &environment)
}

#[cfg(unix)]
fn settings_written(fixture: &Fixture) -> Vec<String> {
    std::fs::read_to_string(fixture.path("calls.log"))
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with("kwriteconfig6 "))
        .map(|line| line.trim_start_matches("kwriteconfig6 ").to_string())
        .collect()
}

#[cfg(unix)]
#[test]
fn the_osd_the_splash_and_the_kde_daemons_are_turned_off() {
    let fixture = Fixture::new("tweaks-settings");
    let tools = services_tools(&fixture);

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let written = settings_written(&fixture);
    for expected in [
        "--file plasmarc --group OSD --key Enabled false",
        "--file plasmarc --group OSD --key ShowOnActiveScreen false",
        "--file kdeglobals --group KDE --key OSDEnabled false",
        "--file plasmanotifyrc --group Notifications --key LoudnessChangedOSD false",
        "--file powerdevilrc --group BrightnessControl --key showOSD false",
        "--file powerdevilrc --group AC --key brightnessosd false",
        "--file kmixrc --group Global --key ShowOSD false",
        "--file ksplashrc --group KSplash --key Engine none",
    ] {
        assert!(
            written.contains(&expected.to_string()),
            "{expected}: {written:?}"
        );
    }

    assert!(
        output.stdout.contains("All system tweaks applied."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn the_shell_profiles_are_pointed_at_the_default_shell() {
    let fixture = Fixture::new("tweaks-shell");
    let tools = services_tools(&fixture);
    let konsole = fixture.path(".local/share/konsole");
    std::fs::create_dir_all(&konsole).expect("a konsole directory");
    std::fs::write(konsole.join("Caelestia.profile"), b"[General]\n").expect("a profile");
    stub_in(&fixture.path("bin"), "fish", "#!/bin/sh\nexit 0\n");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let profile = konsole
        .join("Caelestia.profile")
        .to_string_lossy()
        .to_string();
    let written = settings_written(&fixture);
    assert!(
        written.iter().any(|call| call
            .starts_with(&format!("--file {profile} --group General --key Command "))
            && call.ends_with("fish")),
        "the profile's shell should be the one that was found: {written:?}"
    );
    assert!(
        !written
            .iter()
            .any(|call| call.contains("Profile 1.profile")),
        "a profile that exists is updated rather than a second one invented: {written:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_first_profile_is_written_only_when_there_is_none_to_update() {
    let fixture = Fixture::new("tweaks-shell-empty");
    let tools = services_tools(&fixture);
    stub_in(&fixture.path("bin"), "fish", "#!/bin/sh\nexit 0\n");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let written = settings_written(&fixture);
    assert!(
        written.iter().any(|call| call.contains("Profile 1.profile")
            && call.contains("--key Name Profile 1")),
        "{written:?}"
    );
    assert!(
        written.iter().any(|call| call.contains("konsolerc")
            && call.contains("--key DefaultProfile Profile 1.profile")),
        "{written:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_shell_that_is_not_installed_is_a_warning_and_leaves_the_profiles_alone() {
    let fixture = Fixture::new("tweaks-shell-absent");
    let tools = services_tools(&fixture);
    let konsole = fixture.path(".local/share/konsole");
    std::fs::create_dir_all(&konsole).expect("a konsole directory");
    std::fs::write(konsole.join("Caelestia.profile"), b"[General]\n").expect("a profile");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
            ("DEFAULT_SHELL", "a-shell-that-is-not-installed"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("is not installed, skipping shell change."),
        "{}",
        output.stdout
    );
    assert_eq!(
        settings_written(&fixture)
            .iter()
            .filter(|call| call.contains("konsole"))
            .count(),
        0,
        "no profile is touched for a shell that is not there"
    );
}

#[cfg(unix)]
#[test]
fn a_scheme_the_user_chose_is_kept_and_the_default_is_set_otherwise() {
    for (current, kept) in [("nord", true), ("dynamic", false)] {
        let fixture = Fixture::new("tweaks-scheme");
        let tools = services_tools(&fixture);
        stub_in(
            &fixture.path("bin"),
            "caelestia",
            &format!(
                "#!/bin/sh\nprintf 'caelestia %s\\n' \"$*\" >> \"$KW_CALLS\"\n[ \"$1 $2 $3\" = 'scheme get -n' ] && printf '{current}\\n'\nexit 0\n"
            ),
        );

        let output = run_tweaks(
            &fixture,
            &tools,
            &[
                ("CAELESTIA_INSTALL_KIND", "package"),
                ("CAELESTIA_FRESH_INSTALL", "0"),
            ],
        );
        assert_eq!(output.code, Some(0), "{}", output.stderr);

        let calls: Vec<String> = std::fs::read_to_string(fixture.path("calls.log"))
            .unwrap_or_default()
            .lines()
            .filter(|line| line.starts_with("caelestia "))
            .map(|line| line.trim_start_matches("caelestia ").to_string())
            .collect();

        if kept {
            assert_eq!(calls, ["scheme get -n"], "a chosen scheme is left alone");
            assert!(
                output
                    .stdout
                    .contains("Keeping user-selected Caelestia color scheme (nord)."),
                "{}",
                output.stdout
            );
        } else {
            assert!(
                calls.contains(&"scheme set -n dynamic".to_string()),
                "the default is applied: {calls:?}"
            );
        }
    }
}

#[cfg(unix)]
#[test]
fn a_wallpaper_that_is_there_is_given_to_the_shell_before_the_scheme_is_set() {
    let fixture = Fixture::new("tweaks-wallpaper");
    let tools = services_tools(&fixture);
    stub_in(
        &fixture.path("bin"),
        "caelestia",
        "#!/bin/sh\nprintf 'caelestia %s\\n' \"$*\" >> \"$KW_CALLS\"\n[ \"$1 $2 $3\" = 'scheme get -n' ] && printf 'dynamic\\n'\nexit 0\n",
    );

    let state = fixture.path("state/caelestia");
    std::fs::create_dir_all(state.join("wallpaper")).expect("the wallpaper state directory");
    let image = fixture.path("wall.png");
    std::fs::write(&image, b"png").expect("the wallpaper");
    std::fs::write(
        state.join("wallpaper/path.txt"),
        image.to_string_lossy().to_string(),
    )
    .expect("the recorded wallpaper");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let calls: Vec<String> = std::fs::read_to_string(fixture.path("calls.log"))
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with("caelestia "))
        .map(|line| line.trim_start_matches("caelestia ").to_string())
        .collect();

    let wallpaper_at = calls
        .iter()
        .position(|call| call.starts_with("wallpaper -f "))
        .expect("the recorded wallpaper is applied");
    let scheme_at = calls
        .iter()
        .position(|call| call == "scheme set -n dynamic")
        .expect("the scheme is set");
    assert!(
        wallpaper_at < scheme_at,
        "the wallpaper has to be in place before the scheme follows it: {calls:?}"
    );
}

#[cfg(unix)]
#[test]
fn a_panel_is_removed_from_the_config_when_plasma_cannot_be_reached() {
    let fixture = Fixture::new("tweaks-panels");
    let tools = services_tools(&fixture);

    let appletsrc = fixture.path(".config/plasma-org.kde.plasma.desktop-appletsrc");
    std::fs::create_dir_all(appletsrc.parent().expect("a parent")).expect("the config directory");
    std::fs::write(
        &appletsrc,
        "[Containments][1]\nplugin=org.kde.plasma.folder\n\n\
         [Containments][2]\nplugin=org.kde.plasma.panel\nformfactor=2\n\n\
         [Containments][2][Applets][3]\nplugin=org.kde.plasma.systemtray\n\n\
         [General]\n",
    )
    .expect("the desktop layout");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "1"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let rewritten = std::fs::read_to_string(&appletsrc).expect("the rewritten layout");
    assert!(
        !rewritten.contains("[Containments][2]"),
        "the panel and its applets go: {rewritten}"
    );
    assert!(
        rewritten.contains("[Containments][1]") && rewritten.contains("[General]"),
        "and the rest of the layout stays: {rewritten}"
    );
    assert!(
        output.stdout.contains("Removed 1 KDE panel(s)"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_desktop_the_user_already_configured_keeps_its_panels() {
    let fixture = Fixture::new("tweaks-panels-kept");
    let tools = services_tools(&fixture);

    let appletsrc = fixture.path(".config/plasma-org.kde.plasma.desktop-appletsrc");
    std::fs::create_dir_all(appletsrc.parent().expect("a parent")).expect("the config directory");
    let layout = "[Containments][2]\nplugin=org.kde.plasma.panel\nformfactor=2\n";
    std::fs::write(&appletsrc, layout).expect("the desktop layout");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "1"),
            ("KW_DESKTOPS", "3"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        std::fs::read_to_string(&appletsrc).expect("the layout"),
        layout,
        "a desktop with a count of its own is one this install did not create"
    );
    assert!(
        output
            .stdout
            .contains("Not a first install - leaving Plasma panels alone."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn an_update_never_removes_panels() {
    let fixture = Fixture::new("tweaks-panels-update");
    let tools = services_tools(&fixture);

    let appletsrc = fixture.path(".config/plasma-org.kde.plasma.desktop-appletsrc");
    std::fs::create_dir_all(appletsrc.parent().expect("a parent")).expect("the config directory");
    let layout = "[Containments][2]\nplugin=org.kde.plasma.panel\nformfactor=2\n";
    std::fs::write(&appletsrc, layout).expect("the desktop layout");

    let output = run_tweaks(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        std::fs::read_to_string(&appletsrc).expect("the layout"),
        layout,
        "an update must not delete a panel somebody recreated"
    );
}

#[cfg(unix)]
struct LoginScreen {
    path: PathBuf,
    calls: PathBuf,
    sudo: PathBuf,
}

// The step writes to /usr and /etc, so the two system directories it owns are pointed at a
// tree the test owns, and the sudo it escalates through is a stub that refuses anything
// under /etc - a test must not be able to write a sudoers rule on the machine it runs on.
#[cfg(unix)]
fn login_tools(fixture: &Fixture) -> LoginScreen {
    let bin = fixture.path("bin");
    let calls = fixture.path("calls.log");
    std::fs::write(&calls, "").expect("the call log");

    let sudo = stub_in(
        &bin,
        "sudo",
        "#!/bin/sh\ncase \"$*\" in\n    '-n -v'*) exit 0 ;;\nesac\nprintf 'sudo %s\\n' \"$*\" >> \"$KW_CALLS\"\n\
         for arg in \"$@\"; do\n    case \"$arg\" in /etc/*) exit 1 ;; esac\ndone\nshift\nexec \"$@\"\n",
    );
    stub_in(
        &bin,
        "systemctl",
        "#!/bin/sh\n[ \"${KW_PLASMALOGIN:-}\" = 1 ] && case \"$*\" in *plasmalogin*) exit 0 ;; esac\nexit 1\n",
    );
    stub_in(
        &bin,
        "readlink",
        "#!/bin/sh\nprintf '%s\\n' \"${KW_DM_ALIAS:-}\"\n",
    );
    stub_in(
        &bin,
        "kwriteconfig6",
        "#!/bin/sh\nprintf 'kwriteconfig6 %s\\n' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "kreadconfig6",
        "#!/bin/sh\n[ -n \"${KW_SELECTION:-}\" ] && printf '%s\\n' \"$KW_SELECTION\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "visudo",
        "#!/bin/sh\nexit \"${KW_VISUDO_FAILS:-0}\"\n",
    );
    stub_in(&bin, "sddm-greeter-qt6", "#!/bin/sh\nexit 0\n");
    // The greeter's packages are the distribution's business: this reports them present so
    // that the dependency stage is exercised without a package manager on the test host.
    stub_in(
        &bin,
        "pacman",
        "#!/bin/sh\nprintf 'pacman %s\\n' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    LoginScreen {
        path: PathBuf::from(format!("{}:{system}", bin.display())),
        calls,
        sudo,
    }
}

#[cfg(unix)]
fn theme_fixture(fixture: &Fixture, variant: &str, qt_version: &str) {
    let theme = fixture.path("theme");
    std::fs::create_dir_all(&theme).expect("the theme directory");
    std::fs::write(
        theme.join("metadata.desktop"),
        format!("[SddmGreeterTheme]\nQtVersion={qt_version}\n"),
    )
    .expect("the metadata");
    std::fs::write(theme.join("Main.qml"), "// theme\n").expect("the entrypoint");
    std::fs::write(theme.join("theme.conf"), "[General]\n").expect("the theme config");

    let assets = theme.join("assets/google-sans-flex");
    std::fs::create_dir_all(&assets).expect("the font directory");
    std::fs::write(assets.join("GoogleSansFlex.ttf"), b"font").expect("the font");

    let installed = fixture.path("installed");
    std::fs::create_dir_all(&installed).expect("the installed theme directory");
    std::fs::write(
        installed.join("metadata.desktop"),
        format!("[SddmGreeterTheme]\nQtVersion={qt_version}\n"),
    )
    .expect("the metadata");
    std::fs::write(installed.join("theme.conf"), "[General]\n").expect("the theme config");
    std::fs::write(installed.join("Main.qml"), "// theme\n").expect("the entrypoint");
    if variant == "mini" {
        std::fs::create_dir_all(installed.join("singletons")).expect("the singletons");
    }
    std::fs::create_dir_all(installed.join("scripts")).expect("the scripts directory");
    stub_in(&installed.join("scripts"), "sync.sh", "#!/bin/sh\nexit 0\n");
    std::fs::write(installed.join("theme.conf.template"), "[General]\n").expect("the template");
}

#[cfg(unix)]
fn run_login(fixture: &Fixture, tools: &LoginScreen, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let sudo = tools.sudo.to_str().expect("a path");
    let mut environment: Vec<(&str, &str)> = vec![
        ("CAELESTIA_FRESH_INSTALL", "0"),
        ("KW_CALLS", calls),
        ("CAELESTIA_SUDO_BIN", sudo),
    ];
    environment.extend_from_slice(extra);
    let bundle = fixture.path("bundle");
    fixture.step_in("05-sddm-theme", &tools.path, &bundle, &environment)
}

#[cfg(unix)]
#[test]
fn a_packaged_install_installs_no_theme_files_and_selects_none() {
    let fixture = Fixture::new("login-packaged");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            (
                "CAELESTIA_SDDM_CONF_DIR",
                &fixture.path("conf.d").to_string_lossy(),
            ),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert!(
        output
            .stdout
            .contains("The theme files belong to the package."),
        "{}",
        output.stdout
    );
    assert!(
        output
            .stdout
            .contains("The theme selection belongs to the package."),
        "{}",
        output.stdout
    );
    assert!(
        !fixture.path("conf.d").join("zz-caelestia.conf").exists(),
        "a package does not write a selection of its own"
    );
    assert!(
        fixture
            .path(".config/caelestia/templates/sddm-theme.conf")
            .is_file(),
        "but the theme's template is still offered to the user"
    );
}

#[cfg(unix)]
#[test]
fn the_packaged_install_registers_the_posthook_and_its_sudoers_rule() {
    let fixture = Fixture::new("login-posthook");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    let theme_dir = fixture.text("installed");
    let conf_dir = fixture.text("conf.d");
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "package"),
        ("CAELESTIA_SDDM_THEME_DIR", theme_dir.as_str()),
        ("CAELESTIA_SDDM_CONF_DIR", conf_dir.as_str()),
    ];

    let output = run_login(&fixture, &tools, &environment);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let cli = std::fs::read_to_string(fixture.path(".config/caelestia/cli.json"))
        .expect("the posthook registration wrote the config");
    assert!(
        cli.contains("--posthook"),
        "the hook the login screen sync runs should be recorded: {cli}"
    );
    assert!(
        cli.contains(&format!(
            "{}/scripts/sync.sh",
            fixture.path("installed").display()
        )),
        "and it should name the helper the package installed: {cli}"
    );
    assert!(
        output.stdout.contains("Posthook registered in cli.json"),
        "{}",
        output.stdout
    );

    let calls = std::fs::read_to_string(&tools.calls).unwrap_or_default();
    assert!(
        calls.contains("visudo -cf"),
        "the rule is checked first: {calls}"
    );
    assert!(
        calls.contains("install -m 0440 -o root -g root"),
        "and installed with the mode sudoers demands: {calls}"
    );

    let second = run_login(&fixture, &tools, &environment);
    assert_eq!(second.code, Some(0), "{}", second.stderr);
    assert_eq!(
        cli,
        std::fs::read_to_string(fixture.path(".config/caelestia/cli.json")).expect("the config"),
        "a second run leaves one hook, not two"
    );
}

#[cfg(unix)]
#[test]
fn a_sudoers_rule_that_does_not_validate_is_not_installed() {
    let fixture = Fixture::new("login-visudo");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            (
                "CAELESTIA_SDDM_CONF_DIR",
                &fixture.path("conf.d").to_string_lossy(),
            ),
            ("KW_VISUDO_FAILS", "1"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("did not validate; leaving sudoers alone."),
        "{}",
        output.stdout
    );

    let calls = std::fs::read_to_string(&tools.calls).unwrap_or_default();
    assert!(
        !calls.contains("install -m 0440"),
        "a rule that does not validate must never reach sudoers: {calls}"
    );
}

#[cfg(unix)]
#[test]
fn a_package_without_its_theme_says_so_instead_of_installing_one() {
    let fixture = Fixture::new("login-no-theme");
    let tools = login_tools(&fixture);
    std::fs::create_dir_all(fixture.path("installed")).expect("an empty theme directory");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
        ],
    );
    assert_eq!(output.code, Some(1));
    assert!(
        output
            .stderr
            .contains("login screen theme is not installed at"),
        "{}",
        output.stderr
    );
}

#[cfg(unix)]
#[test]
fn a_reinstall_keeps_a_mini_theme_mini() {
    // The installed theme is what says which variant this is, so a mini theme that is
    // installed over stays mini instead of being replaced by the default full one.
    let fixture = Fixture::new("login-variant");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "mini", "6");

    for (variant, marker) in [("full", "full"), ("mini", "mini")] {
        let source = fixture.path("bundle/src/sddm/themes").join(variant);
        std::fs::create_dir_all(&source).expect("the source theme");
        std::fs::write(source.join("Main.qml"), format!("// {marker}\n")).expect("the entrypoint");
        std::fs::write(source.join("theme.conf"), "[General]\n").expect("the theme config");
    }
    // The mini theme takes its shapes from the full one's tree.
    let shapes = fixture.path("bundle/src/sddm/themes/full/components/shapes");
    std::fs::create_dir_all(&shapes).expect("the shapes");
    std::fs::write(shapes.join("Shape.qml"), "// shape\n").expect("the shape");
    stub_in(
        &fixture.path("bundle/src/sddm"),
        "sync.sh",
        "#!/bin/sh\nexit 0\n",
    );

    let installed = fixture.path("installed");
    let installed_dir = installed.to_string_lossy().to_string();
    let conf_dir = fixture.text("conf.d");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BASE_DISTRO", "arch"),
            ("CAELESTIA_SDDM_THEME_DIR", &installed_dir),
            ("CAELESTIA_SDDM_CONF_DIR", &conf_dir),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert_eq!(
        std::fs::read_to_string(installed.join("Main.qml")).expect("the entrypoint"),
        "// mini\n",
        "the variant the installed theme declared is the one that is installed again"
    );
    assert!(
        installed.join("components/shapes/Shape.qml").is_file(),
        "and the mini theme is given the shapes it takes from the full one"
    );
}

#[cfg(unix)]
#[test]
fn a_variant_that_is_not_one_is_refused_before_anything_is_written() {
    let fixture = Fixture::new("login-bad-variant");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            ("SDDM_THEME_VARIANT", "huge"),
        ],
    );
    assert_eq!(output.code, Some(1));
    assert!(
        output.stderr.contains("Unknown SDDM theme variant: huge"),
        "{}",
        output.stderr
    );
}

#[cfg(unix)]
#[test]
fn the_login_screen_step_can_be_switched_off() {
    let fixture = Fixture::new("login-off");
    let tools = login_tools(&fixture);

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("INSTALL_SDDM", "false"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("SDDM theme not selected."),
        "{}",
        output.stdout
    );
    assert!(
        !fixture.path("calls.log").exists()
            || std::fs::read_to_string(fixture.path("calls.log"))
                .expect("the log")
                .is_empty(),
        "nothing is asked of the system when the theme is not wanted"
    );
}

#[cfg(unix)]
#[test]
fn a_theme_without_a_greeter_is_installed_but_left_unselected() {
    let fixture = Fixture::new("login-no-greeter");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");
    // A Qt version nothing on this machine can run: the step must not select the theme.
    std::fs::write(
        fixture.path("installed/metadata.desktop"),
        "[SddmGreeterTheme]\nQtVersion=9\n",
    )
    .expect("the metadata");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            (
                "CAELESTIA_SDDM_CONF_DIR",
                &fixture.path("conf.d").to_string_lossy(),
            ),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("SDDM has no sddm-greeter-qt9"),
        "{}",
        output.stdout
    );
    assert!(
        output
            .stdout
            .contains("The package selects the theme anyway."),
        "and a packaged install is told the package has already selected it: {}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_theme_that_cannot_run_takes_an_earlier_selection_back() {
    let fixture = Fixture::new("login-revert");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    // The checkout's theme declares a Qt version nothing here can run.
    let source = fixture.path("bundle/src/sddm/themes/full");
    std::fs::create_dir_all(&source).expect("the source theme");
    for (name, body) in [
        ("Main.qml", "// theme\n"),
        ("theme.conf", "[General]\n"),
        ("metadata.desktop", "[SddmGreeterTheme]\nQtVersion=9\n"),
    ] {
        std::fs::write(source.join(name), body).expect("a theme file");
    }
    stub_in(
        &fixture.path("bundle/src/sddm"),
        "sync.sh",
        "#!/bin/sh\nexit 0\n",
    );

    let conf = fixture.path("conf.d");
    std::fs::create_dir_all(&conf).expect("the drop-in directory");
    std::fs::write(
        conf.join("zz-caelestia.conf"),
        "[Theme]\nCurrent=caelestia\n",
    )
    .expect("a selection an earlier run made");
    std::fs::write(conf.join("caelestia.conf"), "[Theme]\nCurrent=caelestia\n")
        .expect("an older one");
    let conf_dir = conf.to_string_lossy().to_string();

    // The selection the install recorded: there was none, so taking it back deletes the key
    // rather than restoring another theme's name.
    let state = fixture.path(".local/state/caelestia");
    std::fs::create_dir_all(&state).expect("the state directory");
    std::fs::write(state.join("sddm.conf.theme-current"), "#none\n").expect("the record");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BASE_DISTRO", "arch"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            ("CAELESTIA_SDDM_CONF_DIR", &conf_dir),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("SDDM has no sddm-greeter-qt9"),
        "{}",
        output.stdout
    );

    assert!(
        !conf.join("zz-caelestia.conf").exists(),
        "the selection this installer made is taken back"
    );
    assert!(
        !conf.join("caelestia.conf").exists(),
        "and so is the one from before the drop-in was renamed"
    );

    let calls = std::fs::read_to_string(&tools.calls).unwrap_or_default();
    assert!(
        calls.contains("kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current --delete"),
        "a machine that had no selection gets the key deleted, not set to a name: {calls}"
    );
    assert!(
        output
            .stdout
            .contains("Restored the login screen theme selection."),
        "{}",
        output.stdout
    );
    assert!(
        !state.join("sddm.conf.theme-current").exists(),
        "the record is spent once it has been put back"
    );
}

#[cfg(unix)]
#[test]
fn a_source_install_puts_the_theme_where_sddm_looks_for_it() {
    let fixture = Fixture::new("login-source");
    let tools = login_tools(&fixture);
    theme_fixture(&fixture, "full", "6");

    // The theme the checkout ships, which is what a source install copies from.
    let source = fixture.path("bundle/src/sddm/themes/full");
    std::fs::create_dir_all(&source).expect("the source theme");
    std::fs::write(source.join("Main.qml"), "// source theme\n").expect("the entrypoint");
    std::fs::write(source.join("theme.conf"), "[General]\n").expect("the theme config");
    std::fs::write(
        source.join("metadata.desktop"),
        "[SddmGreeterTheme]\nQtVersion=6\n",
    )
    .expect("the metadata");
    std::fs::write(source.join(".hidden"), "not part of the theme").expect("a dotfile");
    std::fs::write(source.join("theme.conf.template"), "[General]\n").expect("the template");

    let font = fixture.path("bundle/src/kde/shells/caelestia.desktop/contents/fonts");
    std::fs::create_dir_all(&font).expect("the font directory");
    std::fs::write(font.join("GoogleSansFlex.ttf"), b"font").expect("the font");
    stub_in(
        &fixture.path("bundle/src/sddm"),
        "sync.sh",
        "#!/bin/sh\nexit 0\n",
    );

    let installed = fixture.path("installed");
    let installed_dir = installed.to_string_lossy().to_string();
    let conf = fixture.path("conf.d");
    let conf_dir = conf.to_string_lossy().to_string();
    std::fs::create_dir_all(&installed).expect("the installed theme directory");

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BASE_DISTRO", "arch"),
            ("CAELESTIA_SDDM_THEME_DIR", &installed_dir),
            ("CAELESTIA_SDDM_CONF_DIR", &conf_dir),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert_eq!(
        std::fs::read_to_string(installed.join("Main.qml")).expect("the installed entrypoint"),
        "// source theme\n",
        "the checkout's theme is what lands in the installed tree"
    );
    assert!(
        !installed.join(".hidden").exists(),
        "a dotfile is not part of the theme"
    );
    assert!(
        installed
            .join("assets/google-sans-flex/GoogleSansFlex.ttf")
            .is_file(),
        "the lock screen's font is installed beside it"
    );
    assert!(
        installed.join("scripts/sync.sh").is_file(),
        "and so is the sync helper"
    );
    assert_eq!(
        std::fs::read_to_string(conf.join("zz-caelestia.conf"))
            .unwrap_or_else(|error| panic!("the drop-in: {error}\n{}", output.stdout)),
        "[General]\nGreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1\n\n[Theme]\nCurrent=caelestia\n",
        "the drop-in is what selects the theme"
    );
    assert!(
        fixture
            .path(".config/caelestia/templates/sddm-theme.conf")
            .is_file(),
        "and the template is offered to the user"
    );
    assert!(
        output.stdout.contains("Dependencies met."),
        "an arch install checks the greeter's packages: {}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_source_install_says_which_distribution_it_cannot_help() {
    let fixture = Fixture::new("login-unsupported");
    let tools = login_tools(&fixture);
    let source = fixture.path("bundle/src/sddm/themes/full");
    std::fs::create_dir_all(&source).expect("the source theme");
    for (name, body) in [
        ("theme.conf", "[General]\n"),
        ("Main.qml", "// theme\n"),
        ("metadata.desktop", "[SddmGreeterTheme]\nQtVersion=6\n"),
    ] {
        std::fs::write(source.join(name), body).expect("a theme file");
    }
    stub_in(
        &fixture.path("bundle/src/sddm"),
        "sync.sh",
        "#!/bin/sh\nexit 0\n",
    );

    let output = run_login(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BASE_DISTRO", "gentoo"),
            (
                "CAELESTIA_SDDM_THEME_DIR",
                &fixture.path("installed").to_string_lossy(),
            ),
            (
                "CAELESTIA_SDDM_CONF_DIR",
                &fixture.path("conf.d").to_string_lossy(),
            ),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("SDDM Qt6 dependencies must be installed manually."),
        "{}",
        output.stdout
    );
    assert!(
        output
            .stdout
            .contains("Login screen installed with warnings."),
        "and the run is reported as incompletely applied: {}",
        output.stdout
    );
}

#[cfg(unix)]
struct ConfigTools {
    path: PathBuf,
    calls: PathBuf,
}

#[cfg(unix)]
fn git_is_available() -> bool {
    std::process::Command::new("git")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

#[cfg(unix)]
fn run_git(directory: &Path, arguments: &[&str]) -> bool {
    std::process::Command::new("git")
        .args(["-c", "protocol.file.allow=always"])
        .args(["-c", "user.email=test@example.com"])
        .args(["-c", "user.name=Test"])
        .args(["-c", "init.defaultBranch=main"])
        .args(arguments)
        .current_dir(directory)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

// The step runs git with the fixture's HOME, so the file protocol a fixture remote needs is
// configured where git will look for it.
#[cfg(unix)]
fn allow_file_protocol(fixture: &Fixture) {
    std::fs::write(
        fixture.path(".gitconfig"),
        "[protocol \"file\"]\n\tallow = always\n[user]\n\temail = test@example.com\n\tname = Test\n[init]\n\tdefaultBranch = main\n",
    )
    .expect("the fixture git config");
}

#[cfg(unix)]
fn submodule_source(fixture: &Fixture, name: &str) -> PathBuf {
    let source = fixture.path(name);
    std::fs::create_dir_all(&source).expect("the source directory");
    run_git(&source, &["init", "--quiet"]);
    std::fs::write(source.join("deployed.conf"), b"deployed\n").expect("the source content");
    run_git(&source, &["add", "-A"]);
    run_git(&source, &["commit", "--quiet", "-m", "content"]);
    source
}

#[cfg(unix)]
fn checkout_with_submodule(fixture: &Fixture, source: &Path) -> PathBuf {
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");
    run_git(&bundle, &["init", "--quiet"]);
    std::fs::write(
        bundle.join(".gitmodules"),
        format!(
            "[submodule \"caelestia\"]\n\tpath = src/dots\n\turl = file://{}\n",
            source.display()
        ),
    )
    .expect("the gitmodules file");
    run_git(&bundle, &["add", ".gitmodules"]);
    run_git(&bundle, &["commit", "--quiet", "-m", "add submodule"]);
    run_git(&bundle, &["submodule", "init", "src/dots"]);
    std::fs::create_dir_all(bundle.join("src/dots")).expect("the empty checkout");

    bundle
}

#[cfg(unix)]
fn run_submodules(fixture: &Fixture, bundle: &Path, extra: &[(&str, &str)]) -> Output {
    let path = std::env::var("PATH").unwrap_or_default();
    fixture.step_in("02a-submodules", Path::new(&path), bundle, extra)
}

#[cfg(unix)]
#[test]
fn a_dots_tree_that_is_already_there_is_left_alone() {
    if !git_is_available() {
        return;
    }
    let fixture = Fixture::new("submodules-present");
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(bundle.join("src/dots")).expect("the dots tree");
    std::fs::write(bundle.join("src/dots/local.conf"), b"mine\n").expect("the local content");

    let output = run_submodules(&fixture, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        std::fs::read_to_string(bundle.join("src/dots/local.conf")).expect("the content"),
        "mine\n",
        "content that is already there is not replaced"
    );
    assert!(
        output.stdout.contains("src/dots ready."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn an_empty_dots_submodule_is_fetched_from_the_url_gitmodules_records() {
    if !git_is_available() {
        return;
    }
    let fixture = Fixture::new("submodules-fetch");
    allow_file_protocol(&fixture);
    let source = submodule_source(&fixture, "source");
    let bundle = checkout_with_submodule(&fixture, &source);

    let output = run_submodules(&fixture, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert_eq!(
        std::fs::read_to_string(bundle.join("src/dots/deployed.conf")).expect("the content"),
        "deployed\n"
    );
}

#[cfg(unix)]
#[test]
fn a_dots_submodule_that_cannot_be_fetched_fails_and_invents_nothing() {
    if !git_is_available() {
        return;
    }
    let fixture = Fixture::new("submodules-unfetchable");
    allow_file_protocol(&fixture);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");
    run_git(&bundle, &["init", "--quiet"]);
    std::fs::write(
        bundle.join(".gitmodules"),
        format!(
            "[submodule \"caelestia\"]\n\tpath = src/dots\n\turl = file://{}/gone\n",
            fixture.path("nowhere").display()
        ),
    )
    .expect("the gitmodules file");
    std::fs::create_dir_all(bundle.join("src/dots")).expect("the empty checkout");

    let output = run_submodules(&fixture, &bundle, &[]);
    assert_eq!(output.code, Some(1));
    assert!(
        output.stderr.contains("cannot deploy without it"),
        "{}",
        output.stderr
    );
    assert!(
        output.stderr.contains("02a-submodules"),
        "and it says how to retry it: {}",
        output.stderr
    );
    assert_eq!(
        std::fs::read_dir(bundle.join("src/dots"))
            .expect("the directory")
            .count(),
        0,
        "nothing is invented in its place"
    );
}

#[cfg(unix)]
#[test]
fn a_submodule_the_checkout_no_longer_lists_is_pruned_and_a_live_one_survives() {
    if !git_is_available() {
        return;
    }
    let fixture = Fixture::new("submodules-prune");
    allow_file_protocol(&fixture);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(&bundle).expect("the bundle");
    run_git(&bundle, &["init", "--quiet"]);
    run_git(
        &bundle,
        &["commit", "--quiet", "--allow-empty", "-m", "init"],
    );

    std::fs::write(
        bundle.join(".gitmodules"),
        "[submodule \"keep\"]\n\tpath = keep\n\turl = https://example.invalid/keep.git\n",
    )
    .expect("the gitmodules file");
    for (name, path) in [("keep", "keep"), ("gone", "gone")] {
        run_git(
            &bundle,
            &[
                "config",
                &format!("submodule.{name}.url"),
                &format!("https://example.invalid/{name}.git"),
            ],
        );
        run_git(
            &bundle,
            &["config", &format!("submodule.{name}.path"), path],
        );
        std::fs::create_dir_all(bundle.join(path)).expect("the worktree");
        std::fs::write(bundle.join(path).join("stale.conf"), b"stale\n").expect("a file");
        std::fs::create_dir_all(bundle.join(".git/modules").join(name)).expect("the module cache");
        std::fs::write(
            bundle.join(".git/modules").join(name).join("stale.conf"),
            b"stale\n",
        )
        .expect("a file");
    }

    // The two submodules this step does want are already there, so the only thing it has
    // left to do is the pruning.
    for tree in ["src/dots", "src/yet-another-monochrome-icon-set"] {
        std::fs::create_dir_all(bundle.join(tree)).expect("the submodule tree");
        std::fs::write(bundle.join(tree).join("content"), b"x\n").expect("a file");
    }

    let output = run_submodules(&fixture, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert!(!bundle.join("gone").exists(), "the dropped worktree goes");
    assert!(
        !bundle.join(".git/modules/gone").exists(),
        "and its module cache"
    );
    let registration = std::process::Command::new("git")
        .args(["config", "--get", "submodule.gone.url"])
        .current_dir(&bundle)
        .output()
        .expect("git runs");
    assert!(
        !registration.status.success(),
        "and the registration the checkout keeps"
    );

    assert!(bundle.join("keep").is_dir(), "a listed submodule survives");
    assert!(bundle.join(".git/modules/keep").is_dir());
}

#[cfg(unix)]
#[test]
fn missing_icon_set_is_a_warning_and_not_a_failure() {
    if !git_is_available() {
        return;
    }
    let fixture = Fixture::new("submodules-icons");
    allow_file_protocol(&fixture);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(bundle.join("src/dots")).expect("the dots tree");
    std::fs::write(bundle.join("src/dots/local.conf"), b"mine\n").expect("the local content");

    let output = run_submodules(&fixture, &bundle, &[]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("the monochrome icon theme will be missing"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
struct Services {
    path: PathBuf,
    calls: PathBuf,
}

#[cfg(unix)]
fn services_tools(fixture: &Fixture) -> Services {
    let bin = fixture.path("bin");
    let calls = fixture.path("calls.log");
    std::fs::write(&calls, "").expect("the call log");

    stub_in(
        &bin,
        "systemctl",
        "#!/bin/sh\n[ \"${KW_KEYD:-}\" = 1 ] && case \"$*\" in *keyd*) exit 0 ;; esac\nexit 1\n",
    );
    stub_in(
        &bin,
        "kwriteconfig6",
        "#!/bin/sh\nprintf 'kwriteconfig6 %s\\n' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );
    stub_in(
        &bin,
        "kreadconfig6",
        "#!/bin/sh\n[ -n \"${KW_DESKTOPS:-}\" ] && printf '%s\\n' \"$KW_DESKTOPS\"\nexit 0\n",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    Services {
        path: PathBuf::from(format!("{}:{system}", bin.display())),
        calls,
    }
}

#[cfg(unix)]
fn run_services(fixture: &Fixture, tools: &Services, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let rules = fixture.path("rules");
    std::fs::create_dir_all(&rules).expect("a rules directory");
    // A current rule keeps the system-level branch, which escalates, out of these tests;
    // the decision itself is covered by the unit tests beside it.
    std::fs::write(
        rules.join("70-uinput.rules"),
        "KERNEL==\"uinput\", MODE=\"0600\", OPTIONS+=\"static_node=uinput\", TAG+=\"uaccess\"\n",
    )
    .expect("a rule that is already current");
    let rules = rules.to_string_lossy().to_string();

    let mut environment: Vec<(&str, &str)> = vec![
        ("KW_CALLS", calls),
        ("CAELESTIA_UDEV_RULES_DIR", rules.as_str()),
    ];
    environment.extend_from_slice(extra);
    let bundle = fixture.path("bundle");
    fixture.step_in("06-services", &tools.path, &bundle, &environment)
}

// The step's own text is what the tests below drive, so a stub that reports one status and
// logs the arguments it was handed is enough to see what the step did with it. `install`
// says whether the second run the step makes is taken to have worked.
#[cfg(unix)]
fn quick_share_bundle(fixture: &Fixture, status: &str, port: &str, install: bool) -> PathBuf {
    let bundle = fixture.path("bundle");
    let scripts = bundle.join("shell").join("scripts");
    std::fs::create_dir_all(&scripts).expect("the shell scripts directory");
    let refused = if install { "0" } else { "1" };
    stub_in(
        &scripts,
        "quickshare_setup.sh",
        &format!(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$KW_SETUP_CALLS\"\nprintf 'AVAHI=active\\nSETUP={status}\\n'\ncase \"$*\" in\n    *--status*) exit 0 ;;\nesac\nexit {refused}\n"
        ),
    );
    std::fs::write(scripts.join("quickshare-port"), format!("{port}\n")).expect("the port");

    bundle
}

#[cfg(unix)]
fn quick_share_calls(fixture: &Fixture) -> String {
    std::fs::read_to_string(fixture.path("quickshare.calls")).unwrap_or_default()
}

// Escalation has to be reachable from a test that is not root and has no terminal, so the
// sudo to escalate through is named rather than discovered - the same override the shell
// resolver offers.
#[cfg(unix)]
fn sudo_stub(fixture: &Fixture) -> PathBuf {
    stub_in(
        &fixture.path("bin"),
        "sudo",
        "#!/bin/sh\ncase \"$*\" in\n    '-n -v'*) exit 0 ;;\nesac\nshift\nexec \"$@\"\n",
    )
}

#[cfg(unix)]
fn quick_share_environment(
    fixture: &Fixture,
    kind: &str,
    sudo: Option<&str>,
) -> Vec<(&'static str, String)> {
    let calls = fixture
        .path("quickshare.calls")
        .to_string_lossy()
        .to_string();
    let mut environment = vec![
        ("CAELESTIA_INSTALL_KIND", kind.to_string()),
        ("CAELESTIA_FRESH_INSTALL", "0".to_string()),
        ("KW_SETUP_CALLS", calls),
    ];
    if let Some(sudo) = sudo {
        environment.push(("CAELESTIA_SUDO_BIN", sudo.to_string()));
    }
    environment
}

#[cfg(unix)]
fn run_quick_share(fixture: &Fixture, tools: &Services, environment: &[(&str, String)]) -> Output {
    let borrowed: Vec<(&str, &str)> = environment
        .iter()
        .map(|(key, value)| (*key, value.as_str()))
        .collect();
    run_services(fixture, tools, &borrowed)
}

#[cfg(unix)]
#[test]
fn the_ydotoold_wrapper_and_unit_are_deployed() {
    let fixture = Fixture::new("services-ydotoold");
    let tools = services_tools(&fixture);

    let output = run_services(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let wrapper = fixture.path(".local/bin/ydotoold-wrapper");
    let body = std::fs::read_to_string(&wrapper).expect("the wrapper");
    assert!(
        body.contains("exec /usr/bin/ydotoold"),
        "the wrapper starts ydotoold: {body}"
    );
    assert!(
        body.contains("--socket-perm=0660"),
        "with the socket permissions the session needs: {body}"
    );

    let unit = std::fs::read_to_string(fixture.path(".config/systemd/user/ydotoold.service"))
        .expect("the unit");
    assert!(
        unit.contains("ExecStart=%h/.local/bin/ydotoold-wrapper"),
        "{unit}"
    );
    assert!(unit.contains("WantedBy=graphical-session.target"), "{unit}");

    assert!(
        output.stdout.contains("ydotoold service configured."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_packaged_install_leaves_the_system_level_alone() {
    let fixture = Fixture::new("services-packaged");
    let tools = services_tools(&fixture);

    let output = run_services(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "package"),
            ("CAELESTIA_FRESH_INSTALL", "0"),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("System-level configuration belongs to the package."),
        "{}",
        output.stdout
    );
    assert!(
        !std::fs::read_to_string(fixture.path("rules/70-uinput.rules"))
            .expect("the rule")
            .is_empty(),
        "and the rule the package owns is not rewritten"
    );
}

#[cfg(unix)]
#[test]
fn a_packaged_install_leaves_quick_share_to_the_shell() {
    let fixture = Fixture::new("services-quickshare-package");
    let tools = services_tools(&fixture);
    quick_share_bundle(&fixture, "needed", "1234", true);

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "package", None),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("packaged install"),
        "{}",
        output.stdout
    );
    assert_eq!(
        quick_share_calls(&fixture),
        "",
        "so nothing is run for Quick Share"
    );
}

#[cfg(unix)]
#[test]
fn a_quick_share_setup_that_is_missing_warns_without_raising_a_password_prompt() {
    let fixture = Fixture::new("services-quickshare-missing");
    let tools = services_tools(&fixture);

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", None),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("setup helper is missing"),
        "{}",
        output.stdout
    );
    assert_eq!(quick_share_calls(&fixture), "");
}

#[cfg(unix)]
#[test]
fn a_bundle_without_the_transfer_port_warns_without_raising_a_password_prompt() {
    let fixture = Fixture::new("services-quickshare-port");
    let tools = services_tools(&fixture);
    let bundle = quick_share_bundle(&fixture, "needed", "1234", true);
    std::fs::remove_file(bundle.join("shell/scripts/quickshare-port")).expect("the port is gone");

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", None),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("transfer port is missing"),
        "{}",
        output.stdout
    );
    assert_eq!(quick_share_calls(&fixture), "");
}

#[cfg(unix)]
#[test]
fn a_transfer_port_that_is_not_a_number_warns_without_raising_a_password_prompt() {
    let fixture = Fixture::new("services-quickshare-bad-port");
    let tools = services_tools(&fixture);
    quick_share_bundle(&fixture, "needed", "not-a-port", true);

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", None),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("is not a port number"),
        "{}",
        output.stdout
    );
    assert_eq!(quick_share_calls(&fixture), "");
}

#[cfg(unix)]
#[test]
fn a_quick_share_that_already_works_is_not_raised_for() {
    let fixture = Fixture::new("services-quickshare-ok");
    let tools = services_tools(&fixture);
    quick_share_bundle(&fixture, "ok", "1234", true);

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", None),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains("Quick Share already has the access it needs."),
        "{}",
        output.stdout
    );

    let calls = quick_share_calls(&fixture);
    assert_eq!(
        calls.lines().count(),
        1,
        "the status check decided, and nothing was run after it: {calls}"
    );
    assert!(
        calls.contains("--status --port 1234"),
        "and it was asked about the port the service binds: {calls}"
    );
}

#[cfg(unix)]
#[test]
fn a_quick_share_that_needs_setup_is_raised_for_with_the_port_the_service_binds() {
    let fixture = Fixture::new("services-quickshare-needed");
    let tools = services_tools(&fixture);
    quick_share_bundle(&fixture, "needed", "1234", true);
    let sudo = sudo_stub(&fixture).to_string_lossy().to_string();

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", Some(&sudo)),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let calls = quick_share_calls(&fixture);
    let runs: Vec<&str> = calls.lines().collect();
    assert_eq!(runs.len(), 2, "the status check and the setup run: {calls}");
    assert_eq!(
        runs[1], "--port 1234",
        "the run that is elevated carries the port the service listens on"
    );
    assert!(
        output.stdout.contains("Quick Share can receive"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_quick_share_setup_that_fails_warns_instead_of_failing_the_install() {
    let fixture = Fixture::new("services-quickshare-failed");
    let tools = services_tools(&fixture);
    quick_share_bundle(&fixture, "needed", "1234", false);
    let sudo = sudo_stub(&fixture).to_string_lossy().to_string();

    let output = run_quick_share(
        &fixture,
        &tools,
        &quick_share_environment(&fixture, "source", Some(&sudo)),
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        output.stdout.contains("did not finish"),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
fn dots_tools(fixture: &Fixture) -> ConfigTools {
    let bin = fixture.path("bin");
    let calls = fixture.path("calls.log");
    std::fs::write(&calls, "").expect("the call log");

    // `cksum` stands in for sha256sum: it is POSIX, and its digest is over the bytes, so
    // it changes exactly when the file does.
    stub_in(&bin, "sha256sum", "#!/bin/sh\nexec cksum \"$@\"\n");
    stub_in(&bin, "id", "#!/bin/sh\nprintf 'tester\\n'\n");
    stub_in(
        &bin,
        "getent",
        "#!/bin/sh\nprintf 'tester:x:1000:1000::/home/tester:/bin/zsh\\n'\n",
    );
    stub_in(&bin, "date", "#!/bin/sh\nprintf '20240101_120000\\n'\n");
    stub_in(
        &bin,
        "update-desktop-database",
        "#!/bin/sh\nprintf 'update-desktop-database %s\\n' \"$*\" >> \"$KW_CALLS\"\nexit 0\n",
    );

    let system = std::env::var("PATH").unwrap_or_default();
    ConfigTools {
        path: PathBuf::from(format!("{}:{system}", bin.display())),
        calls,
    }
}

#[cfg(unix)]
fn dots_bundle(fixture: &Fixture) -> PathBuf {
    let bundle = fixture.path("bundle");
    let dots = bundle.join("src/dots");
    for (directory, file, contents) in [
        ("btop", "btop.conf", "theme = \"caelestia\"\n"),
        ("foot", "foot.ini", "[main]\n"),
        ("kitty", "kitty.conf", "font_size 11\n"),
    ] {
        std::fs::create_dir_all(dots.join(directory)).expect("a config tree");
        std::fs::write(dots.join(directory).join(file), contents).expect("a config file");
    }
    std::fs::write(dots.join("starship.toml"), "format = \"$all\"\n").expect("the prompt");

    let fish = bundle.join("src/dots-extra/fish");
    std::fs::create_dir_all(&fish).expect("an extra config tree");
    std::fs::write(fish.join("config.fish"), "set -gx EDITOR nvim\n").expect("a config file");
    let fastfetch = bundle.join("src/dots-extra/fastfetch");
    std::fs::create_dir_all(&fastfetch).expect("an extra config tree");
    std::fs::write(fastfetch.join("config.jsonc"), "{}\n").expect("a config file");

    let bin = bundle.join("src/bin");
    std::fs::create_dir_all(&bin).expect("a bridge directory");
    std::fs::write(bin.join("caelestia-color"), "#!/bin/sh\n").expect("a bridge file");
    std::fs::write(bin.join("helper.cpp"), "// c++\n").expect("a source file");
    std::fs::write(bin.join("CMakeLists.txt"), "add_executable(x)\n").expect("a build file");

    bundle
}

#[cfg(unix)]
fn run_configs(fixture: &Fixture, tools: &ConfigTools, extra: &[(&str, &str)]) -> Output {
    let calls = tools.calls.to_str().expect("a path");
    let mut environment: Vec<(&str, &str)> = vec![("KW_CALLS", calls)];
    environment.extend_from_slice(extra);
    let bundle = fixture.path("bundle");
    fixture.step_in("03-deploy-configs", &tools.path, &bundle, &environment)
}

#[cfg(unix)]
#[test]
fn a_source_install_deploys_the_configs_the_prompt_and_the_bridge_files() {
    let fixture = Fixture::new("configs-source");
    let tools = dots_tools(&fixture);
    dots_bundle(&fixture);
    std::fs::write(fixture.path(".zshrc"), b"export EDITOR=nvim\n").expect("the shell rc");

    let backup = fixture.path("backup").to_string_lossy().to_string();
    let output = run_configs(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BACKUP_DIR", backup.as_str()),
        ],
    );
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/btop/btop.conf")).expect("the config"),
        "theme = \"caelestia\"\n"
    );
    assert!(fixture.path(".config/kitty/kitty.conf").is_file());
    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/starship.toml")).expect("the prompt"),
        "format = \"$all\"\n"
    );

    assert!(fixture.path(".local/bin/caelestia-color").is_file());
    assert!(
        !fixture.path(".local/bin/helper.cpp").exists(),
        "a compiled source file is not a bridge file"
    );
    assert!(
        !fixture.path(".local/bin/CMakeLists.txt").exists(),
        "and neither is a build file"
    );

    let shell = std::fs::read_to_string(fixture.path("backup/previous_shell.txt"));
    assert_eq!(shell.expect("the recorded shell"), "/bin/zsh\n");

    let states =
        std::fs::read_to_string(fixture.path("backup/shellrc/zshrc.state")).expect("the zsh state");
    assert_eq!(states, "present\n");
    assert_eq!(
        std::fs::read_to_string(fixture.path("backup/shellrc/fish_config.state"))
            .expect("the fish state"),
        "missing\n"
    );

    for name in ["btop", "kitty", "starship.toml"] {
        let stamp = fixture
            .path("cache/caelestia-kde/deployed")
            .join(format!("{name}.sha256"));
        assert!(stamp.is_file(), "{} is recorded", stamp.display());
    }

    assert!(
        output.stdout.contains("Config deployment complete."),
        "{}",
        output.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_config_the_user_edited_is_preserved_while_the_others_are_replaced() {
    let fixture = Fixture::new("configs-modified");
    let tools = dots_tools(&fixture);
    let bundle = dots_bundle(&fixture);
    let backup = fixture.path("backup").to_string_lossy().to_string();
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "source"),
        ("BACKUP_DIR", backup.as_str()),
    ];

    let first = run_configs(&fixture, &tools, &environment);
    assert_eq!(first.code, Some(0), "{}", first.stderr);

    std::fs::write(
        fixture.path(".config/btop/btop.conf"),
        "theme = \"material\"\n",
    )
    .expect("the user's own edit");
    std::fs::write(
        bundle.join("src/dots/foot/foot.ini"),
        "[main]\nfont=monospace\n",
    )
    .expect("the new shipped config");

    let second = run_configs(&fixture, &tools, &environment);
    assert_eq!(second.code, Some(0), "{}", second.stderr);

    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/btop/btop.conf")).expect("the config"),
        "theme = \"material\"\n",
        "an edited config is the user's"
    );
    assert!(
        second
            .stdout
            .contains("Preserving locally modified config: btop"),
        "{}",
        second.stdout
    );
    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/foot/foot.ini")).expect("the config"),
        "[main]\nfont=monospace\n",
        "an untouched config is updated"
    );
}

#[cfg(unix)]
#[test]
fn the_configs_the_user_had_are_backed_up_before_they_are_replaced() {
    let fixture = Fixture::new("configs-backup");
    let tools = dots_tools(&fixture);
    dots_bundle(&fixture);
    let backup = fixture.path("backup");
    let backup_dir = backup.to_string_lossy().to_string();
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "source"),
        ("BACKUP_DIR", backup_dir.as_str()),
    ];

    std::fs::create_dir_all(fixture.path(".config/btop")).expect("the user's config tree");
    std::fs::write(fixture.path(".config/btop/btop.conf"), b"theirs\n").expect("a config file");
    std::fs::write(fixture.path(".config/konsolerc"), b"[Desktop Entry]\n").expect("the konsolerc");
    std::fs::create_dir_all(fixture.path(".local/share/konsole")).expect("the konsole tree");
    std::fs::write(
        fixture.path(".local/share/konsole/Caelestia.profile"),
        b"[General]\n",
    )
    .expect("a profile");

    let output = run_configs(&fixture, &tools, &environment);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    assert_eq!(
        std::fs::read_to_string(backup.join(".config/btop/btop.conf")).expect("the backup"),
        "theirs\n"
    );
    assert!(backup.join(".config/konsolerc").is_file());
    assert!(backup.join("local/konsole/Caelestia.profile").is_file());
    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/btop/btop.conf")).expect("the config"),
        "theme = \"caelestia\"\n"
    );
}

#[cfg(unix)]
#[test]
fn thunar_and_fish_follow_the_answers_they_were_given() {
    let fixture = Fixture::new("configs-choices");
    let tools = dots_tools(&fixture);
    let bundle = dots_bundle(&fixture);
    let thunar = bundle.join("src/dots/thunar");
    std::fs::create_dir_all(&thunar).expect("the thunar tree");
    std::fs::write(thunar.join("uca.xml"), "<actions/>\n").expect("an action file");
    let backup = fixture.path("backup");
    let backup_dir = backup.to_string_lossy().to_string();

    let off = run_configs(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BACKUP_DIR", backup_dir.as_str()),
            ("INSTALL_THUNAR", "false"),
            ("INSTALL_FISH", "false"),
        ],
    );
    assert_eq!(off.code, Some(0), "{}", off.stderr);
    assert!(!fixture.path(".config/thunar").exists());
    assert!(!fixture.path(".config/fish").exists());
    assert!(
        fixture.path(".config/fastfetch/config.jsonc").is_file(),
        "the other extra config is not the one that was declined"
    );

    let on = run_configs(
        &fixture,
        &tools,
        &[
            ("CAELESTIA_INSTALL_KIND", "source"),
            ("BACKUP_DIR", backup_dir.as_str()),
            ("INSTALL_THUNAR", "true"),
            ("INSTALL_FISH", "true"),
        ],
    );
    assert_eq!(on.code, Some(0), "{}", on.stderr);
    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/thunar/uca.xml")).expect("the action file"),
        "<actions/>\n"
    );
    assert!(fixture.path(".config/fish/config.fish").is_file());
    assert!(
        on.stdout
            .contains("Missing optional Thunar file: thunar/thunar-volman.xml"),
        "{}",
        on.stdout
    );
}

#[cfg(unix)]
#[test]
fn a_missing_dots_tree_names_the_step_that_fills_it() {
    let fixture = Fixture::new("configs-empty-dots");
    let tools = dots_tools(&fixture);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(bundle.join("src/dots")).expect("an empty dots tree");
    let backup = fixture.path("backup");
    let backup_dir = backup.to_string_lossy().to_string();
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "source"),
        ("BACKUP_DIR", backup_dir.as_str()),
    ];

    let output = run_configs(&fixture, &tools, &environment);
    assert_eq!(output.code, Some(1));
    assert!(
        output.stderr.contains("02a-submodules"),
        "{}",
        output.stderr
    );
}

#[cfg(unix)]
#[test]
fn a_packaged_install_without_dotfiles_says_the_package_owes_them() {
    let fixture = Fixture::new("configs-packaged");
    let tools = dots_tools(&fixture);
    let bundle = fixture.path("bundle");
    std::fs::create_dir_all(bundle.join("src/dots")).expect("an empty dots tree");
    let backup = fixture.path("backup");
    let backup_dir = backup.to_string_lossy().to_string();
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "package"),
        ("BACKUP_DIR", backup_dir.as_str()),
    ];

    let output = run_configs(&fixture, &tools, &environment);
    assert_eq!(output.code, Some(1));
    assert!(output.stderr.contains("reinstall it"), "{}", output.stderr);
}

#[cfg(unix)]
#[test]
fn the_backup_directory_a_previous_step_recorded_is_the_one_that_is_used() {
    let fixture = Fixture::new("configs-recorded");
    let tools = dots_tools(&fixture);
    dots_bundle(&fixture);

    let recorded = fixture.path("bundle/backups/20231231_235959");
    std::fs::create_dir_all(&recorded).expect("the recorded backup");
    std::fs::create_dir_all(fixture.path("cache/caelestia-kde")).expect("the cache directory");
    std::fs::write(
        fixture.path("cache/caelestia-kde/backup-dir.txt"),
        format!("{}\n", recorded.display()),
    )
    .expect("the record");

    let output = run_configs(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);
    assert!(
        recorded.join("previous_shell.txt").is_file(),
        "the recorded backup is where this run puts its files"
    );
}

#[cfg(unix)]
#[test]
fn a_recorded_backup_directory_outside_the_two_roots_is_ignored() {
    let fixture = Fixture::new("configs-stale-record");
    let tools = dots_tools(&fixture);
    dots_bundle(&fixture);

    let elsewhere = fixture.path("elsewhere/20230101_000000");
    std::fs::create_dir_all(&elsewhere).expect("a directory that is not a backup");
    std::fs::create_dir_all(fixture.path("cache/caelestia-kde")).expect("the cache directory");
    std::fs::write(
        fixture.path("cache/caelestia-kde/backup-dir.txt"),
        format!("{}\n", elsewhere.display()),
    )
    .expect("the record");

    let output = run_configs(&fixture, &tools, &[("CAELESTIA_INSTALL_KIND", "source")]);
    assert_eq!(output.code, Some(0), "{}", output.stderr);

    let fresh = fixture.path("bundle/backups/20240101_120000");
    assert!(
        fresh.join("previous_shell.txt").is_file(),
        "a fresh backup is made beside the bundle instead"
    );
    assert!(
        std::fs::read_dir(&elsewhere)
            .expect("the directory")
            .next()
            .is_none(),
        "and the directory the record named is left alone"
    );
}

#[cfg(unix)]
#[test]
fn the_prompt_the_user_edited_is_left_alone_and_backed_up() {
    let fixture = Fixture::new("configs-starship");
    let tools = dots_tools(&fixture);
    let bundle = dots_bundle(&fixture);
    let backup = fixture.path("backup");
    let backup_dir = backup.to_string_lossy().to_string();
    let environment = [
        ("CAELESTIA_INSTALL_KIND", "source"),
        ("BACKUP_DIR", backup_dir.as_str()),
    ];

    let first = run_configs(&fixture, &tools, &environment);
    assert_eq!(first.code, Some(0), "{}", first.stderr);

    std::fs::write(
        fixture.path(".config/starship.toml"),
        "format = \"$directory\"\n",
    )
    .expect("the user's own prompt");
    std::fs::write(
        bundle.join("src/dots/starship.toml"),
        "format = \"$all$time\"\n",
    )
    .expect("the new shipped prompt");

    let second = run_configs(&fixture, &tools, &environment);
    assert_eq!(second.code, Some(0), "{}", second.stderr);
    assert_eq!(
        std::fs::read_to_string(fixture.path(".config/starship.toml")).expect("the prompt"),
        "format = \"$directory\"\n"
    );
    assert_eq!(
        std::fs::read_to_string(backup.join(".config/starship.toml")).expect("the backup"),
        "format = \"$directory\"\n"
    );
    assert!(
        second
            .stdout
            .contains("Preserving locally modified config: starship.toml"),
        "{}",
        second.stdout
    );
}
