#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$REPO_ROOT/shell/services"
BAR_COMPONENTS="$REPO_ROOT/shell/modules/bar/components"
BAR_POPOUTS="$REPO_ROOT/shell/modules/bar/popouts"
CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config"
NEXUS_PANELS="$REPO_ROOT/shell/modules/nexus/pages/panels/taskbar"
PRIVACY="$SERVICES/Privacy.qml"

test_microphone_capture_is_what_the_audio_service_reports() {
    assert_file_contains "$SERVICES/Audio.qml" 'readonly property var captureStreams:' \
        "the audio service owns what a capture stream is, next to the streams it already tracks"
    assert_file_contains "$SERVICES/Audio.qml" '"Stream/Input/Audio"' \
        "and it is the only place that has to know the PipeWire class name"
    assert_file_not_contains "$PRIVACY" 'media.class' \
        "the privacy service must not re-derive stream kinds from PipeWire"

    assert_file_contains "$PRIVACY" 'for (const stream of Audio.captureStreams)' \
        "capture streams are what it counts"
    assert_file_contains "$PRIVACY" 'name !== Audio.selfAppName' \
        "the shell's own capture must not light the indicator"
    assert_file_contains "$PRIVACY" 'names.includes(name)' \
        "one name per application, not one per stream"
}

test_video_capture_comes_from_the_native_watcher() {
    assert_file_contains "$PRIVACY" 'PipewireStreamWatcher.activeStreams' \
        "screen and camera capture is what the native watcher reports"
}

test_the_service_reports_facts_and_the_views_present_them() {
    assert_file_contains "$PRIVACY" 'readonly property bool inUse: root.microphoneApps.length > 0 || root.videoApps.length > 0' \
        "there has to be one answer to whether anything is capturing"
    assert_file_not_contains "$PRIVACY" 'qsTr(' \
        "labels belong to the view, not to a service"
    assert_file_not_contains "$PRIVACY" 'entries' \
        "the service must not hand out rows"

    assert_file_contains "$BAR_COMPONENTS/StatusIcons.qml" 'case "privacy":' "the bar has to know the icon id"
    assert_file_contains "$BAR_COMPONENTS/StatusIcons.qml" 'return Privacy.inUse;' \
        "and the icon may only appear while something is capturing"
    assert_file_contains "$BAR_POPOUTS/Privacy.qml" 'QsServices.Privacy.microphoneApps' \
        "the popout builds its rows from the facts"
}

test_the_icon_is_shipped_but_never_resurrected() {
    assert_file_contains "$CONFIG/barconfig.hpp" 'LIST_ENTRY(privacy, true)' \
        "new configs get the icon in the status area"
    assert_file_contains "$NEXUS_PANELS/BarStatusIcons.qml" 'privacy: qsTr("Privacy")' \
        "the status icon editor needs a label for it"
    assert_file_not_contains "$SERVICES/ConfigMigrations.qml" 'privacy' \
        "a list the user edited is theirs: re-inserting a removed icon on every start is worse than one click in Nexus"
}

test_the_popout_is_registered() {
    assert_file_exists "$BAR_POPOUTS/Privacy.qml"
    assert_file_contains "$BAR_POPOUTS/Content.qml" 'name: "privacy"' "the popout has to be registered"
}

run_tests