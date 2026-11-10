// Lunar: the applications pinned to the task manager.
//
// Plasma's default panel pins System Settings, Discover, the file manager
// and the browser. Lunar pins Konsole, the file manager, LibreWolf, Lutris
// and Steam instead. Applications that aren't installed are left out (the
// software page of the installer can untick them, and the live ISO has
// neither of the three last ones): their launcher would be an empty icon
// that does nothing. Without LibreWolf the default browser takes its place.
//
// Plasma runs every script in this folder once per user, right after the
// panels are loaded or created from the default layout. A task manager whose
// launchers the user already changed only loses launchers of applications
// that aren't installed.

const taskManagers = ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"];
// the task manager's own default, in use while its configuration has no list
const plasmaLaunchers = "applications:systemsettings.desktop,applications:org.kde.discover.desktop,preferred://filemanager,preferred://browser";
const lunarLaunchers = [
    "applications:org.kde.konsole.desktop",
    "preferred://filemanager",
    "applications:librewolf.desktop",
    "applications:net.lutris.Lutris.desktop",
    "applications:steam.desktop"
];
const browser = "applications:librewolf.desktop";

function installed(launcher) {
    const app = /^applications:(.+\.desktop)$/.exec(launcher);
    return app === null || applicationExists(app[1]);
}

const containments = desktops().concat(panels());
for (var i in containments) {
    const widgets = containments[i].widgets();
    for (var j in widgets) {
        const widget = widgets[j];
        if (taskManagers.indexOf(widget.type) === -1) {
            continue;
        }
        widget.currentConfigGroup = ["General"];
        const current = String(widget.readConfig("launchers", plasmaLaunchers));
        var wanted = current.split(",");
        if (current === plasmaLaunchers) {
            wanted = lunarLaunchers.slice();
            if (!installed(browser)) {
                wanted[wanted.indexOf(browser)] = "preferred://browser";
            }
        }
        const launchers = [];
        for (var k in wanted) {
            const launcher = wanted[k].trim();
            if (launcher !== "" && installed(launcher)) {
                launchers.push(launcher);
            }
        }
        if (launchers.join(",") !== current) {
            widget.writeConfig("launchers", launchers);
            widget.reloadConfig();
        }
    }
}
