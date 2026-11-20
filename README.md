# TidyGrid

A small menu bar app for macOS 12+ that works like the retired Window Tidy:
drag any window by its title bar, a row of layout icons pops up, drop the window on one and it snaps into place.

- **Layouts**: as many as you like, each with its own grid. Edit them in Settings → Layouts (drag across the grid to choose the area).
- **Multiple screens**: the icons follow the cursor to whichever screen you drag onto, and the layout is applied there.
- **Follow Mouse**: optionally the icons pop up right below the cursor instead of at a screen edge: to its right on the left third of the screen, centered in the middle, to its left on the right third.
- **Option key**: hold it to hide the icons while dragging (or switch to "show only with Option").
- **Quick Layout** (⌃⌥Space or the menu): drag across a grid to place the active window once, without saving a layout.
- **Move Active Window to This Screen**: rescues windows stuck on a disconnected display.
- **Shortcuts** (optional): ⌃⌥⌘1–9 apply the first nine layouts.

TidyGrid needs Accessibility access (System Settings → Privacy & Security → Accessibility).

## Install

```bash
brew tap bombadiltom/tap
brew trust --cask bombadiltom/tap/tidygrid
brew install --cask bombadiltom/tap/tidygrid
```

Or download `TidyGrid-<version>.zip` from [Releases](https://github.com/bombadiltom/tidygrid/releases) and move the app to Applications.
The app is signed but not notarized, so on first launch macOS may ask you to allow it under
System Settings → Privacy & Security → "Open Anyway".

Then allow TidyGrid under Accessibility. Layouts and settings are per Mac.

## Build

```bash
./build.sh                          # builds build/TidyGrid.app (Apple silicon + Intel)
./build.sh install                  # also copies it to /Applications and starts it
./build.sh deploy macmini macmini2  # installs and starts it on other Macs over SSH
./build.sh release                  # zips it, publishes a GitHub release and prints the cask sha256 (needs a clean, pushed HEAD)
```

`release` uses the version in `Resources/Info.plist`. Bump `CFBundleShortVersionString` for a new release;
re-running with the same version replaces the zip in the existing release.

The app is signed with your "Apple Development" certificate when one exists, so the Accessibility permission survives rebuilds.

## Diagnostics

`/Applications/TidyGrid.app/Contents/MacOS/TidyGrid --self-test com.apple.finder` moves Finder's front window
through every layout on every screen and writes wanted vs. actual frames to `~/Library/Logs/TidyGrid-selftest.log`.
