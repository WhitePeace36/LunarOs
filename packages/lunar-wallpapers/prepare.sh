#!/usr/bin/env bash
# Prepares lunar-wallpapers for scripts/build-packages.sh: copies the PKGBUILD
# and the wallpapers from branding/ (the NN-name.png files) into $1 and prints
# the folder. The wallpapers stay in branding/ only, not twice in the repo.
#
# After adding or changing a wallpaper in branding/, raise pkgrel in the
# PKGBUILD, then
#   scripts/build-packages.sh lunar-wallpapers && scripts/publish.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
branding="$(cd "$here/../../branding" && pwd)"
work="${1:?usage: prepare.sh <work-dir>}"
dst="$work/lunar-wallpapers"

mkdir -p "$dst/wallpapers"
cp "$here/PKGBUILD" "$dst/"
shopt -s nullglob
pngs=("$branding"/[0-9][0-9]-*.png)
[[ ${#pngs[@]} -gt 0 ]] || { echo "  -> lunar-wallpapers: no wallpapers in $branding" >&2; exit 1; }
cp "${pngs[@]}" "$dst/wallpapers/"
echo "  -> lunar-wallpapers: ${#pngs[@]} wallpapers" >&2
echo "$dst"
