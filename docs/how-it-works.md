# How Lunar works

## Repositories and packages

Lunar uses Arch's repositories for everything it doesn't change. Its own
packages, and the AUR packages it ships, are in the `[lunar]` pacman
repository. `[lunar]` comes first in `/etc/pacman.conf`, so its packages win
over packages with the same name in Arch's repositories.

| Package | Purpose |
|---|---|
| `linux-lunar` | Default kernel, built from [linux-lunar](https://github.com/WhitePeace36/linux-lunar) |
| `lunar-settings` | System settings, built from [lunar-settings](https://github.com/WhitePeace36/lunar-settings): sysctl, THP/tmpfiles, kernel parameters, zram, I/O schedulers, SATA/HDD rules, AMD GPU power limit and VRAM clock, limits, mDNS, `lunar-update-cmdline`, `lunar-sdboot-update`, `lunar-gpu-setup` |
| `lunar-hooks` | pacman hooks: Lunar branding in `/etc/os-release`, "reboot required" notice after kernel/systemd updates |
| `lunar-kde-settings` | Breeze Dark everywhere (Plasma, GTK, first login) |
| `lunar-zsh-config` | zsh prompt, completion menu, `lsd`/`bat` aliases |
| `ananicy-cpp-lunar` | Build of the [ananicy-cpp fork](https://github.com/WhitePeace36/ananicy-cpp) (replaces Arch's `ananicy-cpp`) |
| `lunar-ananicy-rules` | ananicy-cpp rules from [ananicy-rules](https://github.com/WhitePeace36/ananicy-rules) |
| `elara` | [Elara](https://github.com/WhitePeace36/Elara) scheduler, enabled by default; conflicts with `scx-manager` |
| `pipewire-configurator-simple` | [PipewireSimpleConfigurator](https://github.com/WhitePeace36/PipewireSimpleConfigurator) |
| `ananicy-configurator` | [AnanicyConfigurator](https://github.com/WhitePeace36/AnanicyConfigurator) |
| `lunar-calamares` | Installer: upstream Calamares 3.3 with Lunar's modules, configuration and branding |
| `lunar-keyring`, `lunar-mirrorlist` | Signing key and server of `[lunar]` |

The AUR packages are listed in `packages/aur-packages.txt`.

## The kernel

`packages/linux-lunar/` has no PKGBUILD of its own. `prepare.sh` clones
linux-lunar at a pinned commit, appends `lunar-distro.cfg` to its
`customization.cfg` and runs `./lunar.sh --config-only`; the resulting folder
is then built in the clean chroot like every other package.

`lunar-distro.cfg` differs from a personal linux-lunar build:
`_march=generic` (one package must boot every x86-64 CPU), `schedutil` and an
idle tick. `lunar-settings` adds `cpufreq.default_governor=performance
nohz=off` to the kernel command line, which restores linux-lunar's own
defaults and applies to linux-lts too. `lunar-settings` also sets the memory
values linux-lunar compiles in (`vm.defrag_mode=1`, boost 600, proactiveness
50, ...), so linux-lts gets them as well.

linux-lunar has no `--config-only` mode yet; until it does, `prepare.sh`
applies `packages/linux-lunar/lunar-config-only.patch`, which also lets the
build continue when the source folder is read-only.

The live ISO boots linux-lunar as well, with linux-lts as a fallback entry.

## Graphics drivers

`lunar-gpu-setup` (in `lunar-settings`) runs during installation and can be
run again after a GPU change. It reads the PCI IDs:

| GPU | Driver |
|---|---|
| NVIDIA Turing and newer | `nvidia-open-dkms` |
| NVIDIA Maxwell, Pascal, Volta | 580xx legacy driver (AUR, built into `[lunar]`) |
| NVIDIA Kepler and older | nouveau (NVIDIA's old drivers don't support Wayland) |
| AMD, Intel | Mesa |

Laptops with two GPUs get both drivers plus `nvidia-prime`.
`lunar-gpu-setup --print` shows what it would do. The live ISO uses Mesa only
(NVIDIA cards run on nouveau/NVK there).

## Kernel parameters

`lunar-update-cmdline` writes `/etc/kernel/cmdline` from, in this order:

1. `/etc/lunar/cmdline-root`: `root=`, LUKS and subvolume options, written
   once by the installer
2. `/usr/lib/lunar/cmdline.d/*.conf`: Lunar's parameters (lunar-settings)
3. `/etc/lunar/cmdline.d/*.conf`: the user's parameters

Within 2 and 3 the files are read in name order. Nothing is merged or
removed; when a parameter appears twice the kernel uses the last value, so the
user's parameters always win. `LUNAR_DEFAULTS=no` in
`/etc/lunar/cmdline.conf` leaves out step 2. It then runs
`lunar-sdboot-update`.

Both tools only act on systems installed by Lunar's installer (where
`/etc/lunar/cmdline-root` exists).

## Boot entries

`lunar-sdboot-update` writes `/boot/loader/entries/lunar-<kernel>.conf` and
`lunar-<kernel>-fallback.conf` for every installed kernel, using the images
mkinitcpio keeps in `/boot` (`vmlinuz-<kernel>`, `initramfs-<kernel>.img`).
It removes entries of removed kernels and makes `linux-lunar` the default
unless another default is set in `loader.conf`.

A pacman hook runs `lunar-update-cmdline` (and with it `lunar-sdboot-update`)
after every kernel install, update or removal, and when Lunar's parameter
files change. So a kernel update also applies edits made in
`/etc/lunar/cmdline.d/` since the last run. `systemd-boot-update.service`
keeps the boot loader itself up to date. The ESP is mounted at `/boot`.

## Installer

Upstream Calamares 3.3 (Qt6), built with two Lunar job modules
(`packages/lunar-calamares/modules`): `pacstrap` installs the system straight
from the repositories (no image), and `gpudrivers` runs `lunar-gpu-setup`.

Pages: welcome, location, keyboard, partitions, graphics (Automatic / Mesa
only), additional software (`config/modules/netinstall.yaml`), user,
summary.

The installer is UEFI only and always installs systemd-boot. It installs
`linux-lunar` (default entry) and `linux-lts`, ranks Arch mirrors with
reflector, uses zsh for new users, masks rtkit, enables ufw (incoming blocked
except LocalSend, 53317 tcp/udp), and installs Flatseal from Flathub.
Filesystems: Btrfs (default, with subvolumes), ext4, XFS, F2FS; optional LUKS2
encryption. There is no swap partition or swap file: Lunar swaps to zram only.
The initramfs uses mkinitcpio's systemd-based hooks (`systemd`, `sd-vconsole`,
`sd-encrypt`).

Calamares' systemd-boot step uses `kernel-install`. The last step,
`scripts/lunar-post-install`, moves that setup over to Lunar's own: it saves
the root options to `/etc/lunar/cmdline-root`, removes the kernel-install
copies and runs `lunar-update-cmdline`.

## The ISO

See [iso/README.md](../iso/README.md).
