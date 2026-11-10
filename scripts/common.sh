#!/usr/bin/env bash
# Shared helpers for the Lunar build scripts. Sourced, not executed.

set -euo pipefail

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

# Where the local [lunar] repo appears inside the build chroot
CHROOT_REPO_MOUNT="/lunar-repo"

# pacman.conf for the clean build chroot: Arch's repos, plus the local
# [lunar] repo once it has packages, so a package can depend on another
# Lunar or AUR package that was built before it (e.g. lunar-calamares needs
# ckbcomp). The chroot gets a copy of the host's /etc/pacman.d/mirrorlist.
write_chroot_conf() {
    local with_lunar="${1:-yes}" out="${2:-$CHROOT_CONF}"
    mkdir -p "$BUILD_DIR"
    {
        cat <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 10
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

EOF
        if [[ "$with_lunar" == yes && -f "$DB_FILE" ]]; then
            printf '[%s]\nSigLevel = Optional TrustAll\nServer = file://%s\n\n' \
                "$LUNAR_REPO_NAME" "$CHROOT_REPO_MOUNT"
        fi
        cat <<'EOF'
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    } > "$out"
}

# makechrootpkg arguments that make the local repo visible in the chroot
chroot_repo_args() {
    [[ -f "$DB_FILE" ]] && printf '%s\n' -D "$REPO_DIR:$CHROOT_REPO_MOUNT"
    return 0
}

# Create (or update) the clean chroot used by makechrootpkg.
ensure_chroot() {
    need devtools mkarchroot makechrootpkg arch-nspawn
    if [[ ! -d "$LUNAR_CHROOT_DIR/root" ]]; then
        msg "Creating build chroot in $LUNAR_CHROOT_DIR"
        write_chroot_conf no      # the host can't see /lunar-repo yet
        sudo mkdir -p "$LUNAR_CHROOT_DIR"
        sudo mkarchroot -C "$CHROOT_CONF" "$LUNAR_CHROOT_DIR/root" base-devel
    fi
    msg "Updating build chroot"
    write_chroot_conf
    sudo cp "$CHROOT_CONF" "$LUNAR_CHROOT_DIR/root/etc/pacman.conf"
    if [[ -f "$DB_FILE" ]]; then
        sudo arch-nspawn "$LUNAR_CHROOT_DIR/root" --bind-ro="$REPO_DIR:$CHROOT_REPO_MOUNT" pacman -Syu --noconfirm
    else
        sudo arch-nspawn "$LUNAR_CHROOT_DIR/root" pacman -Syu --noconfirm
    fi
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

# Version of a package in the local repo database (empty if not there)
repo_version() {
    [[ -f "$DB_FILE" ]] || return 0
    bsdtar -xOf "$DB_FILE" --include="$1-[0-9]*/desc" 2>/dev/null \
        | awk -v want="$1" '
            /^%NAME%$/    { getline; name = $0 }
            /^%VERSION%$/ { getline; if (name == want) { print; exit } }
        '
}
