# Branding

`lunar-logo.svg` is the master file of the Lunar logo. Exports of it are
used in:

| Where | Files |
|---|---|
| [lunar-settings](https://github.com/WhitePeace36/lunar-settings) | `files/usr/share/icons/hicolor/scalable/apps/lunar.svg`, `files/usr/share/icons/hicolor/*/apps/lunar.png`, `files/usr/share/pixmaps/lunar.svg` |
| Installer | `packages/lunar-calamares/branding/lunar/{logo,icon,welcome}.png` |
| Live ISO | `iso/airootfs/usr/share/icons/hicolor/scalable/apps/lunar.svg` |
| Application launcher (panel) | `packages/lunar-kde-settings/files/usr/share/icons/hicolor/scalable/apps/start-here-lunar.svg` |

After changing the master, regenerate these.

## Wallpapers

The `NN-name.png` files are Lunar's wallpapers. The package
`lunar-wallpapers` (`packages/lunar-wallpapers`) installs each one as the
Plasma wallpaper `/usr/share/wallpapers/lunar-<name>` (without the number and
without `busy-` or `lunar-`). After adding or changing one, raise `pkgrel` in
its PKGBUILD.

| Used as | File | Set in |
|---|---|---|
| Desktop wallpaper | `20-wordmark-lockup.png` | `packages/lunar-kde-settings/files/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/lunar_wallpaper.js` |
| Lock screen | `26-busy-moonlit-lake.png` | `packages/lunar-kde-settings/files/etc/xdg/kscreenlockerrc` |
| Login screen | `26-busy-moonlit-lake.png` | `packages/lunar-kde-settings/files/usr/lib/plasmalogin/plasmalogin.conf.d/50-lunar.conf` |
| Boot splash (Plymouth) | `20-wordmark-lockup.png`, its middle | `packages/lunar-plymouth-theme/watermark.png`, made by `make-splash.py` there |

## Colors

| Name | Hex |
|---|---|
| Ice | `#f2f8ff` |
| Frost | `#cfe6ff` |
| Sky | `#7cc4ff` |
| Blue | `#2f80ed` |
| Navy | `#0b1e3f` |
| Night | `#0d1626` |
