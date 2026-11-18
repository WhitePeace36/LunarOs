# How Lunar works

## Repositories and packages

Lunar uses Arch's repositories for everything it doesn't change. Its own
packages, and the AUR packages it ships, are in the `[lunar]` pacman
repository. `[lunar]` comes first in `/etc/pacman.conf`, so its packages win
over packages with the same name in Arch's repositories.

| Package | Purpose |
|---|---|
| `linux-lunar-v3` | Default kernel on CPUs with x86-64-v3, built from [linux-lunar](https://github.com/WhitePeace36/linux-lunar) with Clang, ThinLTO and `-march=x86-64-v3` |
| `linux-lunar` | The same kernel built with GCC, without LTO, for generic x86-64: default kernel on older CPUs, and the live ISO's kernel |
| `lunar-settings` | System settings, built from [lunar-settings](https://github.com/WhitePeace36/lunar-settings): sysctl, THP/tmpfiles, kernel parameters, zram, I/O schedulers, SATA/HDD rules, AMD GPU power limit and VRAM clock, limits, mDNS, `lunar-update-cmdline`, `lunar-sdboot-update`, `lunar-gpu-setup` |
| `lunar-hooks` | pacman hooks: Lunar branding in `/etc/os-release`, "reboot required" notice after kernel/systemd updates |
| `lunar-kde-settings` | Breeze Dark everywhere (Plasma, GTK, first login); the Lunar logo instead of the KDE logo on the application launcher (a Plasma update script, run once per user, that leaves an icon the user picked alone); panels that don't float (update script, once per user); the Lunar wallpaper 20 on the desktop (update script, once per user, only where Plasma's default wallpaper is set) and 26 on the lock screen (`/etc/xdg/kscreenlockerrc`) and the login screen (`/usr/lib/plasmalogin/plasmalogin.conf.d/50-lunar.conf`); no splash screen after login (`/etc/xdg/ksplashrc`, and once per user after Breeze Dark is applied, which sets its own); screen dims after 5 minutes, turns off after 7, after 5 when locked (`/etc/xdg/powerdevilrc`); system tray: Weather Report and Keyboard Layout disabled, Clipboard always shown, Notifications only in the tray's popup (update script, once per user); Ananicy Configurator, Pipewire Configurator and ProtonUp-Qt on the desktop (links made at login, once per application and user, as soon as the application is installed); LibreWolf as the default browser (`BrowserApplication` in `/etc/xdg/kdeglobals`, `/etc/xdg/mimeapps.list` for links and HTML files) |
| `lunar-browser-settings` | Brave and LibreWolf defaults: DNS over HTTPS (Quad9), HTTPS only, no password or payment saving, DuckDuckGo, fingerprinting protection / resistFingerprinting off, dark websites in LibreWolf. Brave: policies in `/etc/brave/policies` (`managed/` enforced: DoH, HTTPS, fingerprinting; `recommended/` changeable defaults), see `brave://policy`. LibreWolf: `librewolf.overrides.cfg` in `/etc/skel` for new users (LibreWolf itself already ships uBlock Origin, DuckDuckGo, HTTPS-only, no password/payment saving) |
| `lunar-wallpapers` | The wallpapers in `branding/` as Plasma wallpaper packages in `/usr/share/wallpapers/lunar-*` (`prepare.sh` copies them into the build folder) |
| `lunar-zsh-config` | zsh prompt, completion menu, `lsd`/`bat` aliases |
| `ananicy-cpp-lunar` | Build of the [ananicy-cpp fork](https://github.com/WhitePeace36/ananicy-cpp-lunar) (replaces Arch's `ananicy-cpp`) |
| `lunar-ananicy-rules` | ananicy-cpp rules from [ananicy-rules](https://github.com/WhitePeace36/ananicy-rules) |
| `elara` | [Elara](https://github.com/WhitePeace36/Elara) scheduler, enabled by default; conflicts with `scx-manager` |
| `pipewire-configurator` | [PipewireConfigurator](https://github.com/WhitePeace36/PipewireConfigurator) |
| `ananicy-configurator` | [AnanicyConfigurator](https://github.com/WhitePeace36/AnanicyConfigurator) |
| `sysmon` | [Sysmon](https://github.com/WhitePeace36/Sysmon), the system monitor (installed instead of KDE's `plasma-systemmonitor`); Lunar's package gives it the global shortcut Ctrl+Shift+Esc |
| `lunar-calamares` | Installer: upstream Calamares 3.3 with Lunar's modules, configuration and branding |
| `lunar-keyring`, `lunar-mirrorlist` | Signing key and servers of `[lunar]` (GitHub, GitLab as mirror) |

The AUR packages are listed in `packages/aur-packages.txt`.

## The kernel

`packages/linux-lunar/` has no PKGBUILD of its own. `prepare.sh` clones
linux-lunar at a pinned commit, appends `lunar-distro.cfg` to its
`customization.cfg` and runs `./lunar.sh --config-only`; the resulting folder
is then built in the clean chroot like every other package.

Lunar builds that kernel twice, from the same commit and `_version`:

| Package | Compiler | LTO | `-march` | Runs on |
|---|---|---|---|---|
| `linux-lunar-v3` | Clang | ThinLTO | `x86-64-v3` | CPUs with AVX2, BMI2, FMA, MOVBE (Intel Haswell, AMD Zen 1 and newer) |
| `linux-lunar` | GCC | none | generic `x86-64` | every x86-64 CPU |

`packages/linux-lunar-v3/prepare.sh` runs linux-lunar's `prepare.sh` with
`packages/linux-lunar-v3/lunar-distro.cfg` as a second file, appended after
linux-lunar's, which only sets the package suffix, compiler, LTO and `-march`.
The kernel releases differ (`7.x.y-N-lunar`, `7.x.y-N-lunar-v3`), so both
packages can be installed at the same time.

`lunar-distro.cfg` only lists what Lunar changes from linux-lunar's
defaults: the version, the compiler, LTO and `_march` (`generic` /
`x86-64-v3` instead of `native`: a package must run on more than the build
machine), and building non-interactively without user patches. Everything
else keeps linux-lunar's
defaults: 1000 Hz, full preemption, periodic tick, the performance governor,
THP `always`. `lunar-settings` sets the memory values linux-lunar compiles in
(`vm.defrag_mode=1`, boost 600, proactiveness 50, THP, ...) once more as
sysctl and tmpfiles settings, so linux-lts gets them as well. linux-lts keeps
its own tick and governor.

linux-lunar has no `--config-only` mode yet; until it does, `prepare.sh`
applies `packages/linux-lunar/lunar-config-only.patch`, which also lets the
build continue when the source folder is read-only.

The live ISO boots `linux-lunar` (generic, so it starts on every CPU), with
linux-lts as a fallback entry. The installer installs `linux-lunar-v3` when
glibc's loader (`ld-linux-x86-64.so.2 --help`) reports x86-64-v3 as supported
(the CPU flags in `/proc/cpuinfo` if that fails), `linux-lunar` otherwise.

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
It removes entries of removed kernels and makes `linux-lunar-v3` the default,
or `linux-lunar` if `-v3` isn't installed, unless another default was set by
hand in `loader.conf` (an entry name or a glob such as `lunar-linux-lts*`)
or with the boot menu's `d` key. It records the default it chose itself in
`/var/lib/lunar/sdboot-default`; only that one moves, so installing
`linux-lunar-v3` later (`pacman -S linux-lunar-v3 linux-lunar-v3-headers`)
makes it the new default, and a default changed by hand is never reset.

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
`linux-lunar-v3` on CPUs with x86-64-v3, otherwise `linux-lunar` (default
entry), and `linux-lts`, ranks Arch mirrors with
reflector, uses zsh for new users, masks rtkit, enables ufw (incoming blocked
except LocalSend, 53317 tcp/udp), sets `deny = 10` in
`/etc/security/faillock.conf` (lockout after 10 wrong passwords instead of 3),
and installs Flatseal from Flathub.
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
