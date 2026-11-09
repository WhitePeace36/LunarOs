#!/usr/bin/env bash
# Create the GPG key that signs Lunar packages and the repo database,
# fill packages/lunar-keyring/ with it and write its fingerprint to lunar.conf.
#
#   scripts/make-key.sh                 create a new key
#   scripts/make-key.sh <fingerprint>   use an existing secret key
#
# Back up the secret key afterwards (gpg --export-secret-keys --armor <fpr>);
# without it you can't publish updates that existing installs will accept.

. "$(dirname "$0")/common.sh"
need gnupg gpg

KEYRING_DIR="$LUNAR_ROOT/packages/lunar-keyring"
uid="Lunar Repository <${LUNAR_PACKAGER#*<}"
uid="${uid%>}>"

if [[ $# -ge 1 ]]; then
    fpr="$1"
    gpg --list-secret-keys "$fpr" >/dev/null 2>&1 || die "no secret key $fpr in your keyring"
else
    if [[ -n "$LUNAR_SIGNING_KEY" ]] && gpg --list-secret-keys "$LUNAR_SIGNING_KEY" >/dev/null 2>&1; then
        die "lunar.conf already has key $LUNAR_SIGNING_KEY; pass a fingerprint to switch keys"
    fi
    msg "Creating signing key: $uid"
    gpg --batch --passphrase '' --quick-gen-key "$uid" ed25519 sign 0
    fpr="$(gpg --list-secret-keys --with-colons "$uid" | awk -F: '/^fpr:/ { print $10; exit }')"
fi

[[ -n "$fpr" ]] || die "could not determine the key fingerprint"
msg "Signing key: $fpr"

gpg --export "$fpr" > "$KEYRING_DIR/lunar.gpg"
echo "$fpr:4:" > "$KEYRING_DIR/lunar-trusted"
: > "$KEYRING_DIR/lunar-revoked"
msg2 "wrote packages/lunar-keyring/{lunar.gpg,lunar-trusted,lunar-revoked}"

sed -i "s/^LUNAR_SIGNING_KEY=.*/LUNAR_SIGNING_KEY=\"$fpr\"/" "$LUNAR_ROOT/lunar.conf"
msg2 "set LUNAR_SIGNING_KEY in lunar.conf"

cat <<EOF

Next steps:
  1. Trust the key on this machine (needed to build the ISO and to test):
       sudo pacman-key --add packages/lunar-keyring/lunar.gpg
       sudo pacman-key --lsign-key $fpr
  2. Back up the secret key somewhere safe:
       gpg --export-secret-keys --armor $fpr > lunar-signing-key.asc
EOF
