import AppKit
import SwiftUI

private struct QuickLayoutView: View {
    let columns: Int
    let rows: Int
    let aspect: CGFloat
    let onPick: (GridRect) -> Void
    @State private var selection: GridRect?

    var body: some View {
        VStack(spacing: 10) {
            Text("Drag across the grid to place the window. Esc cancels.")
                .font(.callout)
                .foregroundStyle(.secondary)
            GridSelector(columns: columns, rows: rows, selection: $selection, onCommit: onPick)
                .aspectRatio(aspect, contentMode: .fit)
        }
        .padding(16)
        .padding(.top, 12)
    }
}

/// Applies a one-off layout without saving it: a grid window opens, you drag across it, done.
final class QuickLayoutController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?

    func show(for target: AXUIElement? = AX.focusedWindow()) {
        close()
        guard let target, let pid = AX.pid(target) else { NSSound.beep(); return }
        let screen = AX.screen(of: target) ?? NSScreen.withMouse
        let prefs = AppSettings.shared.prefs
        let vis = screen.visibleFrame
        let aspect = vis.width / vis.height

        let width: CGFloat = 520
        let height = width / aspect + 70
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = false
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: QuickLayoutView(
            columns: prefs.quickColumns, rows: prefs.quickRows, aspect: aspect,
            onPick: { [weak self] rect in
                guard let self else { return }
                let layout = GridLayout(name: "", columns: prefs.quickColumns, rows: prefs.quickRows,
                                        x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                self.close()
                AX.setFrame(target, layout.frame(in: screen.axVisibleFrame))
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            }))
        w.setFrameOrigin(CGPoint(x: vis.midX - width / 2, y: vis.midY - height / 2))
        window = w

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.close()
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        let w = window
        window = nil
        w?.delegate = nil
        w?.close()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
    func windowWillClose(_ notification: Notification) { close() }
}
