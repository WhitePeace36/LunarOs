// Lunar: panels that don't float. Plasma's default panel floats (a gap
// between the panel and the screen edge); Lunar's sits on the edge.
//
// Plasma runs every script in this folder once per user, right after the
// panels are loaded or, at the first login, created from the default layout.
// So this happens once: the user can turn floating back on afterwards as
// usual (right click on the panel > Show Panel Configuration > Floating).

const allPanels = panels();
for (var i in allPanels) {
    if (allPanels[i].floating) {
        allPanels[i].floating = false;
    }
}
