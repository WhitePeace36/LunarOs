#!/usr/bin/env bash
# Prepares linux-lunar for scripts/build-packages.sh:
#   1. clones github.com/WhitePeace36/linux-lunar at _commit into $1/linux-lunar
#   2. applies lunar-config-only.patch if the repo doesn't have --config-only yet
#   3. appends lunar-distro.cfg to customization.cfg, then the variant file
#      given as $2 if any (packages/linux-lunar-v3/prepare.sh passes its own)
#   4. runs ./lunar.sh --config-only (writes .lunar-build.cfg, builds nothing)
#   5. prints the folder, which build-packages.sh then builds with makechrootpkg
#
# To update the kernels: set _version in lunar-distro.cfg and in
# packages/linux-lunar-v3/lunar-distro.cfg (prepare.sh stops when they
# differ) and/or _commit below, then
# scripts/build-packages.sh linux-lunar linux-lunar-v3.
set -euo pipefail

_repo="https://github.com/WhitePeace36/linux-lunar.git"
_commit="4ab149f3f9dbe34b6b5cfc62109ff665ab30769a"

here="$(cd "$(dirname "$0")" && pwd)"
work="${1:?usage: prepare.sh <work-dir> [variant.cfg]}"
variant="${2:-}"
src="$work/linux-lunar"

log() { echo "  -> linux-lunar: $*" >&2; }

[[ -z "$variant" || -f "$variant" ]] || { log "ERROR: no such file: $variant"; exit 1; }

# The variant file repeats _version and, appended last, wins: both builds
# must be the same release, so a bump that missed one of the files stops here
cfg_version() { sed -n 's/^_version="\(.*\)"$/\1/p' "$1" | tail -n1; }
if [[ -n "$variant" ]]; then
    base_version="$(cfg_version "$here/lunar-distro.cfg")"
    variant_version="$(cfg_version "$variant")"
    if [[ -n "$variant_version" && "$variant_version" != "$base_version" ]]; then
        log "ERROR: _version is $base_version in packages/linux-lunar/lunar-distro.cfg but $variant_version in $(basename "$(dirname "$variant")")/$(basename "$variant"); set the same release in both"
        exit 1
    fi
fi

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
    if [[ -n "$variant" ]]; then
        echo
        echo "#### VARIANT OVERRIDES ($(basename "$(dirname "$variant")")/$(basename "$variant")) ####"
        cat "$variant"
    fi
} >> "$src/customization.cfg"
log "package linux-$(sed -n 's/^_pkgsuffix="\(.*\)"$/\1/p' "$src/customization.cfg" | tail -n1)"

# Signed kernel.org tarballs: makepkg checks them against the builder's keyring.
# (the last _pgp_verify in customization.cfg wins, as in lunar.sh)
if [[ "$(sed -n 's/^_pgp_verify="\(.*\)"$/\1/p' "$src/customization.cfg" | tail -n1)" == true ]]; then
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
