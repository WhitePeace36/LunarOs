#!/usr/bin/env bash
# Upload repo/x86_64 to every server of the [lunar] repository: LUNAR_REPO_URL
# and the mirrors in LUNAR_REPO_MIRRORS (lunar.conf). Two kinds of server:
#
#   GitHub release    https://github.com/<owner>/<repo>/releases/download/<tag>
#                     needs the GitHub CLI (github-cli), `gh auth login`
#   GitLab generic    https://gitlab.com/api/v4/projects/<owner>%2F<repo>/packages/generic/<name>/<version>
#   package registry  needs curl and jq, and a GitLab access token with the
#                     "api" scope (Maintainer role or higher) in GITLAB_TOKEN,
#                     or glab (`glab auth login`)
#
#   scripts/publish.sh            all servers
#   scripts/publish.sh gitlab     only servers whose URL contains "gitlab"
#                                 (any part of the URL works: github, ...)
#
# Each server gets the new or changed package files first and the database
# after them, so a client never sees a database that lists packages the
# server doesn't have yet. Then old package versions are deleted, except the
# previous version of each package: an install or update that downloaded
# the database before this upload still asks for that one, and it would fail
# if the file were gone. Example: the server has 1.3 and 1.4.2, 1.4.3 is
# published: 1.4.2 stays, 1.3 is deleted. Packages taken out of the repo are
# deleted completely. The repo database symlinks (lunar.db, lunar.files) are
# uploaded as real files, since neither server has symlinks.
# A server that fails doesn't stop the others; the script then exits with 1.

. "$(dirname "$0")/common.sh"

filters=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $arg" ;;
        *) filters+=("$arg") ;;
    esac
done

[[ -f "$DB_FILE" ]] || die "no repo database at $DB_FILE - build packages first"
need pacman vercmp

