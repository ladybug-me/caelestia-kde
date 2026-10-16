use std::fs;
use std::path::{Path, PathBuf};

use crate::copy;
use crate::download::{self, Verification};
use crate::install_fs;
use crate::install_kind;
use crate::output;
use crate::paths;
use crate::process;
use crate::steps::{self, Context, Failure};
use crate::tmp::TempDir;
use crate::toolchain;
use crate::update_state;

const PREBUILT_ASSETS: [&str; 2] = ["caelestia-kde", "caelestia-shell"];
const QML_MODULES: [&str; 11] = [
    "Caelestia",
    "Caelestia/Components",
    "Caelestia/Config",
    "Caelestia/Settings",
    "Caelestia/Models",
    "Caelestia/Services",
    "Caelestia/Services/QuickShare",
    "Caelestia/Blobs",
    "Caelestia/Images",
    "Caelestia/Layouts",
    "M3Shapes",
];
const LOCKSCREEN_PACKAGE: &str = "src/kde/shells/caelestia.desktop";
const LEGACY_FONTS: [&str; 3] = ["SF-Pro", "SF-Mono", "google-sans-flex"];
const LEGACY_FONT_README: &str = "# Fonts";
// What an install still on an older release is missing after its updater's sparse rules
// have been applied, and has to be fetched before this step reads it.
const SPARSIFY: [&str; 3] = ["installer/", "assets/", "uninstall.sh"];
const EFFECT_DIR: &str = "kwin-effects/workspace-tracker";

pub fn run(context: &Context) -> Result<(), Failure> {
    let home = paths::home();
    let bundle = &context.bundle;
    let shell_dir = bundle.join("shell");

    if install_kind::is_packaged() {
        write_shell_environment(&home)?;
        output::skip("Nothing to build: the shell tree is the package's.");
        return Ok(());
    }

    let generator = if process::available("ninja") {
        "Ninja"
    } else {
        output::warn("ninja not found; falling back to Unix Makefiles (builds will be slower).");
        "Unix Makefiles"
    };
    let jobs = build_jobs();
    let load = process::capture("nproc", &[])
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "2".to_string());

    prepare_ccache();

    if context.variable("CAELESTIA_SETUP_RUNNING").as_deref() != Some("1") {
        standalone_update(context, &shell_dir)?;
    }

    output::info("Building the Caelestia shell...");
    if !shell_dir.is_dir() {
        return Err(format!("Shell directory not found at {}!", shell_dir.display()).into());
    }
    check_qml_deployment(bundle, &shell_dir)?;

    let theme = Toolchain {
        bundle: bundle.clone(),
        generator: generator.to_string(),
    };

    backup_shell_config(&home)?;

    let prebuilt = context.variable("CAELESTIA_FORCE_BUILD_SHELL").is_none()
        && checkout_may_use_prebuilt(bundle)
        && process::available("curl")
        && try_prebuilt_shell(bundle, &home);

    if prebuilt {
        output::ok("Using prebuilt shell artifacts from the release.");
    } else {
        build_and_install(&shell_dir, &theme, &jobs, &load)?;
    }

    build_workspace_tracker(&shell_dir, &theme, &jobs, &load);

    check_qml_modules(&home)?;

    write_shell_environment(&home)?;
    install_support_files(bundle, &home)?;
    install_icon_set(bundle, &home);

    update_state::record_installed_revision(bundle, &home.join(".config/quickshell/caelestia"));

    cleanup_legacy_fonts(&home);

    match context.variable("CAELESTIA_SKIP_DEPLOY").as_deref() {
        Some("0") | None => {
            if context.variable("APPLY_LOCKSCREEN").as_deref() != Some("false") {
                cleanup_legacy_lockscreen(&home);
                if install_lockscreen_greeter(bundle, &home) {
                    configure_lockscreen_greeter(&home);
                }
            } else {
                output::skip("Lock screen greeter disabled by user choice.");
            }
        }
        _ => {
            if context.variable("APPLY_LOCKSCREEN").as_deref() == Some("false") {
                output::skip("Lock screen greeter disabled by user choice.");
            } else {
                output::info("KDE Lock Screen installation and configuration skipped.");
            }
        }
    }

    output::ok(
        "Caelestia Shell and KDE Bridges built and installed successfully to user directory.",
    );
    Ok(())
}

fn build_jobs() -> String {
    if let Some(jobs) = std::env::var("CAELESTIA_BUILD_JOBS")
        .ok()
        .filter(|jobs| !jobs.is_empty())
    {
        return jobs;
    }

    let available: i64 = process::capture("nproc", &[])
        .and_then(|count| count.parse().ok())
        .unwrap_or(2);
    (available - 1).max(1).to_string()
}

// The cache the compiler reads and writes; keeping it under the user's own cache directory
// is what makes a rebuild after an update cheap.
fn prepare_ccache() {
    let directory = std::env::var("CCACHE_DIR")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            paths::cache_dir()
                .join("caelestia-kde")
                .join("ccache")
                .to_string_lossy()
                .to_string()
        });
    let _ = fs::create_dir_all(&directory);
    if process::available("ccache") {
        let _ = process::succeeds("ccache", &["--max-size", "8G"], None);
    }
}

// ---------------------------------------------------------------------------
// The environment the session reads

const ENVIRONMENT_HEADER: &str = "\
# Written by Caelestia. Read by systemd for every session process and by the
# user manager the shell's unit runs under.";

// The command directory goes on PATH because a checkout's command lives in ~/.local/bin,
// which a session does not carry on every distribution: without this, a terminal here cannot
// run `caelestia update` by name. A package's /usr/bin is already on PATH.
const PLASMA_ENVIRONMENT_HEADER: &str = "\
#!/bin/sh
# Written by Caelestia. Sourced by KDE Plasma during session startup for KWin,
# kscreenlocker_greet, and graphical session processes.
#
# The command directory goes on PATH because a checkout's command lives in
# ~/.local/bin, which a session does not carry on every distribution: without
# this, a terminal here cannot run caelestia update by name. A package's
# /usr/bin is already on PATH, so this only matters for a checkout.";

