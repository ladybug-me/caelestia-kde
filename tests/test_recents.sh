#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/shell/scripts/recents.py"
SERVICE="$REPO_ROOT/shell/services/Recents.qml"
DOCK_MENU="$REPO_ROOT/shell/modules/bar/popouts/DockContext.qml"
PYTHON="$(command -v python3 || command -v python)"

TMP="$("$PYTHON" -c 'import tempfile; print(tempfile.mkdtemp())')"
trap 'rm -rf "$TMP"' EXIT

# A recent-documents list with two files that still exist, one that does not, a web page that
# is not a file at all, and the same file recorded twice — once by each application that
# opened it, which is how the freedesktop list records two visits.
prepare() {
    mkdir -p "$TMP/files"
    : > "$TMP/files/notes.txt"
    : > "$TMP/files/shot.png"
    : > "$TMP/files/shared.txt"

    "$PYTHON" - "$TMP/recently-used.xbel" "$TMP/files" <<'PY'
import sys
from pathlib import Path

target, files = sys.argv[1], Path(sys.argv[2])
uris = {name: (files / f"{name}.{suffix}").as_uri() for name, suffix in (("notes", "txt"), ("shared", "txt"), ("shot", "png"), ("deleted", "txt"))}
template = """<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"
      xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">
  <bookmark href="{notes}" modified="2026-10-03T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="text/plain"/>
      <bookmark:applications><bookmark:application name="org.kde.kate" exec="/usr/bin/kate %U" count="2"/></bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="{notes}" modified="2026-10-09T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="text/plain"/>
      <bookmark:applications><bookmark:application name="org.kde.okular" exec="/usr/bin/okular %U" count="1"/></bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="{shared}" modified="2026-10-07T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="text/plain"/>
      <bookmark:applications>
        <bookmark:application name="org.kde.kate" exec="/usr/bin/kate %U" count="1" modified="2026-10-01T10:00:00Z"/>
        <bookmark:application name="org.kde.okular" exec="/usr/bin/okular %U" count="3" modified="2026-10-07T10:00:00Z"/>
      </bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="{shot}" modified="2026-10-05T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="image/png"/>
      <bookmark:applications><bookmark:application name="org.kde.spectacle" exec="/usr/bin/spectacle %f" count="1"/></bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="{deleted}" modified="2026-10-06T10:00:00Z">
    <info><metadata owner="http://freedesktop.org">
      <mime:mime-type type="text/plain"/>
      <bookmark:applications><bookmark:application name="org.kde.kate" exec="/usr/bin/kate %U" count="1"/></bookmark:applications>
    </metadata></info>
  </bookmark>
  <bookmark href="https://example.com/page" modified="2026-10-08T10:00:00Z"/>
</xbel>
"""

open(target, "w", encoding="utf-8").write(template.format(**uris))
PY
}

names() {
    "$PYTHON" -c 'import json,sys; print(" ".join(entry["name"] for entry in json.load(sys.stdin)))'
}

stamps() {
    "$PYTHON" -c 'import json,sys; print(" ".join(entry["modified"] for entry in json.load(sys.stdin)))'
}

test_only_files_that_are_still_there_and_newest_first() {
    prepare

    assert_eq "notes.txt shared.txt shot.png" "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" | names)" \
        "a deleted file and a web page are not documents you can open from a jump list, and the newest visit comes first"
}

# The same file recorded twice — once per application that opened it — is how the freedesktop
# list spells two visits. Picking the newest row before asking which application opened it is
# what silently drops the file from the first application's jump list.
test_each_application_keeps_its_own_visit_to_the_same_file() {
    prepare

    assert_eq "notes.txt shared.txt" "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app kate | names)" \
        "a file another application opened later is still in this application's list"
    assert_eq "2026-10-03T10:00:00Z 2026-10-01T10:00:00Z" \
        "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app kate | stamps)" \
        "and it is ordered by when this application opened it, not by when anyone last did"
    assert_eq "2026-10-09T10:00:00Z 2026-10-07T10:00:00Z" \
        "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app okular | stamps)" \
        "the other application sees the same two files at its own times"
}

test_a_jump_list_is_one_applications_history() {
    prepare

    assert_eq "shot.png" "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app org.kde.spectacle.desktop | names)" \
        "filtering by the desktop entry id the dock knows, which is spelled differently"
    assert_eq "shot.png notes.txt shared.txt" \
        "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app kate --app spectacle | names)" \
        "several names for one application still make one list"
    assert_eq "" "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --app nothing-opened-this | names)" \
        "an application that opened nothing gets nothing, not everything"
}

test_the_limit_is_the_menu_size() {
    prepare

    assert_eq "notes.txt" "$("$PYTHON" "$SCRIPT" --file "$TMP/recently-used.xbel" --limit 1 | names)" \
        "the menu asks for a handful, not the whole history"
    assert_file_contains "$SERVICE" '"--limit", "5"' "and five is what it asks for"
}

# Some writers hand out `file:////home/...`, and POSIX's url2pathname refuses a path that
# starts with two slashes — on such a machine the jump list used to come back empty.
test_a_href_with_an_extra_slash_still_names_a_file() {
    mkdir -p "$TMP/odd"
    : > "$TMP/odd/odd.txt"
    "$PYTHON" - "$TMP/odd.xbel" "$TMP/odd/odd.txt" <<'PY'
import sys
from pathlib import Path

target, path = sys.argv[1], Path(sys.argv[2])
href = path.as_uri().replace("file:///", "file:////")
open(target, "w", encoding="utf-8").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">\n'
    f'  <bookmark href="{href}" modified="2026-10-01T10:00:00Z">\n'
    '    <info><metadata owner="http://freedesktop.org"><bookmark:applications>'
    '<bookmark:application name="org.kde.kate"/></bookmark:applications></metadata></info>\n'
    '  </bookmark>\n'
    '</xbel>\n'
)
PY

    assert_eq "odd.txt" "$("$PYTHON" "$SCRIPT" --file "$TMP/odd.xbel" | names)" \
        "a doubled leading slash is still a local file, not a bookmark on another host"
}

test_the_dock_menu_offers_them() {
    assert_file_contains "$SERVICE" 'script: "scripts/recents.py"' "one owner for the file"
    assert_file_contains "$DOCK_MENU" 'Recents.load(root.appNames)' "the menu asks for this application's history when it opens"
    assert_file_contains "$DOCK_MENU" 'Launch.exec(["xdg-open", entry.path])' "and opens the file"
    assert_file_contains "$DOCK_MENU" 'qsTr("Recent files")' "the row has a heading"
}

run_tests
