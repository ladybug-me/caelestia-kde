#!/usr/bin/env bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
pkgdir="$here/caelestia-kde"

for cmd in git makepkg tar sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "missing: $cmd" >&2; exit 1; }
done

# shellcheck source=/dev/null
pkgver="$(set +u; . "$pkgdir/PKGBUILD"; printf '%s' "$pkgver")"
[[ -n "$pkgver" ]] || { echo "could not read pkgver from $pkgdir/PKGBUILD" >&2; exit 1; }

stage="${CAELESTIA_AUR_STAGE:-$HOME/.cache/caelestia-aur}"
src="$stage/caelestia-kde-v$pkgver"
tree="$src/caelestia-kde-$pkgver"
artifact="$src/caelestia-kde-v$pkgver.tar.gz"

if [[ "${1:-}" == "--clean" ]]; then
    shift
    rm -rf "$src"
fi

mkdir -p "$src"

echo "==> staging the tree at $(git -C "$repo" rev-parse --short HEAD)"
rm -rf "$tree"
git clone --quiet --depth 1 --recurse-submodules --shallow-submodules "file://$repo" "$tree"

rm -rf "$tree/shell/assets/fonts"

git -C "$tree" rev-parse HEAD > "$tree/REVISION"

rm -rf "$tree/.git" "$tree/.gitmodules"
find "$tree" -maxdepth 4 -name '.git' -exec rm -rf {} + 2>/dev/null || true

echo "==> building $artifact"
tar -C "$src" -czf "$artifact" "caelestia-kde-$pkgver"

sum="$(sha256sum "$artifact" | cut -d' ' -f1)"

{
    printf '_source_url="%s"\n' "$(basename "$artifact")"
    printf '_source_sum="%s"\n' "$sum"
    cat "$pkgdir/PKGBUILD"
} > "$src/PKGBUILD"
install -m644 "$pkgdir/caelestia-autostart" "$pkgdir/caelestia-shell.service" "$src/"

echo "==> $(du -h "$artifact" | cut -f1) tarball, sha256 $sum"
echo "==> makepkg in $src"
cd "$src"
exec makepkg --force "$@"
