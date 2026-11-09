# Lunar ISO profile

An [archiso](https://gitlab.archlinux.org/archlinux/archiso) profile, started
from Arch's `releng` profile (archiso v92) and changed for Lunar:

- **UEFI only** (`bootmodes=('uefi.systemd-boot')`): the installer always
  sets up systemd-boot. `lunar-install` refuses to start on a BIOS boot.
- Boot menu: linux-lunar (default), linux-lts (fallback), Memtest86+.
  One archiso initramfs per kernel (`airootfs/etc/mkinitcpio.d/*.preset`).
- KDE Plasma live session: `lunar-live-user.service` creates `liveuser`
  (no password, sudo/polkit without password), Plasma Login Manager logs it
  in automatically (`etc/plasmalogin.conf.d/lunar-live.conf`).
- NetworkManager instead of systemd-networkd/iwd, Bluetooth on, sshd off,
  `archlinux-keyring-wkd-sync.timer` and rtkit masked.
- Graphics: Mesa only (NVIDIA cards run on nouveau/NVK in the live session).
  The installer puts the right NVIDIA driver on the installed system.
- `pacman.conf` (used for the build) has `[lunar]` with `@LUNAR_REPO_SERVER@`,
  which `scripts/build-iso.sh` fills in. The live system gets
  `airootfs/etc/pacman.conf`, the same one installed systems get.
- Launcher: `/usr/local/bin/lunar-install` and `lunar-install.desktop`
  (menu and desktop). Installer log: `~/lunar-install.log`.

Build with `scripts/build-iso.sh` (needs `archiso`); the ISO lands in `iso/out/`.
