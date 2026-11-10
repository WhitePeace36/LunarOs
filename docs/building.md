# Building Lunar

Everything is built on an Arch (or Arch-based) system: the packages in a
clean chroot (devtools), the ISO with archiso.

The builds don't use the host's mirrorlist or package cache: they download
from Arch's own mirrors (`LUNAR_ARCH_MIRRORS` in `lunar.conf`) into
`/var/lib/lunar-build/pkgcache` (`LUNAR_PKG_CACHE`). So they work the same on
Arch and on Arch-based distributions, whose mirrors can lag behind Arch and
whose caches can hold their own builds of Arch packages under the same file
names.

## Repository layout

| Path | What it is |
|---|---|
| `lunar.conf` | Settings for all scripts: repository URL, signing key, packager |
| `packages/<name>/` | One folder per `[lunar]` package (PKGBUILD and its files, or a `prepare.sh` that fetches them) |
| `packages/build-order.txt` | Order `build-packages.sh` builds in |
| `packages/aur-packages.txt` | AUR packages built into `[lunar]` |
| `iso/` | Live/install ISO profile (archiso) |
| `branding/` | Logo |
| `scripts/` | Build, sign and publish scripts |
| `docs/` | This documentation |

Build output (`build/`, `repo/`, `iso/out/`) is not committed.

## Setup

```sh
sudo pacman -S --needed devtools archiso squashfs-tools github-cli
gpg --locate-keys torvalds@kernel.org gregkh@kernel.org   # kernel tarball signatures
gh auth login                                             # for publish.sh
scripts/make-key.sh
```

`make-key.sh` creates the signing key, writes its fingerprint to
`LUNAR_SIGNING_KEY` in `lunar.conf` and puts the public key into
`packages/lunar-keyring`. Without a key, packages and the database are
unsigned and only test builds work.

The packages are published as assets of the release `x86_64` in the public
GitHub repository [lunar-repo](https://github.com/WhitePeace36/lunar-repo)
(`LUNAR_REPO_URL` in `lunar.conf`). `publish.sh` creates the release on the
first run; the repository itself must exist.

## Building

In this order, since later steps need packages from earlier ones:

```sh
scripts/build-aur.sh         # AUR packages Arch doesn't have
scripts/build-packages.sh    # Lunar's packages, including the kernel
scripts/publish.sh           # upload to the lunar-repo release
scripts/build-iso.sh         # ISO in iso/out/
```

- `build-aur.sh` clones each package from `aur-packages.txt`, shows the
  PKGBUILD for review (`--yes` skips that) and builds it. AUR packages they
  need are built first automatically; packages that would need Electron from
  the AUR (a source build of many hours) are refused. PGP keys a PKGBUILD
  lists in `validpgpkeys` are imported into your gpg keyring. Packages Arch's
  repositories carry by now are skipped. Split packages are listed by their
  package base.
- `build-packages.sh` builds everything in `build-order.txt` (or the
  packages given as arguments) whose version isn't in the repository yet,
  signs it and adds it to `repo/x86_64`. The kernel takes 30 to 90 minutes.
- `publish.sh` uploads new or changed packages and the database to the release and
  deletes assets of versions that are no longer in the repository.
- `build-iso.sh` uses the local repository if it exists (`--remote` for the
  published one). Before building, it checks that every package in
  `iso/packages.x86_64` and in the installer's package lists
  (`pacstrap.conf`, `netinstall.yaml`) exists in a repository.

## Testing the ISO

In a VM with UEFI firmware, for example GNOME Boxes or:

```sh
qemu-system-x86_64 -enable-kvm -m 8G -cdrom iso/out/lunar-*.iso \
    -bios /usr/share/edk2/x64/OVMF.4m.fd
```

The installer writes its log to `~/lunar-install.log` in the live session.

## Debug packages

Arch's `makepkg.conf` builds a `<name>-debug` package next to every package.
Lunar doesn't ship them: the build scripts turn the option off in the build
chroot, and remove the debug packages of earlier builds from `repo/x86_64`
the next time `build-aur.sh` or `build-packages.sh` runs. Run
`scripts/publish.sh` afterwards to delete them from the release as well.

## Updating components

| Component | Change | Then |
|---|---|---|
| Kernel | `_version` in `packages/linux-lunar/lunar-distro.cfg`, `_commit` in its `prepare.sh` | `scripts/build-packages.sh linux-lunar` |
| Elara, ananicy-cpp, AnanicyConfigurator, PipewireSimpleConfigurator | `_commit` in the package's PKGBUILD | `scripts/build-packages.sh <name>` |
| Settings | the files and `pkgver` in [lunar-settings](https://github.com/WhitePeace36/lunar-settings), then `_commit` in `packages/lunar-settings/prepare.sh` | `scripts/build-packages.sh lunar-settings` |
| ananicy rules | `_commit` in `packages/lunar-ananicy-rules/PKGBUILD` | `scripts/build-packages.sh lunar-ananicy-rules` |
| Calamares | `pkgver` and `_commit` (a release tag) in `packages/lunar-calamares/PKGBUILD`; compare upstream's module configs with `config/modules` | `scripts/build-packages.sh lunar-calamares` |
| AUR packages | nothing | `scripts/build-aur.sh` (rebuilds what changed) |
| ISO profile | compare `iso/` with a newer archiso `configs/releng` | `scripts/build-iso.sh` |

Run `scripts/publish.sh` after every build. Installed systems get the new
versions with `pacman -Syu`.
