#!/usr/bin/env bash
# Build the Lunar live/install ISO from the archiso profile in iso/.
#
#   scripts/build-iso.sh          use the local repo (repo/x86_64) if it
#                                 exists, otherwise LUNAR_REPO_URL
#   scripts/build-iso.sh --remote always use LUNAR_REPO_URL
#
# The ISO ends up in iso/out/. The work directory (build/iso-work) is removed
# afterwards unless --keep-work is given.

. "$(dirname "$0")/common.sh"
need archiso mkarchiso
need fakeroot fakeroot

remote=0
keep_work=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote) remote=1 ;;
        --keep-work) keep_work=1 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1" ;;
    esac
    shift
done

profile_src="$LUNAR_ROOT/iso"
[[ -f "$profile_src/profiledef.sh" ]] || die "no archiso profile in $profile_src"

if [[ $remote -eq 0 && -f "$DB_FILE" ]]; then
    server="file://$REPO_DIR"
    msg "Using the local repo: $REPO_DIR"
else
    server="$LUNAR_REPO_URL"
    msg "Using the remote repo: $server"
fi

# pacman must trust the Lunar key to install the signed packages
if [[ -n "$LUNAR_SIGNING_KEY" ]] && ! sudo pacman-key --list-keys "$LUNAR_SIGNING_KEY" >/dev/null 2>&1; then
    msg2 "adding the Lunar signing key to the host keyring"
    sudo pacman-key --add "$LUNAR_ROOT/packages/lunar-keyring/lunar.gpg"
    sudo pacman-key --lsign-key "$LUNAR_SIGNING_KEY"
fi

# build from a copy of the profile, so the repo URL never lands in git
profile="$BUILD_DIR/iso-profile"
work="$BUILD_DIR/iso-work"
mkdir -p "$BUILD_DIR"
sudo rm -rf "$profile"
mkdir -p "$profile"
# without out/ and work/: the ISOs built before are several GB each
find "$profile_src" -mindepth 1 -maxdepth 1 \
    ! -name out ! -name work ! -name README.md ! -name .gitignore \
    -exec cp -a -t "$profile" {} +
sed -i "s|@LUNAR_REPO_SERVER@|$server|" "$profile/pacman.conf"
# Arch's repos with Lunar's mirrors and package cache instead of the host's
# (lunar.conf: LUNAR_ARCH_MIRRORS, LUNAR_PKG_CACHE)
sudo mkdir -p "$LUNAR_PKG_CACHE"
sed -i -e '/^\[core\]$/,$d' -e "s|^\[options\]$|[options]\nCacheDir = $LUNAR_PKG_CACHE|" "$profile/pacman.conf"
arch_repos_conf >> "$profile/pacman.conf"
if [[ -z "$LUNAR_SIGNING_KEY" ]]; then
    warn "no signing key: accepting unsigned [lunar] packages for this test build only"
    sed -i '/^\[lunar\]$/a SigLevel = Optional TrustAll' "$profile/pacman.conf"
fi

# every package of the live system, and every package the installer puts on
# a new system, must exist in Arch's repos or [lunar]
check_db="$BUILD_DIR/iso-syncdb"
mkdir -p "$check_db"
fakeroot -- pacman --config "$profile/pacman.conf" --dbpath "$check_db" --logfile /dev/null -Sy >/dev/null

check_list() {  # <description> <package>...
    local what="$1" missing
    shift
    msg2 "checking $what"
    # pacman exits with an error when a target is missing: that is the case
    # to report, so its exit status must not end the script (pipefail)
    missing="$( { pacman --config "$profile/pacman.conf" --dbpath "$check_db" -Sp --print-format '%n' "$@" 2>&1 >/dev/null || true; } \
        | sed -n 's/^error: target not found: //p')"
    [[ -z "$missing" ]] || die "$what: packages no repo has (build them or remove them):
$missing"
}

yaml_list_items() {  # plain "- name" list items of a Calamares config
    sed -nE 's/^[[:space:]]*-[[:space:]]+([A-Za-z0-9@._+-]+)[[:space:]]*(#.*)?$/\1/p' "$@"
}

mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^\s*$/d' "$profile/packages.x86_64")
check_list "iso/packages.x86_64" "${pkgs[@]}"

cal="$LUNAR_ROOT/packages/lunar-calamares/config/modules"
mapfile -t pkgs < <(yaml_list_items "$cal/pacstrap.conf" "$cal/netinstall.yaml")
pkgs+=(linux-lunar linux-lunar-headers linux-lts linux-lts-headers
       amd-ucode intel-ucode)
check_list "the installer's package selection" "${pkgs[@]}"

msg "Building the ISO (this takes a while)"
sudo rm -rf "$work"
sudo mkarchiso -v -w "$work" -o "$profile_src/out" "$profile"
[[ $keep_work -eq 1 ]] || sudo rm -rf "$work"
sudo chown -R "$(id -u):$(id -g)" "$profile_src/out"
msg "ISO in $profile_src/out/"
