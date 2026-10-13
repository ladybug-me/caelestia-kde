#!/usr/bin/env bash

# Window classes Krohnkite leaves untiled. Krohnkite compares an entry against the
# window class and the resource name exactly, ignoring case, so an app that can
# report either the bare name or the reverse-DNS class gets both spellings. The
# entries from org.pulseaudio.pavucontrol on are the dialog and settings classes
# upstream Hyprland floats. The order is upstream's and is kept: a run only ever
# appends the entries the list does not already hold.
IGNORE_CLASSES=(
    krunner
    yakuake
    spectacle
    kded5
    xwaylandvideobridge
    plasmashell
    ksplashqml
    org.kde.plasmashell
    org.kde.polkit-kde-authentication-agent-1
    quickshell
    org.quickshell
    org.pulseaudio.pavucontrol
    com.saivert.pwvucontrol
    yad
    yad-icon-browser
    system-config-printer
    nwg-look
    org.gnome.Settings
    org.gnome.FileRoller
    file-roller
    blueman-manager
    guifetch
    wev
    zenity
    feh
    imv
    swappy
)

# Membership is an exact comparison of one comma-separated entry, the way Krohnkite
# compares a class. A substring or word-boundary match is looser than that: it would
# count my-wev-app as wev, and it would let org.quickshell stand in for the bare
# quickshell the list needs.
has_ignore_class() {
    local entry
    while IFS= read -r entry; do
        # Spaces are dropped first: a hand-edited list may carry them around a comma,
        # and no window class contains one.
        if [[ "${entry//[[:space:]]/}" == "$2" ]]; then
            return 0
        fi
    done < <(printf '%s\n' "$1" | tr ',' '\n')
    return 1
}

# The default, and any list the user already customized, gain only the entries they
# are missing. The comparison is exact, so a list holding org.quickshell still gains
# the bare quickshell. The write stays unconditional so a shell start re-asserts it.
IGNORE_CLASS=$(kreadconfig6 --file kwinrc --group Script-krohnkite --key ignoreClass 2>/dev/null)
NEW_IGNORE="$IGNORE_CLASS"
for class in "${IGNORE_CLASSES[@]}"; do
    if ! has_ignore_class "$NEW_IGNORE" "$class"; then
        NEW_IGNORE="${NEW_IGNORE:+$NEW_IGNORE,}$class"
    fi
done
kwriteconfig6 --file kwinrc --group Script-krohnkite --key ignoreClass "$NEW_IGNORE"

# Set default tiling gaps for Krohnkite
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapBetween 10
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapBottom 4
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapLeft 4
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapRight 4
kwriteconfig6 --file kwinrc --group Script-krohnkite --key screenGapTop 4

# Set binary as the tiling method and disable others to avoid interference
kwriteconfig6 --file kwinrc --group Script-krohnkite --key binaryTreeLayoutOrder 1
kwriteconfig6 --file kwinrc --group Script-krohnkite --key cascadeLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key columnsLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key monocleLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key quarterLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key spiralLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key spreadLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key stackedLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key stairLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key threeColumnLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key tileLayoutOrder 0
kwriteconfig6 --file kwinrc --group Script-krohnkite --key floatingLayoutOrder 2



echo "StartupTasks: Updated Krohnkite exceptions, configured layouts and shortcuts"

# Return 1 to indicate KWin reconfigure is needed
exit 1