pub fn write_shell_environment(home: &Path) -> Result<(), Failure> {
    let bin_dir = install_kind::bin_dir().to_string_lossy().to_string();
    let lib_dir = install_kind::lib_dir().to_string_lossy().to_string();
    let imports = install_kind::qml_import_path();
    let shell_config = install_kind::shell_config().to_string_lossy().to_string();

    let environment_d = home.join(".config").join("environment.d");
    output::info(&format!(
        "Writing the shell environment to {}",
        environment_d.join("caelestia.conf").display()
    ));
    fs::create_dir_all(&environment_d)
        .map_err(|error| format!("cannot use {}: {error}", environment_d.display()))?;
    fs::write(
        environment_d.join("caelestia.conf"),
        format!(
            "{ENVIRONMENT_HEADER}\n\
             QML2_IMPORT_PATH={imports}\n\
             CAELESTIA_LIB_DIR={lib_dir}\n\
             CAELESTIA_BIN_DIR={bin_dir}\n\
             CAELESTIA_SHELL_CONFIG={shell_config}\n"
        ),
    )
    .map_err(|error| format!("cannot write the shell environment: {error}"))?;
    output::ok("Shell environment written.");

    let plasma_env_d = home.join(".config").join("plasma-workspace").join("env");
    output::info(&format!(
        "Writing the Plasma session environment to {}",
        plasma_env_d.join("caelestia.sh").display()
    ));
    fs::create_dir_all(&plasma_env_d)
        .map_err(|error| format!("cannot use {}: {error}", plasma_env_d.display()))?;
    let script = plasma_env_d.join("caelestia.sh");
    fs::write(
        &script,
        format!(
            "{PLASMA_ENVIRONMENT_HEADER}\n\
             export PATH=\"{bin_dir}${{PATH:+:$PATH}}\"\n\
             export QML2_IMPORT_PATH=\"{imports}${{QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}}\"\n\
             export CAELESTIA_LIB_DIR=\"{lib_dir}\"\n\
             export CAELESTIA_BIN_DIR=\"{bin_dir}\"\n\
             export CAELESTIA_SHELL_CONFIG=\"{shell_config}\"\n"
        ),
    )
    .map_err(|error| format!("cannot write the Plasma environment: {error}"))?;
    paths::make_executable(&script);
    output::ok("Plasma session environment written.");

    for rc in [
        home.join(".bashrc"),
        home.join(".config").join("fish").join("config.fish"),
        home.join(".zshrc"),
    ] {
        remove_environment_lines(&rc);
    }
    Ok(())
}

// The lines an older install added to a shell's rc file are removed: the session gets them
// from environment.d and Plasma now, and an rc file that also carries them would put the
// checkout's directories in front of a package's.
fn remove_environment_lines(rc: &Path) {
    if !rc.is_file() {
        return;
    }
    let Ok(text) = fs::read_to_string(rc) else {
        return;
    };
    if !text.lines().any(is_environment_line) {
        return;
    }

    let kept: Vec<&str> = text
        .lines()
        .filter(|line| !is_environment_line(line))
        .collect();
    if fs::write(rc, format!("{}\n", kept.join("\n"))).is_ok() {
        output::info(&format!(
            "Removed the Caelestia environment lines from {}",
            rc.file_name().unwrap_or_default().to_string_lossy()
        ));
    }
}

fn is_environment_line(line: &str) -> bool {
    line.contains("CAELESTIA_LIB_DIR")
        || (line.contains("QML2_IMPORT_PATH") && line.contains("caelestia"))
}

// ---------------------------------------------------------------------------
// The update path this step repairs

fn sparsify_checkout_paths(bundle: &Path) {
    for rule in SPARSIFY {
        let path = rule.trim_end_matches('/');
        if bundle.join(path).exists() {
            continue;
        }

        let Some(sparse_file) = sparse_checkout_file(bundle) else {
            continue;
        };
        let rules = fs::read_to_string(&sparse_file).unwrap_or_default();
        if !rules.lines().any(|line| line == rule) {
            let _ = fs::write(&sparse_file, format!("{rules}{rule}\n"));
        }
        let _ = process::succeeds("git", &["read-tree", "-mu", "HEAD"], Some(bundle));
        if !bundle.join(path).exists() {
            let _ = process::succeeds("git", &["checkout", "HEAD", "--", path], Some(bundle));
        }
    }
}

fn sparse_checkout_file(bundle: &Path) -> Option<PathBuf> {
    let path = process::capture_in(
        "git",
        &["rev-parse", "--git-path", "info/sparse-checkout"],
        Some(bundle),
    )?;
    if path.is_empty() {
        return None;
    }
    let path = PathBuf::from(path);
    let path = if path.is_absolute() {
        path
    } else {
        bundle.join(path)
    };
    path.is_file().then_some(path)
}

fn standalone_update(context: &Context, shell_dir: &Path) -> Result<(), Failure> {
    output::info("Running standalone update mode... ensuring prerequisites.");

    run_step(context, "02a-submodules")?;

    sparsify_checkout_paths(&context.bundle);

    if context.bundle.join("installer").is_dir() {
        output::info("Checking core, shell, theme, and utility dependencies...");
        if run_step(context, "02-all-packages").is_err() {
            output::warn("02-all-packages reported warnings");
        }
    } else {
        output::warn("Skipping the dependency check: installer/ is missing.");
    }
    output::info("Deleting yet-another-monochrome-icon-set for lag free update...");
    let icons = shell_dir.join("assets/icons/yet-another-monochrome-icon-set");
    if icons.is_dir() && fs::remove_dir_all(&icons).is_err() {
        output::warn("Failed to delete yet-another-monochrome-icon-set.");
    }

    output::info("Installing Caelestia Services...");
    if run_step(context, "06-services").is_err() {
        output::warn("06-services failed");
    }

    output::info("Updating autostart environment variables");
    if run_step(context, "10-autostart").is_err() {
        output::warn("10-autostart failed");
    }

    // The default wallpaper pack is a step of its own in a full install, but an update only
    // runs 03-deploy-configs, this step and 09-system-tweaks, so it is fetched from here to
    // keep updates supplied with it. The step is idempotent.
    output::info("Downloading the default wallpaper pack...");
    if run_step(context, "03a-wallpapers").is_err() {
        output::warn("03a-wallpapers failed");
    }

    Ok(())
}

fn run_step(context: &Context, id: &str) -> Result<(), Failure> {
    let Some(step) = steps::find(id) else {
        return Err(format!("no step is called '{id}'").into());
    };
    if steps::run(step, context) == 0 {
        Ok(())
    } else {
        Err(format!("the {id} step failed").into())
    }
}

