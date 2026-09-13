#!/usr/bin/env bash
# Build the AUR package from a checkout, before the release it names exists.
#
# The PKGBUILD sources a tarball that the release job attaches
# (version-release.yml, job build-source), which does not exist until a tag is pushed -
# so a plain `makepkg -si` cannot work first. This builds the same tarball locally and
# stages a copy of the PKGBUILD with _source_url/_source_sum pointing at it. Everything
# else, compile included, is the real package build: this is how a release is tested.
#
#   packaging/aur/makepkg-from-checkout.sh          # build the package
#   packaging/aur/makepkg-from-checkout.sh -si      # build and install it
#   packaging/aur/makepkg-from-checkout.sh --clean  # rebuild from scratch
#
# Staged in $CAELESTIA_AUR_STAGE (default ~/.cache/caelestia-aur), not /tmp: makepkg builds
# the whole shell there and a tmpfs is usually too small.

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
# A fresh clone, not the working tree: untracked build output cannot leak into the
# package, and submodules arrive at the pinned commits even where never initialized.
rm -rf "$tree"
git clone --quiet --depth 1 --recurse-submodules --shallow-submodules "file://$repo" "$tree"

# Fonts are not built in: the install fetches them into the user's own asset directory
# (12-fetch-assets.sh), which is why the release tarball drops them too.
rm -rf "$tree/shell/assets/fonts"

# shell/CMakeLists.txt reads this before falling back to git, so a tree without .git can
# still report the commit.
git -C "$tree" rev-parse HEAD > "$tree/REVISION"

# A source tree, not a repository: no .git (including the submodules' .git files) and no
# .gitmodules, which inlined submodules make meaningless.
rm -rf "$tree/.git" "$tree/.gitmodules"
find "$tree" -maxdepth 4 -name '.git' -exec rm -rf {} + 2>/dev/null || true

echo "==> building $artifact"
tar -C "$src" -czf "$artifact" "caelestia-kde-$pkgver"

sum="$(sha256sum "$artifact" | cut -d' ' -f1)"

# The staged PKGBUILD is the real one with two variables set ahead of it; see the comment
# above source= in the real file.
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
