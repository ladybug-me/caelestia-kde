#!/usr/bin/env bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
pkgdir="$here/caelestia-kde"

for cmd in git makepkg tar sha256sum cargo; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "missing: $cmd" >&2; exit 1; }
done

# shellcheck source=/dev/null
pkgver="$(set +u; . "$pkgdir/PKGBUILD"; printf '%s' "$pkgver")"
[[ -n "$pkgver" ]] || { echo "could not read pkgver from $pkgdir/PKGBUILD" >&2; exit 1; }
# shellcheck source=/dev/null
tui_version="$(set +u; . "$pkgdir/PKGBUILD"; printf '%s' "$_tui_version")"
[[ -n "$tui_version" ]] || { echo "could not read _tui_version from $pkgdir/PKGBUILD" >&2; exit 1; }

stage="${CAELESTIA_AUR_STAGE:-$HOME/.cache/caelestia-aur}"
src="$stage/caelestia-kde-v$pkgver"
tree="$src/caelestia-kde-$pkgver"
artifact="$src/caelestia-kde-v$pkgver.tar.gz"
vendor_artifact="$src/caelestia-vendor-v$tui_version.tar.gz"

if [[ "${1:-}" == "--clean" ]]; then
    shift
    rm -rf "$src"
fi

mkdir -p "$src"

echo "==> staging the tree at $(git -C "$repo" rev-parse --short HEAD)"
rm -rf "$tree"
git clone --quiet --depth 1 --recurse-submodules --shallow-submodules "file://$repo" "$tree"

git -C "$tree" rev-parse HEAD > "$tree/REVISION"

rm -rf "$tree/.git" "$tree/.gitmodules"
find "$tree" -maxdepth 4 -name '.git' -exec rm -rf {} + 2>/dev/null || true

echo "==> building $artifact"
tar -C "$src" -czf "$artifact" "caelestia-kde-$pkgver"

sum="$(sha256sum "$artifact" | cut -d' ' -f1)"

# The installer builds from a vendored crate tree rather than the network, so the
# helper vendors one from this checkout and hands the PKGBUILD its own URL and hash.
echo "==> vendoring the installer's crates"
rm -rf "$src/vendor"
cargo vendor --manifest-path "$repo/installer/Cargo.toml" --locked --versioned-dirs \
    "$src/vendor" > /dev/null
tar -C "$src" -czf "$vendor_artifact" vendor
vendor_sum="$(sha256sum "$vendor_artifact" | cut -d' ' -f1)"
rm -rf "$src/vendor"

{
    printf '_source_url="%s"\n' "$(basename "$artifact")"
    printf '_source_sum="%s"\n' "$sum"
    printf '_vendor_url="%s"\n' "$(basename "$vendor_artifact")"
    printf '_vendor_sum="%s"\n' "$vendor_sum"
    cat "$pkgdir/PKGBUILD"
} > "$src/PKGBUILD"
install -m644 "$pkgdir/caelestia-autostart" "$pkgdir/caelestia-shell.service" "$src/"

echo "==> $(du -h "$artifact" | cut -f1) tarball, sha256 $sum"
echo "==> $(du -h "$vendor_artifact" | cut -f1) vendored crates, sha256 $vendor_sum"
echo "==> makepkg in $src"
cd "$src"
exec makepkg --force "$@"
