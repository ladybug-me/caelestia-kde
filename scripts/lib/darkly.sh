#!/usr/bin/env bash
# The Darkly GTK theme, which upstream ships as a build script rather than a package -
# that is why it is not with the package helpers. Callers source log.sh first: err is
# how a failed install reports itself.
if [[ -z "${CAELESTIA_DARKLY_SOURCED:-}" ]]; then
CAELESTIA_DARKLY_SOURCED=1

# The commit the theme is built from. Its install script runs here and writes the theme
# directories the desktop then loads, so the tree is this project's choice rather than
# whatever the default branch holds on the day the installer runs. Upstream publishes no
# tags and no releases, so a commit is the only pin it offers, and GitHub serves a shallow
# fetch of one - which is why this is not a `clone --branch`, as that needs a ref name.
DARKLY_GTK_COMMIT="3de7ec457dd3855e32a9760910f4f4430679eb98"

# Upstream's install.sh only drops theme directories - it is not a package, so the
# directories are the whole answer.
darkly_gtk_installed() {
    [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/themes/Darkly" ]] ||
    [[ -d "$HOME/.themes/Darkly" ]] ||
    [[ -d "/usr/share/themes/Darkly" ]]
}

# Clones and builds the theme. Returns non-zero when it did not land, so the caller can
# record the failure next to its own. The sassc build dependency is the caller's
# business: each distro asks for it the way it asks for everything else.
install_darkly_gtk_theme() {
    local tmpdir status=0
    tmpdir="$(mktemp -d)"

    if git -C "$tmpdir" init -q &&
        git -C "$tmpdir" remote add origin https://github.com/wrymt/darkly-gtk &&
        git -C "$tmpdir" fetch --depth 1 origin "$DARKLY_GTK_COMMIT" &&
        git -C "$tmpdir" checkout -q FETCH_HEAD; then
        (cd "$tmpdir" || exit 1; ./install.sh -l) || {
            err "Failed to install Darkly GTK theme."
            status=1
        }
    else
        err "Failed to clone Darkly GTK theme."
        status=1
    fi

    rm -rf "$tmpdir"
    return "$status"
}

fi
