<p align="center">
  <img src="branding/lunar-logo.svg" alt="Lunar logo" width="160">
</p>

<h1 align="center">LunarOs</h1>

<p align="center">
  KDE Plasma on Arch Linux, with the linux-lunar kernel, the Elara sched_ext
  scheduler, ananicy-cpp (fork), and settings tuned for desktop gaming.
</p>

Lunar uses Arch's repositories (core, extra, multilib) for everything it
doesn't change. Its own packages, plus the AUR packages it needs, live in a
small `[lunar]` pacman repo listed **above** Arch's repos, so Lunar's versions
win.

## What's in here

| Path | What it is |
|---|---|
| `lunar.conf` | Settings for all scripts: repo URL, signing key, packager |
| `packages/<name>/` | One folder per package in the `[lunar]` repo (PKGBUILD + its files) |
| `packages/build-order.txt` | Order `build-packages.sh` builds in |
| `packages/aur-packages.txt` | AUR packages built into `[lunar]` |
| `iso/` | Live/install ISO profile (archiso) |
| `branding/` | Logo master file and the logo options |
| `scripts/` | Build, sign and publish helpers |

### Packages

| Package | Purpose |
|---|---|
| `linux-lunar` | Default kernel, built from `WhitePeace36/linux-lunar` (see below) |
| `lunar-settings` | All system settings, from your repo `WhitePeace36/lunar-settings`: sysctl, THP/tmpfiles, kernel parameters (C1 only, performance governor, ...), zram, I/O schedulers, SATA/HDD rules, AMD GPU max power + fixed VRAM clock, limits, mDNS, `lunar-update-cmdline`, `lunar-sdboot-update`, `lunar-gpu-setup` |
| `lunar-hooks` | pacman hooks: Lunar branding in `/etc/os-release`, "reboot required" notice after kernel/systemd updates |
| `lunar-kde-settings` | Breeze Dark everywhere (Plasma, GTK, first login) |
| `lunar-zsh-config` | Prompt `user@host:path(branch⚡) »`, grid completion menu, `lsd`/`bat`/… aliases |
| `ananicy-cpp-lunar` | Build of the WhitePeace36 ananicy-cpp fork (replaces Arch's `ananicy-cpp`) |
| `lunar-ananicy-rules` | Your rules repo `WhitePeace36/ananicy-rules` |
| `elara` | Elara scheduler (`WhitePeace36/Elara`), enabled by default; conflicts with `scx-manager` |
| `pipewire-configurator-simple` | PipeWire GUI (`WhitePeace36/PipewireSimpleConfigurator`) |
| `ananicy-configurator` | GUI for the ananicy-cpp rules (`WhitePeace36/AnanicyConfigurator`) |
| `lunar-calamares` | Installer: upstream Calamares 3.3 + Lunar's modules, configs and branding |
| `lunar-keyring`, `lunar-mirrorlist` | Repo key and server |

The settings are for desktops (CPU idle limited to C1, no PCIe power saving,
performance governor); there is no battery profile for now. Any setting can
be overridden with a file in `/etc` (see the lunar-settings README).

### The kernel

`packages/linux-lunar/` has no PKGBUILD of its own. `prepare.sh` clones
`WhitePeace36/linux-lunar` at a pinned commit, appends `lunar-distro.cfg` to
its `customization.cfg` and runs `./lunar.sh --config-only`; the resulting
folder is then built in the clean chroot like every other package.

`lunar-distro.cfg` differs from a personal linux-lunar build: `_march=generic`
(one package must boot every x86-64 CPU), `schedutil` and an idle tick. `lunar-settings`
adds `cpufreq.default_governor=performance nohz=off` to the kernel command
line, which gives linux-lunar's own defaults back (and applies to linux-lts
too). `lunar-settings` sets the same memory values linux-lunar compiles in
(defrag_mode 1, boost 600, proactiveness 50, ...), so linux-lts gets them as
well.

`--config-only` doesn't exist in linux-lunar yet; until it does,
`prepare.sh` applies `packages/linux-lunar/lunar-config-only.patch`, which also
lets the build continue when the source folder is read-only. Pushing that
patch to linux-lunar makes it unnecessary.

