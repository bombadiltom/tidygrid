# TidyGrid

Menu bar app for macOS 12+ (Swift, AppKit + SwiftUI, no dependencies). Dragging a window by its title bar
pops up layout icons; dropping it on one snaps the window into that layout. A replacement for the retired
Window Tidy, so keep it small: no features beyond what the README lists unless asked.

## Layout

- `Sources/TidyGrid/`
  - `main.swift`, `AppDelegate.swift`: accessory app, status item menu, hot key registration
  - `DragWatcher.swift`: global mouse monitors; decides whether a drag moves a window (idle → pressed → probing → moving)
  - `LayoutPanel.swift`: the pop-up icon panel, its placement (incl. Follow Mouse), hit testing, drop preview
  - `AX.swift`: Accessibility helpers and `NSScreen` coordinate conversion
  - `Settings.swift`: `GridLayout`, `Prefs` (one JSON blob in UserDefaults), default layouts and their migration
  - `SettingsView.swift`, `Views.swift`, `QuickLayout.swift`, `HotKeys.swift` (Carbon hot keys), `SelfTest.swift`
- `Resources/Info.plist`: bundle id `app.tidygrid.TidyGrid`; `CFBundleShortVersionString` is the release version
- `build.sh`: the only build entry point (SwiftPM + manual .app bundle); `scripts/make-icon.swift` makes `AppIcon.icns`

## Build, run, ship

```bash
./build.sh                           # universal (arm64 + x86_64) build/TidyGrid.app
./build.sh install                   # replace /Applications/TidyGrid.app here and start it
./build.sh deploy macmini macmini2   # same on other Macs over SSH (both are Intel; macmini runs macOS 12)
./build.sh release                   # notarize, publish GitHub release vX.Y, bump + push the cask in bombadiltom/homebrew-tap
```

- `release` needs a clean tree pushed to origin/main, the "Developer ID Application" certificate and the
  notarytool keychain profile `BombadilTom`. Bump `CFBundleShortVersionString` first; the same version re-uploads.
- All builds are signed with the same certificate (Developer ID, else Apple Development). Keep it that way:
  the Accessibility grant is tied to the signature, so changing identities forces users to re-grant it.
- The x86_64 deprecation warning from the build is expected; the minis are Intel.

## Conventions

- GitHub: always the `bombadiltom` account, never `tlorenz-reply` (the active gh account on the main Mac).
  Use `GH_TOKEN="$(gh auth token --user bombadiltom)"` per gh call; git pushes go over SSH. The repo is public.
- Keep macOS 12 compatible: guard newer APIs with `#available` (as done for `formStyle(.grouped)`,
  `NSHostingView.sizingOptions`, `SMAppService`). No `AnyLayout`, `LabeledContent` or other macOS 13+ API unguarded.
- Swift 5 language mode (tools version 5.9); the hot key handler relies on it.
- Coordinates: Accessibility uses a top-left origin on the primary screen, AppKit a bottom-left one.
  Convert only via `NSScreen.flip` / `axFrame` / `axVisibleFrame`. `GridLayout.frame(in:)` works in top-left space.
- `AX.setFrame` resizes, moves, then resizes again. Do not reorder: moving first breaks right-side layouts
  when a neighbouring screen is involved.
- Changing default layouts: edit `GridLayout.defaults`, bump `Prefs.currentDefaultsVersion` and extend
  `mergeNewDefaults()` so saved lists are migrated once (retired defaults go in `GridLayout.retiredDefaults`).
- Commit and push only when asked.

## Testing

There are no unit tests. Verify window placement with the self-test, which needs the installed app
launched via `open` (TidyGrid has Accessibility access; a binary started from a shell is checked against
the terminal's access instead):

```bash
open ~/Downloads && sleep 2   # a Finder window to move around
pkill -x TidyGrid; open -a /Applications/TidyGrid.app --args --self-test com.apple.finder
sleep 25 && cat ~/Library/Logs/TidyGrid-selftest.log   # the app keeps running normally afterwards
```

It runs the window through every layout on every screen and logs wanted vs. actual frames. Expected
"failures": Finder cannot get narrower than 520 pt, so thirds on a small screen are a few points off.
Drag interaction itself cannot be automated from the shell; ask the user to try it.