fn check_qml_deployment(bundle: &Path, shell_dir: &Path) -> Result<(), Failure> {
    let checker = bundle.join(".github/scripts/check_qml_deployment.py");
    if !process::available("python3") || !checker.is_file() {
        return Ok(());
    }

    let arguments = [
        checker.to_string_lossy().to_string(),
        "--source-root".to_string(),
        shell_dir.to_string_lossy().to_string(),
    ];
    let args: Vec<&str> = arguments.iter().map(String::as_str).collect();
    if !process::succeeds("python3", &args, None) {
        return Err("QML source compatibility validation failed.".into());
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Preparing a build directory

struct Toolchain {
    bundle: PathBuf,
    generator: String,
}

impl Toolchain {
    fn stamp(&self) -> String {
        let cmake = process::capture("cmake", &["--version"])
            .and_then(|text| {
                text.lines()
                    .next()
                    .map(|line| line.replace("cmake version ", ""))
                    .map(|line| line.trim().to_string())
            })
            .unwrap_or_default();
        let qt = process::capture("pkg-config", &["--modversion", "Qt6Core"])
            .map(|version| normalize_version(&version))
            .unwrap_or_default();

        format!(
            "bundle:{} cmake:{} qt6core:{} gen:{} cava:{}\n",
            self.bundle.display(),
            normalize_version(&cmake),
            qt,
            self.generator,
            toolchain::cava_state()
        )
    }
}

// `1.2.3` and `1.2.4` are the same toolchain as far as a rebuild is concerned: the stamp is
// about whether the generator and the headers changed.
fn normalize_version(text: &str) -> String {
    let mut parts = text.trim().split('.');
    match (parts.next(), parts.next()) {
        (Some(major), Some(minor)) => format!("{major}.{minor}"),
        _ => text.trim().to_string(),
    }
}

fn prepare_build_dir(directory: &Path, theme: &Toolchain) -> Result<(), Failure> {
    let stamp = directory.join(".caelestia_toolchain_stamp");
    if directory.join("CMakeCache.txt").is_file()
        && stamp.is_file()
        && fs::read_to_string(&stamp).unwrap_or_default() == theme.stamp()
    {
        return Ok(());
    }

    let _ = fs::remove_dir_all(directory);
    fs::create_dir_all(directory)
        .map_err(|error| format!("cannot use {}: {error}", directory.display()))?;
    fs::write(&stamp, theme.stamp())
        .map_err(|error| format!("cannot write {}: {error}", stamp.display()))?;
    Ok(())
}

// `nice -n 10`: the build stays usable while it runs.
fn build_command(program: &str, args: &[&str], directory: &Path) -> std::process::Command {
    let mut command = if process::available("nice") {
        let mut command = std::process::Command::new("nice");
        command.args(["-n", "10", program]);
        command
    } else {
        std::process::Command::new(program)
    };
    command.args(args).current_dir(directory);
    command
}

fn show_build_errors(log: &Path) {
    let text = fs::read_to_string(log).unwrap_or_default();
    for line in text.lines().filter(|line| is_build_error(line)) {
        eprintln!("{line}");
    }
    eprintln!("----- last 20 lines of {} -----", log.display());
    let lines: Vec<&str> = text.lines().collect();
    for line in lines.iter().skip(lines.len().saturating_sub(20)) {
        eprintln!("{line}");
    }
}

fn is_build_error(line: &str) -> bool {
    line.contains("error:")
        || line.contains("FAILED:")
        || line.contains("ninja: build stopped")
        || line.contains("CMake Error")
        || line.contains("undefined reference")
        || line.starts_with("ld: ")
        || line.contains("make: ***")
}

fn build_and_install(
    shell_dir: &Path,
    theme: &Toolchain,
    jobs: &str,
    load: &str,
) -> Result<(), Failure> {
    if !toolchain::linguist_tools_available() {
        output::info("Installing Qt Linguist tools for UI translations...");
        if !toolchain::install_linguist_tools() {
            output::warn("Linguist tools install failed; the shell will stay in English.");
        }
    }

    let cache = paths::cache_dir().join("caelestia-kde");
    fs::create_dir_all(&cache).ok();
    let log = cache.join("shell-build.log");

    output::info("Configuring CMake...");
    let build = shell_dir.join("build");
    prepare_build_dir(&build, theme)?;

    let home = paths::home().to_string_lossy().to_string();
    let offline = std::env::var("CAELESTIA_OFFLINE").unwrap_or_else(|_| "OFF".to_string());
    let qsconf = format!("{home}/.config/quickshell/caelestia");
    let configured = run_logged(
        build_command(
            "cmake",
            &[
                "-G",
                &theme.generator,
                "-B",
                "build",
                "-DCMAKE_BUILD_TYPE=Release",
                "-DCAELESTIA_CACHE_DEPS=ON",
                &format!("-DCAELESTIA_OFFLINE={offline}"),
                &format!("-DCMAKE_INSTALL_PREFIX={home}/.local"),
                "-DINSTALL_BINDIR=bin",
                "-DINSTALL_DATADIR=lib/caelestia",
                &format!("-DINSTALL_QSCONFDIR={qsconf}"),
                "-DINSTALL_LIBDIR=lib/caelestia",
                "-DINSTALL_QMLDIR=lib/qt6/qml",
            ],
            shell_dir,
        ),
        &log,
        Logging::Terminal,
    );
    if !configured? {
        return Err("CMake configuration failed.".into());
    }

    output::info(&format!("Building with {jobs} parallel jobs..."));
    if !run_logged(
        build_command(
            "cmake",
            &["--build", "build", &format!("-j{jobs}"), "--", "-l", load],
            shell_dir,
        ),
        &log,
        Logging::ErrorsOnly,
    )? {
        output::err(&format!("Build failed. Full log: {}", log.display()));
        show_build_errors(&log);
        return Err("The shell build failed.".into());
    }

    output::info("Installing to user local dir...");
    if !run_logged(
        build_command("cmake", &["--install", "build"], shell_dir),
        &log,
        Logging::Append,
    )? {
        return Err(format!("Installation failed. Full log: {}", log.display()).into());
    }
    Ok(())
}

// How the shell routed a build command's output: everything to the log, and to the terminal
// either everything, everything but the compiler's own noise, or nothing at all.
#[derive(Copy, Clone, PartialEq, Eq)]
enum Logging {
    Terminal,
    ErrorsOnly,
    Append,
    Silent,
}

fn run_logged(
    mut command: std::process::Command,
    log: &Path,
    logging: Logging,
) -> Result<bool, Failure> {
    use std::io::Write;

    let append = matches!(logging, Logging::Append);
    let file = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .append(append)
        .truncate(!append)
        .open(log);
    let mut file = file.map_err(|error| format!("cannot write {}: {error}", log.display()))?;

    let output = command
        .stdin(std::process::Stdio::null())
        .output()
        .map_err(|error| format!("could not run the build command: {error}"))?;
    file.write_all(&output.stdout)
        .and_then(|_| file.write_all(&output.stderr))
        .map_err(|error| format!("cannot write {}: {error}", log.display()))?;

    if logging != Logging::Silent {
        let combined = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        for line in combined.lines() {
            if logging == Logging::ErrorsOnly
                && (line.contains("warning:") || line.contains("note:"))
            {
                continue;
            }
            println!("{line}");
        }
    }
    Ok(output.status.success())
}

// ---------------------------------------------------------------------------
// The prebuilt archive

fn release_tag(bundle: &Path) -> Option<String> {
    let text = fs::read_to_string(bundle.join(".github/version.env")).ok()?;
    text.lines()
        .find_map(|line| line.trim().strip_prefix("VERSION="))
        .map(|tag| tag.trim().to_string())
        .filter(|tag| !tag.is_empty())
}

// The prebuilt archive holds one released revision, so it may only stand in for a tree that
// is that revision: the released tag itself (an update pinned to a version) or main sitting
// on its remote tip. A branch, a stale main, or a checkout carrying commits of its own builds
// locally instead of letting the archive replace them. Main that has moved on since its last
// release cannot be told apart from that release here, so such a tree is replaced by the
// release the archive was built from.
fn checkout_may_use_prebuilt(bundle: &Path) -> bool {
    let Some(release) = release_tag(bundle) else {
        return false;
    };
    let Some(head) = process::capture_in("git", &["rev-parse", "HEAD"], Some(bundle)) else {
        return false;
    };

    if process::capture_in(
        "git",
        &["describe", "--tags", "--exact-match", &head],
        Some(bundle),
    )
    .as_deref()
        == Some(release.as_str())
    {
        return true;
    }

    if process::capture_in("git", &["branch", "--show-current"], Some(bundle)).as_deref()
        != Some("main")
    {
        return false;
    }
    process::capture_in(
        "git",
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            "refs/remotes/origin/main",
        ],
        Some(bundle),
    )
    .as_deref()
        == Some(head.as_str())
}

fn shell_qt_abi() -> Option<String> {
    process::capture("pkg-config", &["--modversion", "Qt6Core"])
        .map(|version| normalize_version(&version))
        .filter(|version| !version.is_empty())
}

fn try_prebuilt_shell(bundle: &Path, home: &Path) -> bool {
    if process::capture("uname", &["-m"]).as_deref() != Some("x86_64") {
        return false;
    }
    if !Path::new("/etc/arch-release").exists() {
        return false;
    }
    let (Some(abi), Some(tag)) = (shell_qt_abi(), release_tag(bundle)) else {
        return false;
    };

    let Some(work) = TempDir::new("caelestia-prebuilt") else {
        return false;
    };
    let archive = work.path().join("shell.tar.gz");

    output::info(&format!(
        "Downloading prebuilt shell artifacts ({tag}, Qt {abi})..."
    ));
    let mut published = None;
    for asset in PREBUILT_ASSETS {
        let url = format!(
            "https://github.com/ladybug-me/caelestia-kde/releases/download/{tag}/{asset}-x86_64-qt{abi}.tar.gz"
        );
        if download::fetch(&url, &archive, &["--progress-bar"]) {
            published = Some(url);
            break;
        }
        let _ = fs::remove_file(&archive);
    }
    let Some(url) = published else {
        output::warn(&format!(
            "No prebuilt shell artifacts published for {tag} (Qt {abi}) - falling back to a local build."
        ));
        return false;
    };

    match download::verify(&url, &archive) {
        Verification::Mismatch => {
            output::warn(&format!(
                "Checksum mismatch for {url} - falling back to a local build."
            ));
            return false;
        }
        Verification::Unpublished => {
            let digest = download::sha256(&archive).unwrap_or_default();
            output::warn(&format!(
                "No published checksum for {url} - extracting without verification (SHA-256 {digest})."
            ));
        }
        Verification::Match => output::ok("Prebuilt shell artifacts match the published checksum."),
    }

    // Nothing above compared the archive against a published hash for the first two cases,
    // and this extraction writes into $HOME/.config and $HOME/.local, so refuse an archive
    // carrying setuid or escaping entries even when there is no hash to check.
    if !download::archive_entries_are_safe(&archive) {
        output::warn(&format!(
            "Refusing to extract {url}: the archive has setuid, setgid or escaping entries."
        ));
        return false;
    }

    output::info("Extracting prebuilt shell artifacts...");
    let local = home.join(".local");
    let config = home.join(".config");
    let _ = fs::create_dir_all(&local);
    let _ = fs::create_dir_all(&config);
    let archive = archive.to_string_lossy().to_string();

    for (directory, member) in [(&local, "lib"), (&config, "quickshell")] {
        if !extract(&archive, directory, member) {
            output::warn(&format!(
                "Failed to extract {member} from prebuilt shell archive"
            ));
            return false;
        }
    }

    if !archive_has(&archive, "bin/") || !archive_has(&archive, "lib/caelestia/") {
        output::warn(
            "Prebuilt shell artifact has no CMake-owned CLI/data tree - falling back to a local build.",
        );
        return false;
    }
    if !extract(&archive, &local, "bin") {
        output::warn("Failed to extract CMake-owned CLI files");
        return false;
    }
    true
}

fn extract(archive: &str, directory: &Path, member: &str) -> bool {
    process::succeeds(
        "tar",
        &["-C", &directory.to_string_lossy(), "-xzf", archive, member],
        None,
    )
}

fn archive_has(archive: &str, member: &str) -> bool {
    process::succeeds("tar", &["-tzf", archive, member], None)
}

fn backup_shell_config(home: &Path) -> Result<(), Failure> {
    let source = home.join(".config").join("quickshell").join("caelestia");
    if !source.is_dir() {
        return Ok(());
    }
    let root = paths::cache_dir().join("caelestia-kde").join("backups");

    match install_fs::snapshot_dir(&source, &root, "quickshell-caelestia", 3) {
        Ok(destination) => {
            output::info(&format!(
                "Backed up shell configuration to {}",
                destination.display()
            ));
            Ok(())
        }
        Err(error) => Err(format!(
            "Could not back up shell configuration into {}: {error}",
            root.display()
        )
        .into()),
    }
}

// ---------------------------------------------------------------------------
// The workspace-tracker effect

fn workspace_stamp() -> PathBuf {
    paths::cache_dir()
        .join("caelestia-kde")
        .join("workspace-tracker.installed")
}

fn built_effect(shell_dir: &Path) -> Option<PathBuf> {
    let root = shell_dir.join("kwin-effects/workspace-tracker/build");
    let mut found = Vec::new();
    collect_so(&root, &mut found)?;
    found.sort();
    found.into_iter().next()
}

fn collect_so(directory: &Path, found: &mut Vec<PathBuf>) -> Option<()> {
    for entry in fs::read_dir(directory).ok()?.filter_map(Result::ok) {
        let path = entry.path();
        if path.is_dir() {
            collect_so(&path, found)?;
        } else if path.extension().and_then(|extension| extension.to_str()) == Some("so") {
            found.push(path);
        }
    }
    Some(())
}

fn installed_effect(name: &str) -> Option<PathBuf> {
    [
        "/usr/lib/qt6/plugins/kwin/effects/plugins",
        "/usr/lib64/qt6/plugins/kwin/effects/plugins",
    ]
    .iter()
    .map(|directory| Path::new(directory).join(name))
    .find(|candidate| candidate.is_file())
}

fn effect_signature(built: &Path, installed: &Path) -> String {
    let digest = download::sha256(built).unwrap_or_default();
    let stamp = fs::metadata(installed)
        .map(|metadata| {
            let modified = metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|since| since.as_secs())
                .unwrap_or_default();
            format!("{}:{modified}", metadata.len())
        })
        .unwrap_or_else(|_| "missing".to_string());
    format!("{digest} {stamp}\n")
}

