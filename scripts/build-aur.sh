#!/usr/bin/env bash
# Build the AUR apps from packages/aur-packages.txt into the [lunar] repo,
# but only those the Arch repositories don't already provide.
#
#   scripts/build-aur.sh              check all, build what's missing or outdated
#   scripts/build-aur.sh brave-bin    only these
#   scripts/build-aur.sh --yes ...    don't stop to show each PKGBUILD
#
# AUR packages that a listed package needs (depends, makedepends,
# checkdepends) and that Arch's repositories don't have are built first,
# automatically. PGP keys a PKGBUILD lists in validpgpkeys are imported into
# your gpg keyring, so makepkg can check the source signatures.
#
# AUR PKGBUILDs are written by strangers and run code on your machine during
# the build. Without --yes the script shows each PKGBUILD (and its diff since
# the last build) and asks before building.

. "$(dirname "$0")/common.sh"
need git git
need gnupg gpg
need fakeroot fakeroot
need devtools makechrootpkg

yes=0
wanted=()
for arg in "$@"; do
    case "$arg" in
        --yes|-y) yes=1 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $arg" ;;
        *) wanted+=("$arg") ;;
    esac
done
if [[ ${#wanted[@]} -eq 0 ]]; then
    mapfile -t wanted < <(sed -e 's/#.*//' -e '/^\s*$/d' "$LUNAR_ROOT/packages/aur-packages.txt")
fi

export PACKAGER="$LUNAR_PACKAGER"
ensure_chroot

# Sync a private copy of the Arch databases (no root needed)
SYNC_DB="$BUILD_DIR/syncdb"
OFFICIAL_CONF="$BUILD_DIR/official-pacman.conf"
mkdir -p "$SYNC_DB"
write_chroot_conf no "$OFFICIAL_CONF"
msg "Checking the Arch repositories"
fakeroot -- pacman --config "$OFFICIAL_CONF" --dbpath "$SYNC_DB" --logfile /dev/null -Sy >/dev/null

# a package with this name is in Arch's repos
in_official_repos() {
    pacman --config "$OFFICIAL_CONF" --dbpath "$SYNC_DB" -Si "$1" >/dev/null 2>&1
}

# a dependency (name, or something a package provides) can come from Arch's repos
official_satisfies() {
    pacman --config "$OFFICIAL_CONF" --dbpath "$SYNC_DB" --noconfirm \
        -Sp --print-format '%n' "$1" >/dev/null 2>&1
}

AUR_DIR="$BUILD_DIR/aur"
mkdir -p "$AUR_DIR"

# --- .SRCINFO helpers --------------------------------------------------------
srcinfo_field() {   # <file> <field regex>: values, versions stripped, unique
    awk -F' = ' -v f="$2" '$1 ~ "^\t(" f ")$" { print $2 }' "$1" \
        | sed -E 's/[<>=].*//' | sort -u
}
srcinfo_pkgnames() { awk -F' = ' '/^pkgname = / { print $2 }' "$1"; }

# --- fetching -----------------------------------------------------------------
declare -A old_rev=() fetched=()
aur_fetch() {   # <pkgbase>: clone or update; fails if it isn't an AUR package base
    local p="$1" dir="$AUR_DIR/$1"
    [[ -n "${fetched[$p]:-}" ]] && return 0
    if [[ -d "$dir/.git" ]]; then
        old_rev[$p]="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
        git -C "$dir" pull --ff-only -q || warn "$p: git pull failed, using the existing checkout"
    else
        old_rev[$p]=""
        git clone -q "https://aur.archlinux.org/$p.git" "$dir" 2>/dev/null || true
    fi
    [[ -f "$dir/PKGBUILD" && -f "$dir/.SRCINFO" ]] || return 1
    fetched[$p]=1
}

# --- dependency resolution ----------------------------------------------------
# provides[name] = AUR package base that builds or provides it
declare -A provides=() state=() aur_deps=()
order=(); failed=(); skipped=()

register_provides() {   # <pkgbase>
    local p="$1" s="$AUR_DIR/$1/.SRCINFO" n
    while read -r n; do [[ -n "$n" ]] && provides[$n]="$p"; done \
        < <(srcinfo_pkgnames "$s"; srcinfo_field "$s" 'provides')
}

visit() {   # <pkgbase> [needed-by]: queue it after the AUR packages it needs
    local p="$1" by="${2:-}" dep s own
    case "${state[$p]:-}" in
        done) return 0 ;;
        failed) return 1 ;;
        visiting) return 0 ;;   # dependency cycle: the order inside it is left to the PKGBUILDs
    esac
    # Electron from the AUR is a source build of many hours and ~100 GB
    if [[ -n "$by" && "$p" =~ ^electron[0-9]*$ ]]; then
        warn "$by needs $p, which only the AUR has and which would be built from source (hours, ~100 GB). Use a prebuilt (-bin) variant of $by, or another app."
        state[$p]="failed"; return 1
    fi
    state[$p]="visiting"
    if ! aur_fetch "$p"; then
        if [[ -n "$by" ]]; then
            warn "$by needs $p, which is neither in Arch's repos nor an AUR package of that name. Add the AUR package that provides $p to aur-packages.txt above $by."
        else
            warn "$p: not found in the AUR"
        fi
        state[$p]="failed"; return 1
    fi
    register_provides "$p"
    s="$AUR_DIR/$p/.SRCINFO"
    own=" $(srcinfo_pkgnames "$s" | tr '\n' ' ') "
    aur_deps[$p]=""
    while read -r dep; do
        [[ -z "$dep" || "$own" == *" $dep "* ]] && continue
        if [[ -n "${provides[$dep]:-}" ]]; then
            aur_deps[$p]+=" ${provides[$dep]}"
            continue
        fi
        official_satisfies "$dep" && continue
        if visit "$dep" "$p"; then
            aur_deps[$p]+=" ${provides[$dep]:-$dep}"
            msg2 "$p needs $dep from the AUR: building it first"
        else
            state[$p]="failed"; return 1
        fi
    done < <(srcinfo_field "$s" 'depends|makedepends|checkdepends|depends_x86_64|makedepends_x86_64|checkdepends_x86_64')
    state[$p]="done"
    order+=("$p")
}

