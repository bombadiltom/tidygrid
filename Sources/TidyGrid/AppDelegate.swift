import AppKit
import Carbon
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = DragWatcher()
    private let quickLayout = QuickLayoutController()
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "TidyGrid")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        watcher.start()

        AppSettings.shared.$prefs
            .map { [$0.layouts.map(\.id).description, $0.layoutShortcuts.description] }
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.registerHotKeys() } }
            .store(in: &cancellables)

        if !AX.isTrusted {
            AX.promptForTrust()
            showSettings()
        }
    }

    // MARK: Hot keys

    private func registerHotKeys() {
        let hk = HotKeys.shared
        hk.removeAll()
        hk.register(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
            self?.quickLayout.show()
        }
        let prefs = AppSettings.shared.prefs
        guard prefs.layoutShortcuts else { return }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, layout) in prefs.layouts.prefix(9).enumerated() {
            let id = layout.id
            hk.register(keyCode: digits[i], modifiers: controlKey | optionKey | cmdKey) {
                // Look the layout up again so edits made since registering are used.
                guard let layout = AppSettings.shared.prefs.layouts.first(where: { $0.id == id }),
                      let w = AX.focusedWindow(), let screen = AX.screen(of: w) else { return }
                AX.setFrame(w, layout.frame(in: screen.axVisibleFrame))
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !AX.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(.separator())
        }
        let quick = item("Quick Layout", #selector(showQuickLayout))
        quick.keyEquivalent = " "
        quick.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(quick)
        menu.addItem(item("Move Active Window to This Screen", #selector(moveToMouseScreen)))
        menu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(item("Quit TidyGrid", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func grantAccess() {
        AX.promptForTrust()
        AX.openAccessibilitySettings()
    }

    @objc private func showQuickLayout() {
        // The menu does not take focus from the active app, so its window is still the target.
        quickLayout.show()
    }

    /// Brings the active window onto the screen with the mouse, for example after
    /// a display was unplugged or switched off.
    @objc private func moveToMouseScreen() {
        guard let w = AX.focusedWindow(), let frame = AX.frame(w) else { NSSound.beep(); return }
        let vis = NSScreen.withMouse.axVisibleFrame
        let size = CGSize(width: min(frame.width, vis.width), height: min(frame.height, vis.height))
        let origin = CGPoint(x: (vis.midX - size.width / 2).rounded(), y: (vis.midY - size.height / 2).rounded())
        AX.setFrame(w, CGRect(origin: origin, size: size))
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "TidyGrid Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
