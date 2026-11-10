<p align="center">
  <img src="branding/lunar-logo.svg" alt="Lunar logo" width="160">
</p>

<h1 align="center">LunarOs</h1>

<p align="center">
  KDE Plasma on Arch Linux, with the linux-lunar kernel, the Elara sched_ext
  scheduler, ananicy-cpp (fork), and settings tuned for desktop gaming.
</p>

Lunar is Arch Linux with a ready-to-use KDE Plasma desktop for gaming. It
uses Arch's repositories (core, extra, multilib) for everything it doesn't
change. Its own packages, and the few AUR packages it ships, come from the
`[lunar]` repository, which is listed above Arch's.

## Features

**Desktop**
- KDE Plasma on Wayland, Plasma Login Manager, Breeze Dark throughout
  (Plasma and GTK apps)
- PipeWire for sound, with [PipewireSimpleConfigurator](https://github.com/WhitePeace36/PipewireSimpleConfigurator)
  and EasyEffects
- Wi-Fi, Bluetooth and printer/scanner discovery on the network (mDNS) work
  out of the box
- zsh with the prompt `user@host:path(branch⚡) »`, `lsd`/`bat` aliases
  (`ll`, `la`, `lt`, ...), `micro` as editor and `most` as pager

**Performance**
- [linux-lunar](https://github.com/WhitePeace36/linux-lunar) as the default
  kernel, Arch's `linux-lts` as fallback
- [Elara](https://github.com/WhitePeace36/Elara), a sched_ext CPU scheduler
  driven by the nice values that [ananicy-cpp](https://github.com/WhitePeace36/ananicy-cpp)
  sets from Lunar's [rules](https://github.com/WhitePeace36/ananicy-rules);
  [AnanicyConfigurator](https://github.com/WhitePeace36/AnanicyConfigurator)
  edits the rules
- System settings for desktops ([lunar-settings](https://github.com/WhitePeace36/lunar-settings)):
  memory and swap (zram), transparent huge pages, CPU kept in C1 with the
  performance governor, raised file and process limits, I/O schedulers per
  disk type
- AMD graphics cards run at their highest power limit with the VRAM clock
  fixed at its maximum

**Graphics**
- AMD and Intel: Mesa
- NVIDIA: picked automatically during installation, Wayland-capable drivers
  only: `nvidia-open` for Turing (GTX 16xx/RTX 20xx) and newer, the 580xx
  driver for Maxwell to Volta (GTX 750 to GTX 10xx), nouveau for older cards.
  The installer can also install Mesa only.

**Apps**
- Gaming: Steam, Lutris, ProtonUp-Qt, MangoHud, gamescope
- Internet: Brave, LibreWolf, LocalSend, Remmina (RDP/VNC)
- Office: OnlyOffice, printing (CUPS, HP drivers) and scanning (Simple Scan)
- Flatpak with Flathub and Flatseal, AppImageLauncher, balenaEtcher
- No AUR helper is installed

**System**
- systemd-boot, Btrfs with subvolumes by default (ext4, XFS and F2FS too),
  optional full-disk encryption (LUKS2)
- Swap in compressed RAM (zram) only, no swap partition or file, so no
  hibernation
- Firewall (ufw) on: incoming connections are blocked, except for LocalSend
- rtkit is masked, so Elara and ananicy-cpp control the priority of audio
  and desktop threads

The settings are made for desktop PCs. On a laptop they cost battery life:
the CPU and PCIe links don't enter their power-saving states, and disks and
the sound chip stay powered.

## Requirements

- A 64-bit x86 PC that boots in **UEFI** mode (legacy BIOS isn't supported)
- **Secure Boot turned off** (the boot loader and kernel aren't signed)
- 4 GB of RAM and 40 GB of disk space
- An internet connection during installation: packages are downloaded
  from the repositories, so the system is up to date right away

## Installation

1. Write the ISO to a USB stick (balenaEtcher, Ventoy, or
   `dd if=lunar-*.iso of=/dev/sdX bs=4M status=progress`).
2. Boot from it in UEFI mode. The live session starts KDE Plasma by itself.
3. Connect to the internet, then start **Install Lunar** from the desktop.
4. The installer asks for language, keyboard, disk, graphics driver,
   additional software and the user account.

## After installation

| Task | How |
|---|---|
| Update the system | `sudo pacman -Syu` (or the `update` alias) |
| Change a sysctl setting | a file in `/etc/sysctl.d/` (for example `99-local.conf`) |
| Add or change a kernel parameter | put it into a file in `/etc/lunar/cmdline.d/` (for example `50-local.conf`), run `sudo lunar-update-cmdline`; your parameters come last and win over Lunar's |
| Leave out all of Lunar's kernel parameters | `LUNAR_DEFAULTS=no` in `/etc/lunar/cmdline.conf`, run `sudo lunar-update-cmdline` |
| Show the kernel parameters | `lunar-update-cmdline --print` |
| Switch graphics drivers after a GPU change | `sudo lunar-gpu-setup` (`--print` shows what it would do) |
| Edit the ananicy-cpp rules | AnanicyConfigurator |
| Check the scheduler | `systemctl status elara ananicy-cpp` |

Files in `/etc` always take precedence over Lunar's defaults in `/usr/lib`,
and updates never change them. Boot entries are written automatically
whenever a kernel is installed, updated or removed.

## Related repositories

| Repository | What it is |
|---|---|
| [linux-lunar](https://github.com/WhitePeace36/linux-lunar) | The kernel and its patches |
| [lunar-settings](https://github.com/WhitePeace36/lunar-settings) | sysctl, tmpfiles, kernel parameters, udev rules, boot entry tools |
| [Elara](https://github.com/WhitePeace36/Elara) | sched_ext CPU scheduler |
| [ananicy-cpp](https://github.com/WhitePeace36/ananicy-cpp) | ananicy-cpp fork |
| [ananicy-rules](https://github.com/WhitePeace36/ananicy-rules) | Lunar's ananicy-cpp rules |
| [AnanicyConfigurator](https://github.com/WhitePeace36/AnanicyConfigurator) | GUI for the ananicy-cpp rules |
| [PipewireSimpleConfigurator](https://github.com/WhitePeace36/PipewireSimpleConfigurator) | GUI for PipeWire settings |
| [lunar-repo](https://github.com/WhitePeace36/lunar-repo) | The `[lunar]` package repository |

This repository holds the packaging (PKGBUILDs), the installer
configuration, the ISO profile and the build scripts:

- [docs/how-it-works.md](docs/how-it-works.md): kernel packaging, boot
  entries, graphics driver selection, installer
- [docs/building.md](docs/building.md): building the packages and the ISO,
  publishing, updating components

## License

Lunar's own files are GPL-2.0-only (see `LICENSE`). The installer modules in
`packages/lunar-calamares/modules` are GPL-3.0-or-later like Calamares, which
they are built into; files taken from Arch's archiso profile (`iso/`) stay
GPL-3.0-or-later, and packages of other projects keep their own licenses.