targets=()
while read -r url; do
    if [[ ${#filters[@]} -gt 0 ]]; then
        hit=0
        for f in "${filters[@]}"; do [[ "$url" == *"$f"* ]] && hit=1; done
        [[ $hit -eq 1 ]] || continue
    fi
    targets+=("$url")
done < <(lunar_servers)
[[ ${#targets[@]} -gt 0 ]] || die "no server in lunar.conf matches: ${filters[*]}"

stage="$BUILD_DIR/publish"
rm -rf "$stage"; mkdir -p "$stage"
cp -L "$REPO_DIR"/* "$stage/"
rm -f "$stage"/*.old "$stage"/*.old.sig    # repo-add's backups of the previous database

mapfile -t current < <(cd "$stage" && ls -1)

is_db() {
    case "$1" in
        "$LUNAR_REPO_NAME".db|"$LUNAR_REPO_NAME".db.*|"$LUNAR_REPO_NAME".files|"$LUNAR_REPO_NAME".files.*) return 0 ;;
    esac
    return 1
}

in_current() { [[ " ${current[*]} " == *" $1 "* ]]; }

# Splits a package file name (<name>-<pkgver>-<pkgrel>-<arch>.pkg.tar.zst)
# into pkg_name and pkg_ver (<pkgver>-<pkgrel>). Fails for other files.
pkg_split() {
    [[ "$1" =~ ^(.+)-([^-]+-[^-]+)-[^-]+\.pkg\.tar\.zst$ ]] || return 1
    pkg_name="${BASH_REMATCH[1]}"
    pkg_ver="${BASH_REMATCH[2]}"
}

# Fills keep_prev with the previous version of every package that is still
# in the repo: of the files on the server (the arguments) that are older than
# the current version, the newest one, and its signature.
declare -A keep_prev=()
select_previous() {  # <file on the server>...
    local f name
    local -A cur_ver=() prev_ver=() prev_file=()
    for f in "${current[@]}"; do
        pkg_split "$f" || continue
        cur_ver[$pkg_name]="$pkg_ver"
    done
    for f in "$@"; do
        in_current "$f" && continue
        pkg_split "$f" || continue
        [[ -n "${cur_ver[$pkg_name]:-}" ]] || continue    # taken out of the repo
        [[ "$(vercmp "$pkg_ver" "${cur_ver[$pkg_name]}")" -lt 0 ]] || continue
        if [[ -z "${prev_ver[$pkg_name]:-}" ]] \
                || [[ "$(vercmp "$pkg_ver" "${prev_ver[$pkg_name]}")" -gt 0 ]]; then
            prev_ver[$pkg_name]="$pkg_ver"
            prev_file[$pkg_name]="$f"
        fi
    done
    keep_prev=()
    for name in "${!prev_file[@]}"; do
        keep_prev[${prev_file[$name]}]=1
        keep_prev[${prev_file[$name]}.sig]=1
    done
}

# The file stays on the server: it's in the repo, or it's a previous version
keep_file() { in_current "$1" || [[ -n "${keep_prev[$1]:-}" ]]; }

# Filled by each server before select_uploads: size and (where the server
# reports one) sha256 of every file it has.
declare -A pub_size=() pub_sha256=()

# The server has the file with the same content. A package that was built
# again under the same version (--force, or a build on another machine) has
# the same name but other contents, and the database lists the new checksum
# and signature: it must be uploaded again, or pacman rejects the download.
is_published() {
    local f="$1"
    [[ -n "${pub_size[$f]:-}" ]] || return 1
    if [[ -n "${pub_sha256[$f]:-}" ]]; then
        [[ "$(sha256sum "$stage/$f" | cut -d' ' -f1)" == "${pub_sha256[$f]}" ]]
    else
        [[ "$(stat -c %s "$stage/$f")" == "${pub_size[$f]}" ]]
    fi
}

# Fills pkg_uploads (new or changed package files) and db_uploads (the
# database files: they change with every build and are always uploaded).
select_uploads() {
    local f
    pkg_uploads=(); db_uploads=()
    for f in "${current[@]}"; do
        if is_db "$f"; then
            db_uploads+=("$f")
        elif ! is_published "$f"; then
            pkg_uploads+=("$f")
        fi
    done
    msg2 "uploading ${#pkg_uploads[@]} of $(( ${#current[@]} - ${#db_uploads[@]} )) package files, and the database"
}

# --- GitHub release -------------------------------------------------------------
publish_github() {
    local url="$1" gh_repo tag name size digest asset
    need github-cli gh
    [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/?$ ]] \
        || die "not a GitHub release URL: $url"
    gh_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    tag="${BASH_REMATCH[3]}"

    if ! gh release view "$tag" -R "$gh_repo" >/dev/null 2>&1; then
        msg2 "creating release $tag in $gh_repo"
        gh release create "$tag" -R "$gh_repo" --title "Lunar repository ($tag)" \
            --notes "pacman repository for Lunar. Server = $url"
    fi

    local published=()
    while IFS=$'\t' read -r name size digest; do
        [[ -n "$name" ]] || continue
        published+=("$name")
        pub_size[$name]="$size"
        [[ "$digest" == sha256:* ]] && pub_sha256[$name]="${digest#sha256:}"
    done < <(gh release view "$tag" -R "$gh_repo" --json assets \
                --jq '.assets[] | [.name, (.size | tostring), (.digest // "")] | @tsv')

    select_uploads
    if [[ ${#pkg_uploads[@]} -gt 0 ]]; then
        (cd "$stage" && gh release upload "$tag" -R "$gh_repo" --clobber "${pkg_uploads[@]}")
    fi
    (cd "$stage" && gh release upload "$tag" -R "$gh_repo" --clobber "${db_uploads[@]}")

    select_previous "${published[@]}"
    for asset in "${published[@]}"; do
        keep_file "$asset" && continue
        msg2 "deleting old asset $asset"
        gh release delete-asset "$tag" "$asset" -R "$gh_repo" -y
    done
}

# --- GitLab generic package registry ---------------------------------------------
gitlab_token() {  # <host>
    if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        printf '%s' "$GITLAB_TOKEN"
    elif command -v glab >/dev/null 2>&1; then
        glab config get token --host "$1" 2>/dev/null || true
    fi
}

# curl with the token. It goes to curl through a file descriptor, not on the
# command line, where other users could read it (ps).
gl() {
    curl -sS --fail-with-body --retry 3 -H @<(printf 'PRIVATE-TOKEN: %s\n' "$gl_token") "$@"
}

# Writes every file of the package gl_pkg/gl_ver to gl_listing, oldest first:
# id, name, size, sha256, upload time. Sets gl_pkg_id (empty until the first
# upload creates the package).
gitlab_files() {
    local page=1 resp
    : > "$gl_listing"
    # fetched before jq reads it, so that an HTTP error (bad token, no
    # access) ends the upload here with curl's message
    resp="$(gl "$gl_api/projects/$gl_project/packages?package_type=generic&package_name=$gl_pkg&per_page=100")"
    gl_pkg_id="$(jq -r --arg n "$gl_pkg" --arg v "$gl_ver" \
        '[.[] | select(.name == $n and .version == $v) | .id][0] // empty' <<<"$resp")"
    [[ -n "$gl_pkg_id" ]] || return 0
    while :; do
        resp="$(gl "$gl_api/projects/$gl_project/packages/$gl_pkg_id/package_files?per_page=100&page=$page")"
        [[ "$(jq length <<<"$resp")" -gt 0 ]] || break
        jq -r '.[] | [(.id | tostring), .file_name, (.size | tostring), (.file_sha256 // ""), .created_at] | @tsv' \
            <<<"$resp" >> "$gl_listing"
        page=$((page + 1))
    done
    sort -t$'\t' -k5,5 -k1,1n -o "$gl_listing" "$gl_listing"
}

publish_gitlab() {
    local url="$1" f id name size sha
    need curl curl
    need jq jq
    [[ "$url" =~ ^(https://([^/]+)/api/v4)/projects/([^/]+)/packages/generic/([^/]+)/([^/]+)/?$ ]] \
        || die "not a GitLab generic package URL: $url"
    gl_api="${BASH_REMATCH[1]}"
    gl_project="${BASH_REMATCH[3]}"
    gl_pkg="${BASH_REMATCH[4]}"
    gl_ver="${BASH_REMATCH[5]}"
    gl_listing="$BUILD_DIR/publish-gitlab.tsv"
    gl_token="$(gitlab_token "${BASH_REMATCH[2]}")"
    [[ -n "$gl_token" ]] || die "no GitLab token for ${BASH_REMATCH[2]}: set GITLAB_TOKEN or run 'glab auth login'"

    for f in "${current[@]}"; do
        # GitLab's rule for generic package file names
        [[ "$f" =~ ^[A-Za-z0-9._~+-]+$ && "$f" != *..* ]] \
            || die "GitLab doesn't accept the file name $f"
    done

    gitlab_files
    # A file uploaded again under the same name is stored beside the old one,
    # and downloads get the newest: compare with that one (the list is
    # oldest first).
    while IFS=$'\t' read -r id name size sha _; do
        pub_size[$name]="$size"
        pub_sha256[$name]="$sha"
    done < "$gl_listing"

    select_uploads
    for f in "${pkg_uploads[@]}" "${db_uploads[@]}"; do
        gl --upload-file "$stage/$f" "$gl_api/projects/$gl_project/packages/generic/$gl_pkg/$gl_ver/$f" >/dev/null
    done

    # delete old package versions (except the previous one of each package),
    # and the older copies of files that were uploaded again
    gitlab_files
    local -A newest=()
    local names=()
    while IFS=$'\t' read -r id name _; do newest[$name]="$id"; names+=("$name"); done < "$gl_listing"
    select_previous "${names[@]}"
    while IFS=$'\t' read -r id name _; do
        if ! keep_file "$name"; then
            msg2 "deleting old file $name"
        elif [[ "${newest[$name]}" == "$id" ]]; then
            continue
        fi
        gl -X DELETE "$gl_api/projects/$gl_project/packages/$gl_pkg_id/package_files/$id" >/dev/null
    done < "$gl_listing"
}

# ---------------------------------------------------------------------------------
failed=()
for url in "${targets[@]}"; do
    msg "Publishing to $url"
    case "$url" in
        https://github.com/*) kind=github ;;
        https://*/api/v4/projects/*/packages/generic/*) kind=gitlab ;;
        *) warn "don't know how to upload to $url"; failed+=("$url"); continue ;;
    esac
    # In a subshell, so an error ends only this server's upload. Not as the
    # condition of an if: bash ignores set -e there, also in the subshell.
    set +e
    ( set -e; "publish_$kind" "$url" )
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        msg2 "done: $url"
    else
        warn "publishing to $url failed"
        failed+=("$url")
    fi
done

[[ ${#failed[@]} -eq 0 ]] || die "failed: ${failed[*]}"
msg "Published to ${#targets[@]} server(s)"
