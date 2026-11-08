#!/usr/bin/env bash
# The programs the installer uses to make a security decision, named so that the user's
# own PATH cannot stand in for them.
if [[ -z "${CAELESTIA_TOOLS_SOURCED:-}" ]]; then
CAELESTIA_TOOLS_SOURCED=1

# The absolute path of "$1", from a directory only root can write.
#
# A source install puts the user's bin directory first on PATH, and this project's threat
# model already includes something writing there. A `sha256sum` that reports whatever it is
# asked to, a `jq` that names a different download, or a `stat` that calls a file root's is
# then enough to have root install content no release published - so every program a check
# depends on is named by absolute path rather than looked up.
#
# PATH is still the fallback for a system that keeps coreutils somewhere else; a caller in
# that position is no worse off than before this existed.
system_tool() {
    local name="$1" candidate
    for candidate in "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v "$name"
}

fi