fn effect_up_to_date(shell_dir: &Path) -> bool {
    let Some(built) = built_effect(shell_dir) else {
        return false;
    };
    let Some(name) = built.file_name() else {
        return false;
    };
    let Some(installed) = installed_effect(&name.to_string_lossy()) else {
        return false;
    };
    let stamp = workspace_stamp();
    fs::read_to_string(&stamp).unwrap_or_default() == effect_signature(&built, &installed)
}

fn record_effect_install(shell_dir: &Path) {
    let Some(built) = built_effect(shell_dir) else {
        return;
    };
    let Some(name) = built.file_name() else {
        return;
    };
    let Some(installed) = installed_effect(&name.to_string_lossy()) else {
        return;
    };

    let stamp = workspace_stamp();
    if let Some(parent) = stamp.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(stamp, effect_signature(&built, &installed));
}

fn build_workspace_tracker(shell_dir: &Path, theme: &Toolchain, jobs: &str, load: &str) {
    output::info("Building and installing workspace-tracker KWin Effect...");
    let build = shell_dir.join(EFFECT_DIR).join("build");
    if prepare_build_dir(&build, theme).is_err() {
        output::warn("Workspace tracker configuration failed; skipping KWin effect build.");
        return;
    }

    let configured = run_logged(
        build_command(
            "cmake",
            &[
                "-G",
                &theme.generator,
                "-B",
                "kwin-effects/workspace-tracker/build",
                "-S",
                EFFECT_DIR,
                "-DCMAKE_BUILD_TYPE=Release",
                "-DCMAKE_INSTALL_PREFIX=/usr",
            ],
            shell_dir,
        ),
        &paths::cache_dir().join("caelestia-kde/workspace-tracker-configure.log"),
        Logging::Silent,
    );
    if !matches!(configured, Ok(true)) {
        output::warn("Workspace tracker configuration failed; skipping KWin effect build.");
        return;
    }

    let build_log = paths::cache_dir().join("caelestia-kde/workspace-tracker-build.log");
    let built = run_logged(
        build_command(
            "cmake",
            &[
                "--build",
                "kwin-effects/workspace-tracker/build",
                &format!("-j{jobs}"),
                "--",
                "-l",
                load,
            ],
            shell_dir,
        ),
        &build_log,
        Logging::Silent,
    );
    if !matches!(built, Ok(true)) {
        output::warn(&format!(
            "Workspace tracker build failed. Full log: {}",
            build_log.display()
        ));
        show_build_errors(&build_log);
        return;
    }

    if effect_up_to_date(shell_dir) {
        output::info("Workspace tracker already up to date; skipping system install.");
        enable_effect(false);
        return;
    }

    let absolute = shell_dir.join(EFFECT_DIR).join("build");
    let absolute = absolute.to_string_lossy().to_string();
    if crate::privileges::elevated("cmake", &["--install", &absolute], None) != Ok(0) {
        output::warn("Workspace tracker system installation failed.");
        return;
    }
    record_effect_install(shell_dir);
    enable_effect(true);
}