`linux-lts` from Arch is installed as the fallback kernel. The live ISO boots
linux-lunar too (linux-lts as a fallback entry), with Mesa only.

### Graphics drivers

`lunar-gpu-setup` (in `lunar-settings`, run by the installer and by hand after
a GPU swap) reads the PCI IDs: NVIDIA Turing and newer get `nvidia-open-dkms`,
Maxwell/Pascal/Volta the 580xx legacy driver (AUR, built into `[lunar]`),
Kepler and older nouveau (NVIDIA's old drivers have no Wayland support),
AMD/Intel Mesa. Laptops with two GPUs get both plus `nvidia-prime`.
`lunar-gpu-setup --print` shows what it would do.

### Kernel parameters

`lunar-update-cmdline` collects `/usr/lib/lunar/cmdline.d/*.conf` (from the
packages) and `/etc/lunar/cmdline.d/*.conf` (your overrides; a same-named
file in `/etc` replaces the one in `/usr/lib`) and writes `/etc/kernel/cmdline` = `/etc/lunar/cmdline-root` (root=, LUKS,
subvolume, resume; written once by the installer) + those parameters. Then
`lunar-sdboot-update` writes the systemd-boot entries.

`lunar-update-cmdline --print` shows the current list.

### Boot entries

`lunar-sdboot-update` writes `/boot/loader/entries/lunar-<kernel>.conf` (and
`-fallback.conf`) for every installed kernel, using the images mkinitcpio
keeps in `/boot` (`vmlinuz-<kernel>`, `initramfs-<kernel>.img`), removes
entries of removed kernels and makes `linux-lunar` the default unless you
picked another default. A pacman hook runs it after every kernel install,
upgrade or removal; `systemd-boot-update.service` keeps the boot loader itself
current. The ESP must be mounted at `/boot` (the installer does that).

### Installer

Upstream Calamares 3.3 (Qt6), built with two Lunar job modules
(`packages/lunar-calamares/modules`): `pacstrap` installs the system straight
from the repos (no image), `gpudrivers` runs `lunar-gpu-setup`. Pages:
welcome, location, keyboard, partitions, **Graphics** (Automatic / Mesa only),
additional software
(`config/modules/netinstall.yaml`), user, summary.

It is **UEFI only** and always installs **systemd-boot**. It installs
`linux-lunar` (default entry) and `linux-lts`, ranks Arch mirrors with
reflector, uses zsh for new users, masks rtkit, enables ufw (incoming blocked
except LocalSend 53317 tcp/udp), installs Flatseal from Flathub, and no AUR
helper. Filesystems: Btrfs (default, with subvolumes), ext4, XFS, F2FS;
optional LUKS2 encryption. The last step, `scripts/lunar-post-install`, turns
the boot setup of Calamares' systemd-boot step (kernel-install) into Lunar's
own (`lunar-update-cmdline`).

## How the repositories fit together

| Repo | Holds | Built by |
|---|---|---|
| `WhitePeace36/LunarOs` | this project: PKGBUILDs, installer config, ISO profile, scripts | - |
| `WhitePeace36/lunar-repo` | only the release with the built packages (`[lunar]`) | `scripts/publish.sh` |
| `WhitePeace36/linux-lunar`, `ananicy-cpp`, `Elara`, `PipewireSimpleConfigurator`, `AnanicyConfigurator` | the projects' own source; no Lunar files needed in them | their PKGBUILD here pins a commit |
| `WhitePeace36/lunar-settings` | sysctl, tmpfiles, cmdline, udev, zram, ... (`files/`) | `packages/lunar-settings/prepare.sh` |
| `WhitePeace36/ananicy-rules` | your rules in `ananicy.d/` (same layout as `/etc/ananicy.d`) | `packages/lunar-ananicy-rules` |

Every Lunar package is a folder under `packages/` with the PKGBUILD and the
files it installs; no build output is committed (`.gitignore`). A package for
one of your projects only pins a commit, so a release is: push to the
project, change `_commit` here, rebuild that package, publish.

## Building

Run everything on an Arch (or Arch-based) machine. One-time setup:

```sh
sudo pacman -S --needed devtools archiso squashfs-tools github-cli
gpg --locate-keys torvalds@kernel.org gregkh@kernel.org   # kernel tarball signatures
scripts/make-key.sh          # creates the signing key, fills packages/lunar-keyring
```

Create `WhitePeace36/lunar-repo` on GitHub (empty). If you use another name,
change `LUNAR_REPO_URL` in `lunar.conf`.

Then, in this order (later steps need earlier packages):

```sh
scripts/build-aur.sh         # AUR packages Arch doesn't have (asks per PKGBUILD)
scripts/build-packages.sh    # Lunar's packages incl. the kernel -> repo/x86_64 (signed)
scripts/publish.sh           # upload repo/x86_64 to the GitHub release
scripts/build-iso.sh         # ISO in iso/out/
```

The kernel build takes a while (30-90 minutes depending on the CPU). Test the
ISO in a VM before real hardware, e.g. with GNOME Boxes or
`qemu-system-x86_64 -enable-kvm -m 8G -cdrom iso/out/lunar-*.iso -bios /usr/share/edk2/x64/OVMF.4m.fd`
(UEFI firmware is required).

### Updating

* Kernel: `_version` in `packages/linux-lunar/lunar-distro.cfg` and/or `_commit` in its `prepare.sh`, then `scripts/build-packages.sh linux-lunar`.
* Your other projects: `_commit` in their PKGBUILD, then `scripts/build-packages.sh <name>`.
* Settings (sysctl, tmpfiles, cmdline, ...): edit them in the `lunar-settings` repo, raise `pkgver` there, push, set `_commit` in `packages/lunar-settings/prepare.sh`, then `scripts/build-packages.sh lunar-settings`.
* Ananicy rules: push to `WhitePeace36/ananicy-rules`, set `_commit` in `packages/lunar-ananicy-rules/PKGBUILD`, rebuild.
* Calamares: `pkgver`/`_commit` in `packages/lunar-calamares/PKGBUILD` (a release tag), compare upstream's module configs with `config/modules`.
* ISO profile: compare `iso/` with a newer archiso `configs/releng` now and then.
* AUR packages: re-run `scripts/build-aur.sh`; it rebuilds only what changed.
* `scripts/publish.sh` after every build.

## Before the first release - things to check

These depend on details I couldn't test without an Arch machine:

1. **Your ananicy rules repo:** `ananicy.d/ananicy.conf` must exist in it
   (the package checks for it).
2. **Elara build:** uses the `include/vmlinux.h` committed in the Elara repo
   (regenerate it with `create_vmlinux.h.sh` after big kernel changes).
3. **AUR names:** `build-aur.sh` reports what it built and what it found in
   Arch's repos. If a name in `aur-packages.txt` doesn't exist in the AUR
   (split packages are listed by their base name), fix it there.
4. **In a VM (UEFI):** systemd-boot default entry is `linux-lunar`, no
   leftover `<machine-id>` entries in `/boot/loader/entries`; `uname -r` shows `-lunar`; ufw active (`sudo ufw status`); Flatseal
   present; `systemctl status elara ananicy-cpp`; `cat /proc/cmdline`.
5. **On NVIDIA hardware:** the DKMS module builds for both kernels
   (`dkms status`).
6. **On AMD hardware:** `systemctl status lunar-amdgpu-performance` and
   compare with LACT. Don't run LACT's own power settings at the same time.
7. **Installer packages:** `scripts/build-iso.sh` checks that every package in
   `iso/packages.x86_64`, `pacstrap.conf` and `netinstall.yaml` exists in a
   repo, and stops with a list if not.

## License

Lunar's own files are GPL-2.0-only (see `LICENSE`). The installer modules in
`packages/lunar-calamares/modules` are GPL-3.0-or-later like Calamares, which
they are built into; files taken from Arch's archiso profile (`iso/`) stay
GPL-3.0-or-later, and packages of other projects keep their own licenses.
