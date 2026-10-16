//! The KDE config tools, faked against one plain ini file.
//!
//! The installer writes window rules and lock-screen settings through `kwriteconfig6` and
//! reads them back through `kreadconfig6`, and an uninstall reverses what it finds. Both
//! integration suites need those two tools to behave the way they do on a desktop - one file,
//! written and read back - rather than answer from a fixture.

#![allow(dead_code)]

#[cfg(unix)]
use std::path::{Path, PathBuf};

const CONFIG_TOOLS: &str = r##"
import os
import sys
from pathlib import Path


def arguments(argv):
    values = {"file": "kwinrulesrc", "group": "", "key": ""}
    positional = []
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument in ("--file", "--group", "--key") and index + 1 < len(argv):
            values[argument[2:]] = argv[index + 1]
            index += 2
        else:
            positional.append(argument)
            index += 1
    return values, positional


def read(path):
    sections = {}
    current = None
    if not path.is_file():
        return sections
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
        elif current is not None and "=" in line:
            key, _, value = line.partition("=")
            sections[current][key.strip()] = value.strip()
    return sections


def write(path, sections):
    lines = []
    for name, entries in sections.items():
        if not entries:
            continue
        lines.append("[%s]" % name)
        for key, value in entries.items():
            lines.append("%s=%s" % (key, value))
        lines.append("")
    path.write_text("\n".join(lines))


def main():
    mode = sys.argv[1]
    values, positional = arguments(sys.argv[2:])
    path = Path(values["file"])
    if not path.is_absolute():
        path = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / path
    sections = read(path)

    if mode == "get":
        value = sections.get(values["group"], {}).get(values["key"])
        if value is None:
            return 1
        print(value)
        return 0

    if mode == "delete":
        entries = sections.get(values["group"])
        if entries is not None:
            entries.pop(values["key"], None)
            if not entries:
                del sections[values["group"]]
        write(path, sections)
        return 0

    sections.setdefault(values["group"], {})[values["key"]] = positional[0]
    write(path, sections)
    return 0


sys.exit(main())
"##;

/// The stubs, the file they share, and the log of what was asked of them.
#[cfg(unix)]
pub struct ConfigTools {
    pub program: PathBuf,
    pub config: PathBuf,
    pub calls: PathBuf,
}

/// Installs the two config tools into `bin`, which the caller has already made.
#[cfg(unix)]
pub fn config_tools(root: &Path, bin: &Path) -> ConfigTools {
    let program = root.join("kwinrules.py");
    let config = root.join("config");
    let calls = root.join("calls.log");
    std::fs::create_dir_all(&config).expect("the config directory");
    std::fs::write(&program, CONFIG_TOOLS).expect("the config-tool program");
    std::fs::write(&calls, "").expect("the call log");

    stub(
        bin,
        "kreadconfig6",
        "#!/bin/sh\nexec python3 \"$KW_RULES\" get \"$@\"\n",
    );
    stub(
        bin,
        "kwriteconfig6",
        "#!/bin/sh\nprintf '%s %s\\n' 'kwriteconfig6' \"$*\" >> \"$KW_CALLS\"\n\
         if [ -n \"${KW_SILENT_REJECT:-}\" ]; then exit 0; fi\n\
         case \"$*\" in *--delete*) exec python3 \"$KW_RULES\" delete \"$@\" ;; esac\n\
         exec python3 \"$KW_RULES\" set \"$@\"\n",
    );

    ConfigTools {
        program,
        config,
        calls,
    }
}

/// The environment the two stubs need to find the program and the log.
#[cfg(unix)]
pub fn config_tools_environment(tools: &ConfigTools) -> Vec<(String, String)> {
    vec![
        (
            "XDG_CONFIG_HOME".to_string(),
            tools.config.to_string_lossy().to_string(),
        ),
        (
            "KW_RULES".to_string(),
            tools.program.to_string_lossy().to_string(),
        ),
        (
            "KW_CALLS".to_string(),
            tools.calls.to_string_lossy().to_string(),
        ),
    ]
}

#[cfg(unix)]
pub fn stub(bin: &Path, name: &str, body: &str) {
    use std::os::unix::fs::PermissionsExt;

    let path = bin.join(name);
    std::fs::write(&path, body).expect("a stub");
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).expect("an executable");
}

/// Every call the stub was asked to make, in order.
#[cfg(unix)]
pub fn calls(tools: &ConfigTools) -> Vec<String> {
    std::fs::read_to_string(&tools.calls)
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}
