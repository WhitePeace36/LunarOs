#!/usr/bin/env bash
# Prepares linux-lunar for scripts/build-packages.sh:
#   1. clones github.com/WhitePeace36/linux-lunar at _commit into $1/linux-lunar
#   2. applies lunar-config-only.patch if the repo doesn't have --config-only yet
#   3. appends lunar-distro.cfg to customization.cfg
#   4. runs ./lunar.sh --config-only (writes .lunar-build.cfg, builds nothing)
#   5. prints the folder, which build-packages.sh then builds with makechrootpkg
#
# To update the kernel: set _version in lunar-distro.cfg and/or _commit
# below, then scripts/build-packages.sh linux-lunar.
set -euo pipefail

_repo="https://github.com/WhitePeace36/linux-lunar.git"
_commit="ccea1762b61b5b412d509ed46978cf4c358094e6"

here="$(cd "$(dirname "$0")" && pwd)"
work="${1:?usage: prepare.sh <work-dir>}"
src="$work/linux-lunar"

log() { echo "  -> linux-lunar: $*" >&2; }

git clone -q "$_repo" "$src" >&2
git -C "$src" checkout -q "$_commit" >&2
log "commit ${_commit:0:12}"

if ! grep -q -- '--config-only' "$src/lunar.sh"; then
    log "applying lunar-config-only.patch"
    patch -d "$src" -Np1 -i "$here/lunar-config-only.patch" >&2
fi

{
    echo
    echo "#### LUNAR DISTRO OVERRIDES (packages/linux-lunar/lunar-distro.cfg) ####"
    cat "$here/lunar-distro.cfg"
} >> "$src/customization.cfg"

# Signed kernel.org tarballs: makepkg checks them against the builder's keyring.
if grep -q '^_pgp_verify="true"' "$here/lunar-distro.cfg"; then
    gpg --batch --locate-keys torvalds@kernel.org gregkh@kernel.org >/dev/null 2>&1 \
        || log "WARNING: could not fetch the kernel.org signing keys"
fi

# A personal ~/.config/linux-lunar.cfg must not leak into the distro build,
# so lunar.sh runs with an empty HOME.
fake_home="$work/home"
mkdir -p "$fake_home"
(cd "$src" && HOME="$fake_home" ./lunar.sh --config-only) >&2

[[ -f "$src/.lunar-build.cfg" ]] || { log "ERROR: lunar.sh wrote no .lunar-build.cfg"; exit 1; }
echo "$src"
