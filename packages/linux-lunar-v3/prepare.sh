#!/usr/bin/env bash
# Prepares linux-lunar-v3 for scripts/build-packages.sh: the same steps as
# packages/linux-lunar/prepare.sh (same commit, same _version), with
# lunar-distro.cfg from this folder appended after linux-lunar's.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec "$here/../linux-lunar/prepare.sh" "${1:?usage: prepare.sh <work-dir>}" "$here/lunar-distro.cfg"
