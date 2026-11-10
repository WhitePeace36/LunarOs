// Lunar: the Lunar logo on the application launcher ("start menu" button)
// instead of the KDE logo.
//
// Plasma runs every script in this folder once per user (it records them in
// ~/.config/plasmashellrc, [Updates] performed), right after the panels are
// loaded or, at the first login, created from the default layout. Only
// launchers that still show a stock icon are changed, so an icon the user
// picked is kept, and the user can pick another one afterwards as usual
// (right click on the launcher > Configure).
//
// The icon is /usr/share/icons/hicolor/scalable/apps/start-here-lunar.svg.

const lunarIcon = "start-here-lunar";
const launchers = ["org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.kickerdash"];
const stockIcons = ["", "start-here-kde-symbolic", "start-here-kde", "start-here-symbolic", "start-here"];

const containments = desktops().concat(panels());
for (var i in containments) {
    const widgets = containments[i].widgets();
    for (var j in widgets) {
        const widget = widgets[j];
        if (launchers.indexOf(widget.type) === -1) {
            continue;
        }
        widget.currentConfigGroup = ["General"];
        if (stockIcons.indexOf(String(widget.readConfig("icon", ""))) !== -1) {
            widget.writeConfig("icon", lunarIcon);
            widget.reloadConfig();
        }
    }
}
