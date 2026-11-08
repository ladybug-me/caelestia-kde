#!/usr/bin/env bash
# suite: fast
#
# The notification sound is the one sound with a name that comes from a setting, and it used to
# be played by a path that skipped the switch every other sound effect honours.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO="$REPO_ROOT/shell/services/Audio.qml"

play_notification_block() {
    sed -n '/function playNotification(): void {/,/^    }$/p' "$AUDIO"
}

test_the_notification_sound_follows_the_sounds_switch() {
    local block
    block="$(play_notification_block)"

    [[ -n "$block" ]] || {
        fail "playNotification has to be readable out of Audio.qml"
        return 0
    }

    assert_contains "$block" 'playSoundSource(' \
        "it is a sound effect like the rest, so it goes through the same gate"
    assert_file_contains "$AUDIO" 'if (!GlobalConfig.audio.sounds.enabled || !enabled)' \
        "which is the one place the switch is read"
}

# The name is a setting, so a path in it would play a file from anywhere on the machine on
# the shell's behalf.
test_the_notification_sound_name_cannot_leave_the_bundled_sounds() {
    local block
    block="$(play_notification_block)"

    assert_contains "$block" 'if (name.includes("/"))' \
        "a name that carries a path is refused rather than resolved"
}

run_tests
