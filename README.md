# TidyGrid

A small menu bar app for macOS 14+ that works like the retired Window Tidy:
drag any window by its title bar, a row of layout icons pops up, drop the window on one and it snaps into place.

- **Layouts**: as many as you like, each with its own grid. Edit them in Settings → Layouts (drag across the grid to choose the area).
- **Multiple screens**: the icons follow the cursor to whichever screen you drag onto, and the layout is applied there.
- **Option key**: hold it to hide the icons while dragging (or switch to "show only with Option").
- **Quick Layout** (⌃⌥Space or the menu): drag across a grid to place the active window once, without saving a layout.
- **Move Active Window to This Screen**: rescues windows stuck on a disconnected display.
- **Shortcuts** (optional): ⌃⌥⌘1–9 apply the first nine layouts.

TidyGrid needs Accessibility access (System Settings → Privacy & Security → Accessibility).

## Build

```bash
./build.sh           # builds build/TidyGrid.app
./build.sh install   # also copies it to /Applications and starts it
```

The app is signed with your "Apple Development" certificate when one exists, so the Accessibility permission survives rebuilds.