fn enable_effect(reconfigure: bool) {
    let _ = process::succeeds(
        "kwriteconfig6",
        &[
            "--file",
            "kwinrc",
            "--group",
            "Plugins",
            "--key",
            "kwin_workspace_trackerEnabled",
            "true",
        ],
        None,
    );
    if reconfigure {
        let _ = process::succeeds("qdbus6", &["org.kde.KWin", "/KWin", "reconfigure"], None);
        output::ok("Installed workspace-tracker to KDE.");
    }
}

// ---------------------------------------------------------------------------
// What the shell needs on disk afterwards

fn check_qml_modules(home: &Path) -> Result<(), Failure> {
    let base = home.join(".local").join("lib").join("qt6").join("qml");

    for module in QML_MODULES {
        let directory = base.join(module);
        if !directory.join("qmldir").is_file() {
            return Err(format!(
                "Missing QML module metadata: {}",
                directory.join("qmldir").display()
            )
            .into());
        }

        let has_library = fs::read_dir(&directory)
            .map(|entries| {
                entries
                    .filter_map(Result::ok)
                    .any(|entry| entry.path().extension().is_some_and(|e| e == "so"))
            })
            .unwrap_or(false);
        if !has_library {
            return Err(format!("Missing QML plugin library in {}", directory.display()).into());
        }
    }
    Ok(())
}

fn install_support_files(bundle: &Path, home: &Path) -> Result<(), Failure> {
    let _ = fs::create_dir_all(home.join(".local").join("bin"));
    let units = home.join(".config").join("systemd").join("user");
    fs::create_dir_all(&units)
        .map_err(|error| format!("cannot use {}: {error}", units.display()))?;

    let lib_dir = install_kind::lib_dir();
    fs::create_dir_all(&lib_dir)
        .map_err(|error| format!("cannot use {}: {error}", lib_dir.display()))?;
    let state_lib = bundle.join("scripts/lib/update-state.sh");
    copy::file(&state_lib, &lib_dir.join("update-state.sh"))
        .map_err(|error| format!("cannot install the update-state helper: {error}"))?;

    output::info("Installing the update-checker units...");
    for unit in [
        "caelestia-update-checker.service",
        "caelestia-update-checker.timer",
    ] {
        copy::file(
            &bundle.join("src").join("systemd").join(unit),
            &units.join(unit),
        )
        .map_err(|error| format!("cannot install {unit}: {error}"))?;
    }

    if std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|value| !value.is_empty())
        .is_some()
    {
        let _ = process::succeeds("systemctl", &["--user", "daemon-reload"], None);
        if process::succeeds(
            "systemctl",
            &[
                "--user",
                "enable",
                "--now",
                "caelestia-update-checker.timer",
            ],
            None,
        ) {
            output::ok("Update-checker timer enabled");
        }
    } else {
        output::info("Skipping update-checker timer setup (no XDG_RUNTIME_DIR)");
    }
    Ok(())
}

