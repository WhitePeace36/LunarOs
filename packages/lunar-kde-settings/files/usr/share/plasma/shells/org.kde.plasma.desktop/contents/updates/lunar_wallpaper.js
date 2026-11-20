// Lunar: the Lunar wallpaper "Wordmark Lockup" (branding/20-wordmark-lockup.png,
// package lunar-wallpapers) on the desktop instead of Plasma's "Next".
//
// Plasma runs every script in this folder once per user, right after the
// desktops are loaded or, at the first login, created from the default
// layout. Only desktops that still show Plasma's default wallpaper are
// changed, so a wallpaper the user picked is kept, and the user can pick
// another one afterwards as usual (right click on the desktop > Desktop and
// Wallpaper). The lock screen shows the same wallpaper (set in
// /etc/xdg/kscreenlockerrc), and so does the login screen
// (/usr/lib/plasmalogin/plasmalogin.conf.d/50-lunar.conf).

const lunarWallpaper = "file:///usr/share/wallpapers/lunar-wordmark-lockup/";
// unset (Plasma's default) or Plasma's default written out
const stockWallpaper = /^((file:\/\/)?\/usr\/share\/wallpapers\/Next\/?)?$/;

const allDesktops = desktops();
for (var i in allDesktops) {
    const desktop = allDesktops[i];
    if (desktop.wallpaperPlugin !== "org.kde.image") {
        continue;
    }
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    if (stockWallpaper.test(String(desktop.readConfig("Image", "")))) {
        desktop.writeConfig("Image", lunarWallpaper);
        desktop.reloadConfig();
    }
}