msg "Resolving AUR dependencies"
for pkg in "${wanted[@]}"; do
    if in_official_repos "$pkg"; then
        msg2 "$pkg: available in the Arch repos, not building"
        skipped+=("$pkg")
        continue
    fi
    visit "$pkg" || failed+=("$pkg")
done

# --- PGP keys for source signatures -------------------------------------------
# makechrootpkg checks source signatures on the host, as you, with your keyring
import_pgp_keys() {   # <pkgbase>
    local p="$1" dir="$AUR_DIR/$1" fpr ks
    while read -r fpr; do
        [[ -z "$fpr" ]] && continue
        gpg --list-keys "$fpr" >/dev/null 2>&1 && continue
        if [[ -f "$dir/keys/pgp/$fpr.asc" ]]; then
            gpg --quiet --import "$dir/keys/pgp/$fpr.asc" 2>/dev/null || true
        fi
        for ks in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org; do
            gpg --list-keys "$fpr" >/dev/null 2>&1 && break
            gpg --quiet --keyserver "$ks" --recv-keys "$fpr" 2>/dev/null || true
        done
        if gpg --list-keys "$fpr" >/dev/null 2>&1; then
            msg2 "$p: imported PGP key $fpr"
        else
            warn "$p: could not get PGP key $fpr (source signature check will fail)"
        fi
    done < <(awk -F' = ' '/^\tvalidpgpkeys = / { print $2 }' "$dir/.SRCINFO" | sort -u)
}

# --- building -----------------------------------------------------------------
built=()
is_in() { local x="$1"; shift; [[ " $* " == *" $x "* ]]; }

for pkg in "${order[@]}"; do
    dir="$AUR_DIR/$pkg"
    bad=""
    for d in ${aur_deps[$pkg]}; do
        if is_in "$d" "${failed[@]}"; then bad="$d"; fi
    done
    if [[ -n "$bad" ]]; then
        warn "$pkg: not building, it needs $bad, which failed"
        failed+=("$pkg"); continue
    fi

    ver="$(srcinfo_version "$dir/.SRCINFO")"
    have="$(repo_version "$(srcinfo_pkgname "$dir/.SRCINFO")")"
    if [[ -n "$have" && "$have" == "$ver" ]]; then
        msg2 "$pkg $ver is up to date in the repo"
        continue
    fi

    if [[ $yes -eq 0 ]]; then
        old="${old_rev[$pkg]:-}"
        if [[ -n "$old" && "$old" != "$(git -C "$dir" rev-parse HEAD)" ]]; then
            git -C "$dir" --no-pager diff "$old" HEAD -- PKGBUILD
        else
            ${PAGER:-less} "$dir/PKGBUILD"
        fi
        read -r -p "Build $pkg $ver? [y/N] " answer
        [[ "$answer" == [yY]* ]] || { msg2 "skipped $pkg"; failed+=("$pkg"); continue; }
    fi

    import_pgp_keys "$pkg"

    msg "Building $pkg $ver (AUR)"
    stamp="$BUILD_DIR/.stamp-aur-$pkg"
    touch "$stamp"
    if (cd "$dir" && makechrootpkg -c -u -r "$LUNAR_CHROOT_DIR"); then
        mapfile -t files < <(find "$dir" -maxdepth 1 -name '*.pkg.tar.zst' -newer "$stamp")
        if [[ ${#files[@]} -gt 0 ]]; then
            add_to_repo "${files[@]}"
            rm -f "${files[@]}"
            built+=("$pkg")
        else
            warn "$pkg: no package file produced"
            failed+=("$pkg")
        fi
    else
        warn "$pkg failed to build"
        failed+=("$pkg")
    fi
done

msg "Done"
[[ ${#built[@]} -gt 0 ]] && msg2 "built: ${built[*]}"
[[ ${#skipped[@]} -gt 0 ]] && msg2 "from Arch repos: ${skipped[*]}"
if [[ ${#failed[@]} -gt 0 ]]; then
    warn "failed or skipped: ${failed[*]}"
    exit 1
fi