fn install_icon_set(bundle: &Path, home: &Path) {
    let icons = bundle.join("src/yet-another-monochrome-icon-set");
    let destination =
        home.join(".config/quickshell/caelestia/assets/icons/yet-another-monochrome-icon-set");
    let staging = destination.with_file_name(format!(
        "{}.tmp",
        destination
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_default()
    ));

    if let Some(parent) = destination.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::remove_dir_all(&staging);
    if fs::create_dir_all(&staging).is_err() {
        output::warn("Failed to copy yet-another-monochrome-icon-set.");
        return;
    }

    if copy_tree_without_git(&icons, &staging).is_err() {
        let _ = fs::remove_dir_all(&staging);
        output::warn("Failed to copy yet-another-monochrome-icon-set.");
        return;
    }

    let _ = fs::remove_dir_all(&destination);
    if fs::rename(&staging, &destination).is_err() {
        let _ = fs::remove_dir_all(&staging);
        output::warn("Failed to copy yet-another-monochrome-icon-set.");
        return;
    }
    output::info("Yet another monochrome icon set copied successfully.");
}

// `rsync -a --exclude=.git`, including the part that matters here: a file the copy writes is
// writable afterwards, which a read-only checkout's own files are not.
fn copy_tree_without_git(source: &Path, destination: &Path) -> std::io::Result<()> {
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let name = entry.file_name();
        if name == ".git" {
            continue;
        }
        let target = destination.join(&name);
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            copy_tree_without_git(&entry.path(), &target)?;
        } else if file_type.is_symlink() {
            let _ = copy::symlink(&target, &fs::read_link(entry.path()).unwrap_or_default());
        } else {
            fs::copy(entry.path(), &target)?;
            make_writable(&target);
        }
    }
    Ok(())
}

// `--chmod=u+w`: a checkout can be mounted read-only, and the shell reads these icons at
// start-up. A copy on Windows is writable already.
fn make_writable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(metadata) = fs::metadata(path) {
            let mut permissions = metadata.permissions();
            permissions.set_mode(permissions.mode() | 0o200);
            let _ = fs::set_permissions(path, permissions);
        }
    }
    #[cfg(not(unix))]
    let _ = path;
}

// ---------------------------------------------------------------------------
// What an older install left behind

// The shell used to load every font under `assets/fonts`, so an install can hold two copies
// of them: the tree's own, which the CMake install puts in the config directory and never
// deletes files from, and the copy an older asset step downloaded into the user's asset
// directory. Nothing reads either directory now, and the two together are about 600 MiB on a
// machine that has both. Only what those two mechanisms could have put there is removed;
// anything the user added themselves stays.
fn cleanup_legacy_fonts(home: &Path) {
    let roots = [
        install_kind::shell_config()
            .parent()
            .map(|directory| directory.join("assets").join("fonts"))
            .unwrap_or_default(),
        home.join(".local/share/caelestia/assets/fonts"),
    ];

    for root in roots {
        let removed = cleanup_fonts_in(&root);
        if !removed.is_empty() {
            output::ok(&format!(
                "Reclaimed the fonts an older install left in {} ({}); the shell no longer loads them.",
                root.display(),
                removed.join(" ")
            ));
        }
    }
}

fn cleanup_fonts_in(root: &Path) -> Vec<String> {
    if !root.is_dir() {
        return Vec::new();
    }

    let mut removed = Vec::new();
    for entry in LEGACY_FONTS {
        let path = root.join(entry);
        if path.exists() && fs::remove_dir_all(&path).is_ok() {
            removed.push(entry.to_string());
        }
    }

    // The download copied the tree's own three-line README along with the fonts, and it
    // describes a directory nothing reads now. Only that exact text is removed.
    let readme = root.join("README.md");
    if fs::read_to_string(&readme)
        .map(|text| text.lines().next() == Some(LEGACY_FONT_README))
        .unwrap_or(false)
    {
        let _ = fs::remove_file(&readme);
    }

    let _ = fs::remove_dir(root);
    removed
}

fn cleanup_legacy_lockscreen(home: &Path) {
    if process::available("kpackagetool6") {
        let _ = process::succeeds(
            "kpackagetool6",
            &[
                "-t",
                "Plasma/Wallpaper",
                "-r",
                "net.dosowisko.PlasmaApplicationWallpaper",
            ],
            None,
        );
    }
    let _ = fs::remove_dir_all(
        home.join(".local/share/plasma/wallpapers/net.dosowisko.PlasmaApplicationWallpaper"),
    );
    let _ = fs::remove_file(
        paths::cache_dir()
            .join("caelestia-kde")
            .join("wallpaper-plugin-installed"),
    );

    if !process::available("kwriteconfig6") {
        return;
    }
    let _ = process::succeeds(
        "kwriteconfig6",
        &[
            "--file",
            "kscreenlockerrc",
            "--group",
            "Greeter",
            "--key",
            "WallpaperPlugin",
            "org.kde.image",
        ],
        None,
    );
    for (group, key) in [
        (
            "Wallpaper/net.dosowisko.PlasmaApplicationWallpaper/General",
            "command",
        ),
        ("LnF/General", "alwaysShowClock"),
        ("LnF/General", "showMediaControls"),
    ] {
        let mut args = vec!["--file", "kscreenlockerrc"];
        for part in group.split('/') {
            args.push("--group");
            args.push(part);
        }
        args.extend_from_slice(&["--key", key, "--delete"]);
        let _ = process::succeeds("kwriteconfig6", &args, None);
    }
    let _ = process::succeeds(
        "kwriteconfig6",
        &[
            "--file",
            "kscreenlockerrc",
            "--group",
            "Greeter",
            "--key",
            "Theme",
            "--delete",
        ],
        None,
    );
}

fn install_lockscreen_greeter(bundle: &Path, home: &Path) -> bool {
    let source = bundle.join(LOCKSCREEN_PACKAGE);
    let destination = home.join(".local/share/plasma/shells/caelestia.desktop");

    if !source.is_dir() {
        output::warn(&format!(
            "Caelestia lock screen greeter source not found: {}",
            source.display()
        ));
        return false;
    }

    output::info("Installing Caelestia lock screen greeter.");
    if install_fs::atomic_replace_tree(&source, &destination, Some("metadata.json")).is_err() {
        output::warn(&format!(
            "Failed to install Caelestia lock screen greeter to {}",
            destination.display()
        ));
        return false;
    }

    output::ok("Caelestia lock screen greeter installed.");
    true
}

