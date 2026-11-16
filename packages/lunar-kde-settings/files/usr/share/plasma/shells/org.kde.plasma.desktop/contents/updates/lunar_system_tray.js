// Lunar: system tray entries (right click on the tray > Configure System
// Tray > Entries):
//
//   Weather Report    Disabled
//   Keyboard Layout   Disabled
//   Clipboard         Always shown
//   Notifications     Always hidden (in the tray's popup; notification
//                     popups still appear)
//
// Plasma runs every script in this folder once per user, right after the
// panels are loaded or, at the first login, created from the default layout.
// So this happens once: the user can change the entries afterwards as usual.
//
// The tray keeps its entries in its General config group: extraItems are
// the enabled plasmoids, knownItems the ones the tray has seen (a plasmoid
// that is enabled by default but not known yet is enabled again),
// shownItems and hiddenItems the "Always shown/hidden" ones. In Plasma 6
// the tray widget in the panel holds them itself; older layouts kept them in
// a separate containment (SystrayContainmentId).

const disabled = ["org.kde.plasma.weather", "org.kde.plasma.keyboardlayout"];
const alwaysShown = ["org.kde.plasma.clipboard"];
const alwaysHidden = ["org.kde.plasma.notifications"];

function readList(containment, key) {
    const value = containment.readConfig(key, []);
    if (typeof value === "string") {
        return value === "" ? [] : value.split(",");
    }
    const list = [];
    for (var i = 0; i < value.length; i++) {
        list.push(String(value[i]));
    }
    return list;
}

function without(list, items) {
    return list.filter(function (item) { return items.indexOf(item) === -1; });
}

function withAll(list, items) {
    const result = list.slice();
    for (var i in items) {
        if (result.indexOf(items[i]) === -1) {
            result.push(items[i]);
        }
    }
    return result;
}

function configureTray(tray) {
    tray.currentConfigGroup = ["General"];
    var extra = readList(tray, "extraItems");
    var known = readList(tray, "knownItems");
    var shown = readList(tray, "shownItems");
    var hidden = readList(tray, "hiddenItems");

    // disabled: not enabled, but known, so the tray doesn't enable it again
    extra = without(extra, disabled);
    known = withAll(known, disabled);
    shown = without(shown, disabled);
    hidden = without(hidden, disabled);

    // always shown / always hidden: enabled, and in one of the two lists
    extra = withAll(extra, alwaysShown.concat(alwaysHidden));
    known = withAll(known, alwaysShown.concat(alwaysHidden));
    shown = withAll(without(shown, alwaysHidden), alwaysShown);
    hidden = withAll(without(hidden, alwaysShown), alwaysHidden);

    tray.writeConfig("extraItems", extra);
    tray.writeConfig("knownItems", known);
    tray.writeConfig("shownItems", shown);
    tray.writeConfig("hiddenItems", hidden);
    tray.reloadConfig();
}

const containments = desktops().concat(panels());
for (var i in containments) {
    const widgets = containments[i].widgets();
    for (var j in widgets) {
        if (widgets[j].type !== "org.kde.plasma.systemtray") {
            continue;
        }
        const trayId = widgets[j].readConfig("SystrayContainmentId");
        const tray = trayId ? desktopById(trayId) : null;
        configureTray(tray ? tray : widgets[j]);
    }
}
