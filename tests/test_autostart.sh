#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/shell/scripts/autostart.py"
SERVICE="$REPO_ROOT/shell/services/Autostart.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/startup/AutostartPage.qml"
PICKER="$REPO_ROOT/shell/modules/nexus/pages/startup/AutostartAppPicker.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
PYTHON="$(command -v python3 || command -v python)"

# A throwaway set of XDG directories, so the test never reads or writes the real ones.
sandbox() {
    SANDBOX="$("$PYTHON" - <<'PY'
import tempfile

print(tempfile.mkdtemp())
PY
)"
    export XDG_CONFIG_HOME="$SANDBOX/config"
    export XDG_CONFIG_DIRS="$SANDBOX/etc"
    export XDG_DATA_HOME="$SANDBOX/data"
    export XDG_DATA_DIRS="$SANDBOX/usr/share"
    mkdir -p "$XDG_CONFIG_HOME/autostart" "$XDG_CONFIG_DIRS/autostart" \
        "$XDG_DATA_HOME/applications" "$XDG_DATA_DIRS/applications"
}

desktop_file() {
    # desktop_file PATH Name Exec [extra lines...]
    local path="$1" name="$2" exec="$3"
    shift 3
    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Name=$name"
        echo "Exec=$exec"
        for line in "$@"; do echo "$line"; done
    } >"$path"
}

test_the_list_merges_system_and_user_entries() {
    sandbox
    desktop_file "$XDG_CONFIG_DIRS/autostart/system-app.desktop" "System App" "system-app --flag"
    desktop_file "$XDG_CONFIG_HOME/autostart/own-app.desktop" "My App" "my-app" "Hidden=true"

    local listed
    listed="$("$PYTHON" "$SCRIPT" --list)"

    assert_contains "$listed" '"id": "system-app"' "system entries are listed"
    assert_contains "$listed" '"id": "own-app"' "and so are the user's"
    assert_contains "$listed" '"system": true' "a system entry says where it came from"
    assert_contains "$listed" '"enabled": false' "a Hidden entry is listed as off"

    # The page reads the list top to bottom, so it is ordered by what it shows, not by the
    # desktop file's name.
    local names
    names="$(printf '%s' "$listed" | "$PYTHON" -c 'import json,sys; print(" | ".join(e["name"] for e in json.load(sys.stdin)))')"
    assert_eq "My App | System App" "$names" "entries are ordered by their name"
    rm -rf "$SANDBOX"
}

test_switching_a_system_entry_off_writes_an_override() {
    sandbox
    desktop_file "$XDG_CONFIG_DIRS/autostart/system-app.desktop" "System App" "system-app"

    "$PYTHON" "$SCRIPT" --set system-app off >/dev/null
    assert_eq "yes" "$([ -f "$XDG_CONFIG_HOME/autostart/system-app.desktop" ] && echo yes)" \
        "the override is a copy in the user's directory, which is how KDE does it"
    assert_contains "$(cat "$XDG_CONFIG_HOME/autostart/system-app.desktop")" "Hidden=true" \
        "the copy is what switches it off"
    assert_contains "$("$PYTHON" "$SCRIPT" --list)" '"enabled": false' "and the list agrees"

    "$PYTHON" "$SCRIPT" --set system-app on >/dev/null
    assert_contains "$("$PYTHON" "$SCRIPT" --list)" '"enabled": true' "switching it back on clears that"
    assert_not_contains "$(cat "$XDG_CONFIG_HOME/autostart/system-app.desktop")" "Hidden=true" \
        "by removing the key rather than adding a second one"
    rm -rf "$SANDBOX"
}

test_editing_keeps_the_rest_of_the_file() {
    sandbox
    printf '# a comment the user wrote\n[Desktop Entry]\nType=Application\nName=Keep Me\nExec=keep-me\nX-Custom=kept\n' \
        >"$XDG_CONFIG_HOME/autostart/keep.desktop"

    "$PYTHON" "$SCRIPT" --set keep off >/dev/null
    local edited
    edited="$(cat "$XDG_CONFIG_HOME/autostart/keep.desktop")"

    assert_contains "$edited" "X-Custom=kept" "unrelated keys survive"
    assert_contains "$edited" "# a comment the user wrote" "and so do comments"
    assert_contains "$edited" "Hidden=true" "while the switch is written"
    rm -rf "$SANDBOX"
}

test_removing_only_touches_the_users_own_entry() {
    sandbox
    desktop_file "$XDG_CONFIG_DIRS/autostart/system-app.desktop" "System App" "system-app"
    desktop_file "$XDG_CONFIG_HOME/autostart/own-app.desktop" "My App" "my-app"

    "$PYTHON" "$SCRIPT" --remove own-app >/dev/null
    assert_eq "yes" "$([ ! -f "$XDG_CONFIG_HOME/autostart/own-app.desktop" ] && echo yes)" "the entry is gone"
    assert_eq "no" "$("$PYTHON" "$SCRIPT" --remove system-app >/dev/null 2>&1 && echo yes || echo no)" \
        "a system entry cannot be removed, only switched off"
    rm -rf "$SANDBOX"
}

test_an_installed_application_can_be_added() {
    sandbox
    desktop_file "$XDG_DATA_DIRS/applications/org.example.App.desktop" "Example" "example"

    "$PYTHON" "$SCRIPT" --add org.example.App >/dev/null
    assert_eq "yes" "$([ -f "$XDG_CONFIG_HOME/autostart/org.example.App.desktop" ] && echo yes)" \
        "the application's own desktop file is the source"
    assert_contains "$("$PYTHON" "$SCRIPT" --list)" '"name": "Example"' "and it shows up straight away"
    rm -rf "$SANDBOX"
}

test_the_page_and_service_drive_the_script() {
    local service page picker dictionary registry
    service="$(cat "$SERVICE")"
    page="$(cat "$PAGE")"
    picker="$(cat "$PICKER")"
    dictionary="$(cat "$DICTIONARY")"
    registry="$(cat "$REGISTRY")"

    assert_contains "$service" 'Quickshell.shellPath("scripts/autostart.py")' "the script owns the files"
    assert_contains "$service" 'function setEnabled(id: string, on: bool): void' "switching an entry"
    assert_contains "$service" 'onExited: root.refresh()' "every edit is re-read, because the file is the truth"
    assert_contains "$page" 'model: root.entries' "the page lists what the service found"
    assert_contains "$page" 'Autostart.setEnabled(entryRow.modelData.id, checked)' "and toggles it"
    assert_contains "$page" 'visible: entryRow.modelData.own' "only the user's own entry can be removed"
    assert_contains "$picker" 'Autostart.add(appRow.modelData.id)' "adding copies an installed application in"
    assert_contains "$dictionary" 'key: "startup"' "the page exists in the dictionary"
    assert_contains "$dictionary" 'category: "system"' "among the system pages"
    assert_contains "$registry" 'Component { AutostartPage {} }' "and is registered"
    assert_contains "$registry" 'Component { AutostartAppPicker {} }' "with its application picker"
}

run_tests