fn configure_lockscreen_greeter(home: &Path) -> bool {
    if !process::available("kwriteconfig6") {
        output::warn(
            "KDE config tools (kwriteconfig6) not found. Skipping KDE Lock Screen configuration.",
        );
        return false;
    }

    let package = home.join(".local/share/plasma/shells/caelestia.desktop");
    if !package.is_dir() || !package.join("metadata.json").is_file() {
        output::warn(&format!(
            "Caelestia lock screen shell package not found at {}. Skipping lock screen configuration to prevent session lockout.",
            package.display()
        ));
        return false;
    }

    if process::succeeds(
        "kwriteconfig6",
        &[
            "--file",
            "plasmashellrc",
            "--group",
            "Shell",
            "--key",
            "ShellPackage",
            "caelestia.desktop",
        ],
        None,
    ) {
        output::ok("KDE Lock Screen configured to use Caelestia greeter.");
        return true;
    }
    output::warn("Failed to apply KDE Lock Screen configuration.");
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tmp::TempDir;

    fn run_git(directory: &Path, arguments: &[&str]) -> bool {
        std::process::Command::new("git")
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

    // A checkout of main with origin/main pointing at the same commit, which is what
    // install.sh leaves behind, plus a version.env naming the released version.
    fn seed_checkout(work: &TempDir, name: &str, version: &str) -> PathBuf {
        let repo = work.path().join(name);
        fs::create_dir_all(repo.join(".github")).expect("a checkout");
        fs::write(
            repo.join(".github/version.env"),
            format!("VERSION={version}\n"),
        )
        .expect("the version");
        run_git(&repo, &["init", "--quiet"]);
        run_git(&repo, &["symbolic-ref", "HEAD", "refs/heads/main"]);
        run_git(&repo, &["add", "-A"]);
        run_git(&repo, &["commit", "--quiet", "-m", "release"]);
        run_git(&repo, &["update-ref", "refs/remotes/origin/main", "HEAD"]);
        repo
    }

    #[test]
    fn main_sitting_on_its_remote_tip_may_use_the_prebuilt() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");

        assert!(checkout_may_use_prebuilt(&repo));
    }

    #[test]
    fn local_commits_on_main_build_locally() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        fs::write(repo.join("local.txt"), b"local").expect("a local file");
        run_git(&repo, &["add", "-A"]);
        run_git(&repo, &["commit", "--quiet", "-m", "unreleased local work"]);

        assert!(
            !checkout_may_use_prebuilt(&repo),
            "main with commits of its own must not be overwritten by the prebuilt"
        );
    }

    #[test]
    fn main_behind_its_remote_builds_locally() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        // The remote moves on while the checkout stays behind, as a stale local main does.
        run_git(
            &repo,
            &["commit", "--quiet", "--allow-empty", "-m", "released later"],
        );
        run_git(&repo, &["update-ref", "refs/remotes/origin/main", "HEAD"]);
        run_git(&repo, &["reset", "--quiet", "--hard", "HEAD~1"]);

        assert!(
            !checkout_may_use_prebuilt(&repo),
            "a stale main checkout must not be treated as the released revision"
        );
    }

    #[test]
    fn another_branch_builds_locally() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        run_git(&repo, &["checkout", "--quiet", "-b", "dev"]);

        assert!(
            !checkout_may_use_prebuilt(&repo),
            "dev must never install the prebuilt shell"
        );
    }

    #[test]
    fn the_released_tag_may_use_the_prebuilt() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        // An update pinned to a version: the checkout is the tag, not main's tip.
        run_git(
            &repo,
            &["commit", "--quiet", "--allow-empty", "-m", "next release"],
        );
        run_git(&repo, &["tag", "v2.0.0"]);
        fs::write(repo.join(".github/version.env"), "VERSION=v2.0.0\n").expect("the version");

        assert!(checkout_may_use_prebuilt(&repo));
    }

    #[test]
    fn a_version_that_is_not_the_tag_builds_locally() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        run_git(
            &repo,
            &["commit", "--quiet", "--allow-empty", "-m", "next release"],
        );
        run_git(&repo, &["tag", "v2.0.0"]);
        // version.env still names the older release, so the prebuilt would be older than
        // the tree it replaces.

        assert!(!checkout_may_use_prebuilt(&repo));
    }

    #[test]
    fn a_checkout_without_a_version_builds_locally() {
        if !process::available("git") {
            return;
        }
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let repo = seed_checkout(&work, "repo", "v1.0.0");
        fs::remove_file(repo.join(".github/version.env")).expect("the version goes");

        assert!(
            !checkout_may_use_prebuilt(&repo),
            "without a version there is no release artifact to fetch"
        );
    }

    #[test]
    fn a_tree_that_is_not_a_checkout_builds_locally() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let tree = work.path().join("tree");
        fs::create_dir_all(tree.join(".github")).expect("a tree");
        fs::write(tree.join(".github/version.env"), "VERSION=v1.0.0\n").expect("the version");

        assert!(
            !checkout_may_use_prebuilt(&tree),
            "a source tree without git history must build locally"
        );
    }

    #[test]
    fn the_fonts_an_older_install_left_go_and_the_rest_stays() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let fonts = work.path().join("assets/fonts");
        for directory in ["SF-Pro", "SF-Mono", "google-sans-flex", "MyFonts"] {
            fs::create_dir_all(fonts.join(directory)).expect("a font directory");
            fs::write(fonts.join(directory).join("font.ttf"), b"font").expect("a font");
        }
        fs::write(
            fonts.join("README.md"),
            "# Fonts\n\nThe shell loads every .ttf/.otf found here at startup.\n",
        )
        .expect("the shipped readme");
        fs::write(work.path().join("assets/emojis.txt"), b"emoji").expect("the emoji database");

        let removed = cleanup_fonts_in(&fonts);

        assert_eq!(removed, ["SF-Pro", "SF-Mono", "google-sans-flex"]);
        assert!(!fonts.join("SF-Pro").exists());
        assert!(!fonts.join("README.md").exists());
        assert!(
            fonts.join("MyFonts/font.ttf").is_file(),
            "a font the user added themselves stays"
        );
        assert!(
            work.path().join("assets/emojis.txt").is_file(),
            "the emoji database beside it is not ours to remove"
        );
        assert!(
            fonts.is_dir(),
            "the directory stays while something of the user's is in it"
        );
    }

    #[test]
    fn only_the_shipped_readme_is_removed() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let fonts = work.path().join("fonts");
        fs::create_dir_all(&fonts).expect("the fonts directory");
        fs::write(fonts.join("MyFont.ttf"), b"font").expect("a font");
        fs::write(fonts.join("README.md"), "# My own font notes\n").expect("a readme");

        let removed = cleanup_fonts_in(&fonts);

        assert!(removed.is_empty());
        assert!(fonts.join("README.md").is_file(), "that one is the user's");
        assert!(fonts.join("MyFont.ttf").is_file());
    }

    #[test]
    fn a_fonts_directory_goes_once_it_is_empty() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let fonts = work.path().join("fonts");
        fs::create_dir_all(fonts.join("SF-Pro")).expect("a font directory");
        fs::write(fonts.join("SF-Pro/font.ttf"), b"font").expect("a font");
        fs::write(work.path().join("emojis.txt"), b"emoji").expect("the emoji database");

        assert_eq!(cleanup_fonts_in(&fonts), ["SF-Pro"]);

        assert!(
            !fonts.exists(),
            "an emptied directory goes with its contents"
        );
        assert!(work.path().join("emojis.txt").is_file());
    }

    #[test]
    fn a_machine_that_never_installed_fonts_is_a_no_op() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");

        assert_eq!(
            cleanup_fonts_in(&work.path().join("absent")),
            Vec::<String>::new()
        );
    }

    #[test]
    fn a_toolchain_is_the_same_across_a_patch_release() {
        assert_eq!(normalize_version("3.28.3"), "3.28");
        assert_eq!(
            normalize_version("cmake version 3.28.1"),
            "cmake version 3.28"
        );
        assert_eq!(normalize_version("6"), "6");
        assert_eq!(normalize_version(""), "");
    }

    #[test]
    fn a_build_directory_is_kept_only_while_the_toolchain_is_the_one_it_was_made_with() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let directory = work.path().join("build");
        let theme = Toolchain {
            bundle: work.path().join("bundle"),
            generator: "Ninja".to_string(),
        };

        prepare_build_dir(&directory, &theme).expect("the build directory is prepared");
        fs::write(directory.join("CMakeCache.txt"), b"cache").expect("a configured cache");
        fs::write(directory.join("leftover.o"), b"object").expect("a build output");

        prepare_build_dir(&directory, &theme).expect("the same toolchain keeps the directory");
        assert!(
            directory.join("leftover.o").is_file(),
            "a configured directory with the same stamp is reused"
        );

        let other = Toolchain {
            bundle: work.path().join("bundle"),
            generator: "Unix Makefiles".to_string(),
        };
        prepare_build_dir(&directory, &other).expect("the build directory is prepared");
        assert!(
            !directory.join("leftover.o").exists(),
            "another generator starts from an empty directory"
        );
        assert!(!directory.join("CMakeCache.txt").is_file());
    }

    #[test]
    fn the_environment_names_the_layout_the_install_has() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let home = work.path().join("home");
        fs::create_dir_all(&home).expect("a home directory");

        write_shell_environment(&home).expect("the environment is written");

        let environment = fs::read_to_string(home.join(".config/environment.d/caelestia.conf"))
            .expect("the session environment");
        for key in [
            "QML2_IMPORT_PATH=",
            "CAELESTIA_LIB_DIR=",
            "CAELESTIA_BIN_DIR=",
            "CAELESTIA_SHELL_CONFIG=",
        ] {
            assert!(environment.contains(key), "{key} is missing: {environment}");
        }

        let plasma = home.join(".config/plasma-workspace/env/caelestia.sh");
        let script = fs::read_to_string(&plasma).expect("the Plasma environment");
        assert!(script.starts_with("#!/bin/sh\n"), "{script}");
        assert!(
            script.contains("export PATH=\""),
            "the command directory goes on PATH: {script}"
        );
        assert!(
            plasma.is_file(),
            "the Plasma session sources this file by path"
        );
    }

    #[test]
    fn the_environment_lines_an_older_install_added_are_taken_out() {
        let work = TempDir::new("caelestia-build-shell-test").expect("a temporary directory");
        let home = work.path().join("home");
        fs::create_dir_all(&home).expect("a home directory");
        fs::write(
            home.join(".bashrc"),
            "export EDITOR=nvim\nexport CAELESTIA_LIB_DIR=\"$HOME/.local/lib/caelestia\"\nexport QML2_IMPORT_PATH=\"$HOME/.local/lib/qt6/qml:caelestia\"\n",
        )
        .expect("a shell rc");

        write_shell_environment(&home).expect("the environment is written");

        let rc = fs::read_to_string(home.join(".bashrc")).expect("the shell rc");
        assert!(rc.contains("export EDITOR=nvim"), "{rc}");
        assert!(
            !rc.contains("CAELESTIA_LIB_DIR"),
            "the session gets it from environment.d now: {rc}"
        );
        assert!(!rc.contains("QML2_IMPORT_PATH"), "{rc}");
    }

    #[test]
    fn the_sparse_rules_are_the_paths_an_older_updater_never_fetched() {
        assert_eq!(SPARSIFY, ["installer/", "assets/", "uninstall.sh"]);
        for rule in SPARSIFY {
            assert!(rule.ends_with('/') || rule == "uninstall.sh", "{rule}");
        }
    }

    // The updater of the release before this one wrote its own rules into the checkout, so
    // an install still on it is missing whatever this release added. The repair asks git for
    // those paths again rather than re-cloning, and leaves everything already held alone.
    #[test]
    fn the_repair_fills_what_a_sparse_checkout_left_out() {
        if !process::available("git") {
            return;
        }

        let work = TempDir::new("caelestia-sparse").expect("a temporary directory");
        let repo = work.path().join("checkout");
        fs::create_dir_all(repo.join("shell")).expect("a checkout");
        fs::write(repo.join("shell/CMakeLists.txt"), "project(shell)\n").expect("a file");
        for rule in SPARSIFY {
            let path = repo.join(rule.trim_end_matches('/'));
            if rule.ends_with('/') {
                fs::create_dir_all(&path).expect("a directory");
                fs::write(path.join("content"), rule).expect("a file");
            } else {
                fs::write(&path, rule).expect("a file");
            }
        }
        run_git(&repo, &["init", "--quiet"]);
        run_git(&repo, &["add", "-A"]);
        run_git(&repo, &["commit", "--quiet", "-m", "release"]);
        run_git(&repo, &["config", "core.sparseCheckout", "true"]);
        // Only the shell is selected: what an install that predates the rest of the rules has.
        fs::write(repo.join(".git/info/sparse-checkout"), "/shell/\n").expect("the rules");
        run_git(&repo, &["read-tree", "-mu", "HEAD"]);

        assert!(!repo.join("installer/content").exists(), "the fixture");
        assert!(!repo.join("assets/content").exists(), "the fixture");
        assert!(!repo.join("uninstall.sh").exists(), "the fixture");

        sparsify_checkout_paths(&repo);

        assert!(repo.join("installer/content").is_file(), "installer/");
        assert!(repo.join("assets/content").is_file(), "assets/");
        assert!(repo.join("uninstall.sh").is_file(), "uninstall.sh");
        assert!(
            repo.join("shell/CMakeLists.txt").is_file(),
            "a selected path was dropped"
        );
        let rules = fs::read_to_string(repo.join(".git/info/sparse-checkout")).expect("the rules");
        for rule in SPARSIFY {
            assert!(
                rules.lines().any(|line| line == rule),
                "{rule} is not named in the rules: {rules}"
            );
        }
    }
}
