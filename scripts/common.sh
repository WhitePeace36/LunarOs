#!/usr/bin/env bash
# Shared helpers for the Lunar build scripts. Sourced, not executed.

set -Eeuo pipefail
# With set -e a failing command ends the script; say where, instead of
# stopping without a word
# shellcheck disable=SC2154  # _rc is set inside the trap itself
trap '_rc=$?; printf "\033[1;31m==> ERROR:\033[0m %s line %s: command failed (exit %s): %s\n" "$(basename "${BASH_SOURCE[0]:-$0}")" "$LINENO" "$_rc" "$BASH_COMMAND" >&2' ERR

LUNAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lunar.conf
. "$LUNAR_ROOT/lunar.conf"

REPO_DIR="$LUNAR_ROOT/$LUNAR_REPO_DIR"
BUILD_DIR="$LUNAR_ROOT/build"
CHROOT_CONF="$BUILD_DIR/chroot-pacman.conf"
DB_FILE="$REPO_DIR/$LUNAR_REPO_NAME.db.tar.gz"

msg()  { printf '\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
msg2() { printf '  \033[1;32m->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
    local cmd pkg="$1"; shift
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found - install $pkg (sudo pacman -S $pkg)"
    done
}

# Arch's repos with Lunar's mirrors (LUNAR_ARCH_MIRRORS) as Server lines, so
# nothing depends on the host's mirrorlist
arch_repos_conf() {
    local repo m
    for repo in core extra multilib; do
        printf '[%s]\n' "$repo"
        for m in "${LUNAR_ARCH_MIRRORS[@]}"; do printf 'Server = %s\n' "$m"; done
        printf '\n'
    done
}

# pacman.conf for the clean build chroot: Arch's repos, plus the local
# [lunar] repo once it has packages, so a package can depend on another
# Lunar or AUR package that was built before it (e.g. lunar-calamares needs
# ckbcomp). Mirrors and package cache are Lunar's own (lunar.conf), not the
# host's.
write_chroot_conf() {
    local with_lunar="${1:-yes}" out="${2:-$CHROOT_CONF}"
    mkdir -p "$BUILD_DIR"
    {
        cat <<EOF
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 10
CacheDir    = $LUNAR_PKG_CACHE
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

EOF
        # arch-nspawn (used by makechrootpkg too) mounts every file:// server
        # of the chroot's pacman.conf read-only at the same path, so the
        # local repo is listed by its real path
        if [[ "$with_lunar" == yes && -f "$DB_FILE" ]]; then
            printf '[%s]\nSigLevel = Optional TrustAll\nServer = file://%s\n\n' \
                "$LUNAR_REPO_NAME" "$REPO_DIR"
        fi
        arch_repos_conf
    } > "$out"
}

# Create (or update) the clean chroot used by makechrootpkg.
ensure_chroot() {
    need devtools mkarchroot makechrootpkg arch-nspawn
    local root="$LUNAR_CHROOT_DIR/root"
    sudo mkdir -p "$LUNAR_PKG_CACHE"
    # mkarchroot writes .arch-chroot last; without it the creation failed
    if [[ -d "$root" && ! -f "$root/.arch-chroot" ]]; then
        warn "removing the unfinished build chroot $root"
        if command -v btrfs >/dev/null && sudo btrfs subvolume show "$root" >/dev/null 2>&1; then
            sudo btrfs subvolume delete "$root" >/dev/null
        else
            sudo rm -rf --one-file-system "$root"
        fi
    fi
    if [[ ! -d "$root" ]]; then
        msg "Creating build chroot in $LUNAR_CHROOT_DIR"
        write_chroot_conf no      # the chroot is created without the local repo
        sudo mkdir -p "$LUNAR_CHROOT_DIR"
        sudo mkarchroot -C "$CHROOT_CONF" -c "$LUNAR_PKG_CACHE" "$root" base-devel
    fi
    msg "Updating build chroot"
    write_chroot_conf
    sudo cp "$CHROOT_CONF" "$LUNAR_CHROOT_DIR/root/etc/pacman.conf"
    sudo arch-nspawn "$LUNAR_CHROOT_DIR/root" pacman -Syu --noconfirm
}

# Sign new packages and add them to the repo database.
# GitHub release assets can't contain ':' (epoch), so such files are
# renamed first; pacman downloads by the file name stored in the database.
add_to_repo() {
    local pkg new files=()
    mkdir -p "$REPO_DIR"
    for pkg in "$@"; do
        # GitHub renames release assets with other characters (e.g. the ":" of
        # an epoch) to ".", so the file gets that name before repo-add
        # records it; pacman then asks for the name that exists.
        new="$(basename "$pkg")"
        new="$REPO_DIR/${new//[^A-Za-z0-9._-]/.}"
        cp -f "$pkg" "$new"
        if [[ -n "$LUNAR_SIGNING_KEY" ]]; then
            rm -f "$new.sig"
            gpg --batch --yes --local-user "$LUNAR_SIGNING_KEY" --detach-sign --no-armor "$new"
        fi
        files+=("$new")
    done
    if [[ -n "$LUNAR_SIGNING_KEY" ]]; then
        repo-add --remove --sign --key "$LUNAR_SIGNING_KEY" "$DB_FILE" "${files[@]}"
    else
        warn "LUNAR_SIGNING_KEY is empty - repo is NOT signed (run scripts/make-key.sh)"
        repo-add --remove "$DB_FILE" "${files[@]}"
    fi
    # the first package in the repo: let the chroot see [lunar] from now on
    if [[ -d "$LUNAR_CHROOT_DIR/root" ]] && ! grep -q "^\[$LUNAR_REPO_NAME\]" "$CHROOT_CONF"; then
        write_chroot_conf
        sudo cp "$CHROOT_CONF" "$LUNAR_CHROOT_DIR/root/etc/pacman.conf"
    fi
}

# First package name in a .SRCINFO file (split packages: pkgbase != pkgname)
srcinfo_pkgname() {
    awk -F' = ' '/^pkgname = / { print $2; exit }' "$1"
}

# Version string "epoch:pkgver-pkgrel" from a .SRCINFO file
srcinfo_version() {
    awk -F' = ' '
        /^\tepoch = /  { e = $2 }
        /^\tpkgver = / { v = $2 }
        /^\tpkgrel = / { r = $2 }
        /^pkgname = / && v != "" { exit }
        END { printf "%s%s-%s\n", (e != "" ? e ":" : ""), v, r }
    ' "$1"
}

# Version of a package in the local repo database (empty if not there).
# bsdtar exits with an error when the package isn't in the database, and
# with SIGPIPE when awk stops early; neither may end the calling script
# (set -e with pipefail), so its exit status is ignored.
repo_version() {
    [[ -f "$DB_FILE" ]] || return 0
    { bsdtar -xOf "$DB_FILE" --include="$1-[0-9]*/desc" 2>/dev/null || true; } \
        | awk -v want="$1" '
            /^%NAME%$/    { getline; name = $0 }
            /^%VERSION%$/ { getline; if (name == want) { print; exit } }
        '
    return 0
}
