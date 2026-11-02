#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPC_BIN="$REPO_ROOT/src/bin/caelestia-shell-ipc"

# A stand-in for quickshell that misbehaves the way the real one does: under a
# non-UTF-8 locale Qt writes its warning to stdout before the reply, which is what
# used to end up in `... call notifs list | jq`.
install_locale_sensitive_stub() {
    local dir="$1"

    mkdir -p "$dir"
    cat > "$dir/quickshell" <<'STUB'
#!/usr/bin/env bash
printf 'SEEN=%s\n' "${LC_ALL:-}" >&2
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) ;;
    *) printf 'WARN: Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not UTF-8.\n' ;;
esac
printf '%s\n' '{"dnd":false,"items":[]}'
STUB
    chmod +x "$dir/quickshell"
}

prepared_env() {
    local tmp="$1"

    mkdir -p "$tmp/cfg"
    : > "$tmp/cfg/shell.qml"
    printf '%s\n' "$tmp"
}

test_the_reply_is_alone_on_stdout_under_a_c_locale() {
    local tmp out
    tmp="$(new_tmpdir)"
    prepared_env "$tmp" >/dev/null
    install_locale_sensitive_stub "$tmp/bin"

    out="$(LANG=C LC_ALL= LC_CTYPE= PATH="$tmp/bin:$PATH" CAELESTIA_SHELL_CONFIG="$tmp/cfg/shell.qml" bash "$IPC_BIN" call notifs list 2>/dev/null)"

    assert_eq '{"dnd":false,"items":[]}' "$out" \
        "Qt's locale warning must not precede the IPC reply, or every pipe breaks"
}

test_a_caller_locale_that_is_already_utf8_is_kept() {
    local tmp seen
    tmp="$(new_tmpdir)"
    prepared_env "$tmp" >/dev/null
    install_locale_sensitive_stub "$tmp/bin"

    seen="$(LC_ALL=en_GB.UTF-8 PATH="$tmp/bin:$PATH" CAELESTIA_SHELL_CONFIG="$tmp/cfg/shell.qml" bash "$IPC_BIN" call notifs list 2>&1 1>/dev/null | grep '^SEEN=' | head -1)"

    assert_eq 'SEEN=en_GB.UTF-8' "$seen" \
        "a UTF-8 locale the caller chose must not be overridden"
}

run_tests
