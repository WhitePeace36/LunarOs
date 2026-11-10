#!/usr/bin/env bash
# Prepares lunar-settings for scripts/build-packages.sh: clones
# github.com/WhitePeace36/lunar-settings at _commit into $1 and prints the
# folder. Its own PKGBUILD then builds the lunar-settings package.
#
# To release a settings change: push it to the lunar-settings repo (with a
# raised pkgver or pkgrel in its PKGBUILD), set _commit below, then
#   scripts/build-packages.sh lunar-settings && scripts/publish.sh
#
# _commit="" builds the newest commit of the default branch (for a first test
# only: pin a commit for real builds, so a build can be repeated).
set -euo pipefail

_repo="https://github.com/WhitePeace36/lunar-settings.git"
_commit="fb8b994a120c5adbe2d7352c99dab0f657d6a283"

work="${1:?usage: prepare.sh <work-dir>}"
src="$work/lunar-settings"

git clone -q "$_repo" "$src" >&2
if [[ -n "$_commit" ]]; then
    git -C "$src" checkout -q "$_commit" >&2
    echo "  -> lunar-settings: commit ${_commit:0:12}" >&2
else
    echo "  -> lunar-settings: WARNING: no _commit set, using $(git -C "$src" rev-parse --short=12 HEAD)" >&2
fi
[[ -f "$src/PKGBUILD" ]] || { echo "  -> lunar-settings: no PKGBUILD in the repo" >&2; exit 1; }
echo "$src"
