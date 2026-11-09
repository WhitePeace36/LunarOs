#!/usr/bin/env bash
# shellcheck disable=SC2034
# Lunar live/install ISO (based on Arch's releng profile, archiso v92).
# UEFI only: the installer always sets up systemd-boot.

iso_name="lunar"
iso_label="LUNAR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Lunar <https://github.com/WhitePeace36/LunarOs>"
iso_application="Lunar Live/Install"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="lunar"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/lunar-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/lunar-install"]="0:0:755"
  ["/usr/local/bin/lunar-live-user"]="0:0:755"
)
