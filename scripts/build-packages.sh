#!/usr/bin/env bash
# Build Lunar's own packages (everything in packages/ with a PKGBUILD) in a
# clean chroot, sign them and add them to the local repo in repo/x86_64.
#
#   scripts/build-packages.sh               build what changed
#   scripts/build-packages.sh elara         build only these packages
#   scripts/build-packages.sh --force ...   rebuild even if the version is in the repo
#
# A package folder may hold an executable prepare.sh instead of building its
# PKGBUILD directly (linux-lunar does): it gets an empty work folder as $1,
# prepares the real build folder there and prints its path; that folder is
# then built like any other.
#
# Needs: devtools. Run on an Arch (or Arch-based) host.

. "$(dirname "$0")/common.sh"
need devtools makechrootpkg
need pacman repo-add makepkg bsdtar

force=0
wanted=()
for arg in "$@"; do
    case "$arg" in
        --force|-f) force=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $arg" ;;
        *) wanted+=("$arg") ;;
    esac
done

if [[ ${#wanted[@]} -eq 0 ]]; then
    mapfile -t wanted < <(sed -e 's/#.*//' -e '/^\s*$/d' "$LUNAR_ROOT/packages/build-order.txt")
    for d in "$LUNAR_ROOT"/packages/*/; do
        n="$(basename "$d")"
        [[ -f "$d/PKGBUILD" || -x "$d/prepare.sh" ]] || continue
        [[ " ${wanted[*]} " == *" $n "* ]] || wanted+=("$n")
    done
fi

# packages/lunar-mirrorlist: Server line from lunar.conf
sed -i "s|^Server = .*|Server = $LUNAR_REPO_URL|" "$LUNAR_ROOT/packages/lunar-mirrorlist/lunar-mirrorlist"

# packages/lunar-keyring needs the key files from make-key.sh
if [[ " ${wanted[*]} " == *" lunar-keyring "* ]] && [[ ! -s "$LUNAR_ROOT/packages/lunar-keyring/lunar.gpg" ]]; then
    die "packages/lunar-keyring/lunar.gpg missing - run scripts/make-key.sh first"
fi

export PACKAGER="$LUNAR_PACKAGER"
ensure_chroot
remove_debug_packages

built=()
failed=()
for name in "${wanted[@]}"; do
    dir="$LUNAR_ROOT/packages/$name"
    if [[ -x "$dir/prepare.sh" ]]; then
        msg "Preparing $name"
        work="$BUILD_DIR/work/$name"
        rm -rf "$work"; mkdir -p "$work"
        dir="$("$dir/prepare.sh" "$work" | tail -n1)" || { warn "$name: prepare.sh failed"; failed+=("$name"); continue; }
    fi
    [[ -f "$dir/PKGBUILD" ]] || die "no PKGBUILD for $name (looked in $dir)"

    srcinfo="$BUILD_DIR/$name.SRCINFO"
    (cd "$dir" && makepkg --printsrcinfo > "$srcinfo")
    ver="$(srcinfo_version "$srcinfo")"
    have="$(repo_version "$(srcinfo_pkgname "$srcinfo")")"
    if [[ $force -eq 0 && -n "$have" && "$have" == "$ver" ]]; then
        msg2 "$name $ver is already in the repo, skipping (use --force to rebuild)"
        continue
    fi

    msg "Building $name $ver"
    stamp="$BUILD_DIR/.stamp-$name"
    touch "$stamp"
    if (cd "$dir" && makechrootpkg -c -u -r "$LUNAR_CHROOT_DIR"); then
        mapfile -t pkgs < <(new_packages "$dir" "$stamp")
        [[ ${#pkgs[@]} -gt 0 ]] || { warn "$name: no package file produced"; failed+=("$name"); continue; }
        add_to_repo "${pkgs[@]}"
        rm -f "${pkgs[@]}"
        built+=("$name")
    else
        warn "$name failed to build"
        failed+=("$name")
    fi
done

msg "Done"
[[ ${#built[@]} -gt 0 ]] && msg2 "built: ${built[*]}"
if [[ ${#failed[@]} -gt 0 ]]; then
    warn "failed: ${failed[*]}"
    exit 1
fi
msg2 "repo: $REPO_DIR"
