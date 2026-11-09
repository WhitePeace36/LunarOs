#!/usr/bin/env bash
# Build the AUR apps from packages/aur-packages.txt into the [lunar] repo,
# but only those the Arch repositories don't already provide.
#
#   scripts/build-aur.sh              check all, build what's missing or outdated
#   scripts/build-aur.sh brave-bin    only these
#   scripts/build-aur.sh --yes ...    don't stop to show each PKGBUILD
#
# AUR PKGBUILDs are written by strangers and run code on your machine during
# the build. Without --yes the script shows each PKGBUILD (and its diff since
# the last build) and asks before building.

. "$(dirname "$0")/common.sh"
need git git
need fakeroot fakeroot
need devtools makechrootpkg

yes=0
wanted=()
for arg in "$@"; do
    case "$arg" in
        --yes|-y) yes=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

in_official_repos() {
    pacman --config "$OFFICIAL_CONF" --dbpath "$SYNC_DB" -Si "$1" >/dev/null 2>&1
}

AUR_DIR="$BUILD_DIR/aur"
mkdir -p "$AUR_DIR"

built=(); skipped=(); failed=()
for pkg in "${wanted[@]}"; do
    if in_official_repos "$pkg"; then
        msg2 "$pkg: available in the Arch repos, not building"
        skipped+=("$pkg")
        continue
    fi

    dir="$AUR_DIR/$pkg"
    if [[ -d "$dir/.git" ]]; then
        old="$(git -C "$dir" rev-parse HEAD)"
        git -C "$dir" pull --ff-only -q
    else
        old=""
        git clone -q "https://aur.archlinux.org/$pkg.git" "$dir"
    fi
    [[ -f "$dir/PKGBUILD" ]] || { warn "$pkg: not found in the AUR"; failed+=("$pkg"); continue; }

    ver="$(srcinfo_version "$dir/.SRCINFO")"
    have="$(repo_version "$(srcinfo_pkgname "$dir/.SRCINFO")")"
    if [[ -n "$have" && "$have" == "$ver" ]]; then
        msg2 "$pkg $ver is up to date in the repo"
        continue
    fi

    if [[ $yes -eq 0 ]]; then
        if [[ -n "$old" && "$old" != "$(git -C "$dir" rev-parse HEAD)" ]]; then
            git -C "$dir" --no-pager diff "$old" HEAD -- PKGBUILD
        else
            ${PAGER:-less} "$dir/PKGBUILD"
        fi
        read -r -p "Build $pkg $ver? [y/N] " answer
        [[ "$answer" == [yY]* ]] || { msg2 "skipped $pkg"; continue; }
    fi

    msg "Building $pkg $ver (AUR)"
    stamp="$BUILD_DIR/.stamp-aur-$pkg"
    touch "$stamp"
    mapfile -t repo_args < <(chroot_repo_args)
    if (cd "$dir" && makechrootpkg -c -u -r "$LUNAR_CHROOT_DIR" "${repo_args[@]}"); then
        mapfile -t files < <(find "$dir" -maxdepth 1 -name '*.pkg.tar.zst' -newer "$stamp")
        if [[ ${#files[@]} -gt 0 ]]; then
            add_to_repo "${files[@]}"
            rm -f "${files[@]}"
            built+=("$pkg")
        else
            failed+=("$pkg")
        fi
    else
        warn "$pkg failed (if it needs another AUR package, add that one to aur-packages.txt above $pkg)"
        failed+=("$pkg")
    fi
done

msg "Done"
[[ ${#built[@]} -gt 0 ]] && msg2 "built: ${built[*]}"
[[ ${#skipped[@]} -gt 0 ]] && msg2 "from Arch repos: ${skipped[*]}"
if [[ ${#failed[@]} -gt 0 ]]; then
    warn "failed: ${failed[*]}"
    exit 1
fi
