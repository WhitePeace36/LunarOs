#!/usr/bin/env bash
# Upload repo/x86_64 to the GitHub release that LUNAR_REPO_URL points at
# (https://github.com/<owner>/<repo>/releases/download/<tag>).
#
#   scripts/publish.sh
#
# Needs the GitHub CLI (github-cli) logged in with `gh auth login`.
# The repo database symlinks (lunar.db, lunar.files) are uploaded as real
# files, since release assets can't be symlinks.

. "$(dirname "$0")/common.sh"
need github-cli gh

[[ "$LUNAR_REPO_URL" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/?$ ]] \
    || die "LUNAR_REPO_URL is not a GitHub release URL: $LUNAR_REPO_URL"
gh_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
tag="${BASH_REMATCH[3]}"

[[ -f "$DB_FILE" ]] || die "no repo database at $DB_FILE - build packages first"

if ! gh release view "$tag" -R "$gh_repo" >/dev/null 2>&1; then
    msg "Creating release $tag in $gh_repo"
    gh release create "$tag" -R "$gh_repo" --title "Lunar repository ($tag)" \
        --notes "pacman repository for Lunar. Server = $LUNAR_REPO_URL"
fi

stage="$BUILD_DIR/publish"
rm -rf "$stage"; mkdir -p "$stage"
cp -L "$REPO_DIR"/* "$stage/"
rm -f "$stage"/*.old    # repo-add's backups of the previous database

mapfile -t current < <(cd "$stage" && ls -1)

# name, size and (where GitHub reports one) sha256 digest of every asset
published=()
declare -A pub_size=() pub_digest=()
while IFS=$'\t' read -r name size digest; do
    [[ -n "$name" ]] || continue
    published+=("$name")
    pub_size[$name]="$size"
    pub_digest[$name]="${digest:-}"
done < <(gh release view "$tag" -R "$gh_repo" --json assets \
            --jq '.assets[] | [.name, (.size | tostring), (.digest // "")] | @tsv')

# The asset exists with the same content. A package that was built again
# under the same version (--force, or a build on another machine) has the
# same name but other contents, and the database lists the new checksum and
# signature: it must be uploaded again, or pacman rejects the download.
is_published() {
    local f="$1"
    [[ -n "${pub_size[$f]:-}" ]] || return 1
    if [[ "${pub_digest[$f]}" == sha256:* ]]; then
        [[ "sha256:$(sha256sum "$stage/$f" | cut -d' ' -f1)" == "${pub_digest[$f]}" ]]
    else
        [[ "$(stat -c %s "$stage/$f")" == "${pub_size[$f]}" ]]
    fi
}

# Only new or changed package files are uploaded. The database files change
# with every build and always are.
uploads=()
for f in "${current[@]}"; do
    case "$f" in
        "$LUNAR_REPO_NAME".db|"$LUNAR_REPO_NAME".db.*|"$LUNAR_REPO_NAME".files|"$LUNAR_REPO_NAME".files.*)
            uploads+=("$stage/$f") ;;
        *) is_published "$f" || uploads+=("$stage/$f") ;;
    esac
done
msg "Uploading ${#uploads[@]} of ${#current[@]} files to $gh_repo ($tag)"
gh release upload "$tag" -R "$gh_repo" --clobber "${uploads[@]}"

# drop assets that are no longer in the repo (old package versions)
for asset in "${published[@]}"; do
    [[ " ${current[*]} " == *" $asset "* ]] && continue
    msg2 "deleting old asset $asset"
    gh release delete-asset "$tag" "$asset" -R "$gh_repo" -y
done

msg "Published: $LUNAR_REPO_URL"
