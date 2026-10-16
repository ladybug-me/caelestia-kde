#!/usr/bin/env bash
if [[ -z "${CAELESTIA_INSTALLER_BIN_SOURCED:-}" ]]; then
CAELESTIA_INSTALLER_BIN_SOURCED=1

caelestia_bundle_dir() {
    local bundle="${BUNDLE_DIR:-}"
    if [[ -z "$bundle" ]]; then
        bundle="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || return 1
    fi
    [[ -n "$bundle" ]] || return 1
    printf '%s\n' "$bundle"
}

caelestia_installer_version() {
    local bundle version
    bundle="$(caelestia_bundle_dir)" || return 1
    version="$(tr -d '[:space:]' < "$bundle/installer/data/tui.version" 2>/dev/null || true)"
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

caelestia_release_tag() {
    local bundle tag
    bundle="$(caelestia_bundle_dir)" || return 1
    tag="$(sed -nE 's/^[[:space:]]*VERSION=//p' "$bundle/.github/version.env" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$tag" ]] || return 1
    printf '%s\n' "$tag"
}

caelestia_installer_url() {
    local arch version tag
    arch="$(uname -m)"
    case "$arch" in
        x86_64 | aarch64) ;;
        *) return 1 ;;
    esac

    version="$(caelestia_installer_version)" || return 1
    tag="$(caelestia_release_tag)" || return 1

    printf 'https://github.com/ladybug-me/caelestia-kde/releases/download/%s/caelestia-install-%s-v%s\n' \
        "$tag" "$arch" "$version"
}

caelestia_cached_installer() {
    local version
    version="$(caelestia_installer_version)" || return 1
    printf '%s\n' "${XDG_CACHE_HOME:-${HOME:-}/.cache}/caelestia/caelestia-install-v${version}"
}

caelestia_prune_cached_installers() {
    local keep="$1" stale
    for stale in "$(dirname -- "$keep")"/caelestia-install-v*; do
        [[ -e "$stale" ]] || continue
        [[ "$stale" == "$keep" ]] && continue
        rm -f "$stale"
    done
}

caelestia_fetch_installer() {
    local bin url sidecar expected actual
    bin="$(caelestia_cached_installer)" || return 1
    if [[ -x "$bin" ]]; then
        printf '%s\n' "$bin"
        return 0
    fi

    url="$(caelestia_installer_url)" || return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1

    mkdir -p "$(dirname -- "$bin")" || return 1
    rm -f "$bin.part"
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$bin.part" 2>/dev/null; then
        rm -f "$bin.part"
        return 1
    fi

    sidecar="$(mktemp)" || { rm -f "$bin.part"; return 1; }
    if ! curl -fsSL --connect-timeout 10 "$url.sha256" -o "$sidecar" 2>/dev/null; then
        rm -f "$sidecar" "$bin.part"
        return 1
    fi
    expected="$(cut -d' ' -f1 < "$sidecar" | tr -d '[:space:]')"
    rm -f "$sidecar"

    actual="$(sha256sum "$bin.part" | cut -d' ' -f1)"
    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        printf '[ERR]   the downloaded installer failed its checksum\n' >&2
        rm -f "$bin.part"
        return 1
    fi

    chmod +x "$bin.part" || { rm -f "$bin.part"; return 1; }
    mv -f "$bin.part" "$bin" || { rm -f "$bin.part"; return 1; }
    caelestia_prune_cached_installers "$bin"
    printf '%s\n' "$bin"
}

caelestia_installer_bin() {
    if [[ -n "${CAELESTIA_INSTALL_BIN:-}" && -x "${CAELESTIA_INSTALL_BIN}" ]]; then
        printf '%s\n' "$CAELESTIA_INSTALL_BIN"
        return 0
    fi

    local bundle candidate
    if bundle="$(caelestia_bundle_dir)"; then
        for candidate in \
            "$bundle/caelestia-install" \
            "$bundle/installer/target/release/caelestia-install" \
            "$bundle/installer/target/debug/caelestia-install"; do
            if [[ -x "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    fi

    for candidate in \
        /usr/bin/caelestia-install \
        /usr/lib/caelestia/caelestia-install; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if [[ "${CAELESTIA_NO_INSTALLER_FETCH:-0}" == "1" ]]; then
        return 1
    fi
    caelestia_fetch_installer
}

caelestia_run_step() {
    local id="$1"
    shift
    local bundle="${BUNDLE_DIR:-}"
    local bin

    if ! bin="$(caelestia_installer_bin)"; then
        printf '[ERR]   cannot run the %s step: no installer binary to run it with\n' "$id" >&2
        return 127
    fi

    if [[ -n "$bundle" ]]; then
        "$bin" step "$id" --bundle "$bundle" "$@"
    else
        "$bin" step "$id" "$@"
    fi
}

fi
