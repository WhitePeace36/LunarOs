#!/usr/bin/env bash
# Prepares lunar-settings for scripts/build-packages.sh: clones
# github.com/WhitePeace36/lunar-settings at the release tag _tag into $1 and
# prints the folder. Its own PKGBUILD then builds the lunar-settings package.
#
# To release a settings change: raise pkgver in the lunar-settings repo's
# PKGBUILD, commit, tag the commit v<pkgver> and push it with the tag; set
# _tag below, then
#   scripts/build-packages.sh lunar-settings && scripts/publish.sh
set -euo pipefail

_repo="https://github.com/WhitePeace36/lunar-settings.git"
_tag="v2.0.3"

work="${1:?usage: prepare.sh <work-dir>}"
src="$work/lunar-settings"

git -c advice.detachedHead=false clone -q --branch "$_tag" "$_repo" "$src" >&2
echo "  -> lunar-settings: $_tag ($(git -C "$src" rev-parse --short=12 HEAD))" >&2
[[ -f "$src/PKGBUILD" ]] || { echo "  -> lunar-settings: no PKGBUILD in the repo" >&2; exit 1; }
want="${_tag#v}"
have="$(sed -n 's/^pkgver=//p' "$src/PKGBUILD")"
[[ "$have" == "$want" ]] || {
    echo "  -> lunar-settings: tag $_tag but pkgver=$have in its PKGBUILD" >&2; exit 1; }
echo "$src"
