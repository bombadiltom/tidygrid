import AppKit

/// Watches mouse drags system-wide. When a drag turns out to move a window,
/// the layout icons appear; dropping the window on one applies that layout.
final class DragWatcher {
    private enum Phase { case idle, pressed, probing, moving, ignored }

    let panel = LayoutPanel()
    private var monitors: [Any] = []
    private var phase = Phase.idle
    private var window: AXUIElement?
    private var startPosition: CGPoint?
    private var startSize: CGSize?
    private var lastProbe: TimeInterval = 0

    func start() {
        let add: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Void = { mask, handler in
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
                self.monitors.append(m)
            }
        }
        add(.leftMouseDown) { [weak self] _ in self?.mouseDown() }
        add(.leftMouseDragged) { [weak self] _ in self?.mouseDragged() }
        add(.leftMouseUp) { [weak self] _ in self?.mouseUp() }
        add(.flagsChanged) { [weak self] _ in
            if self?.phase == .moving { self?.updatePanel() }
        }
    }

    private func mouseDown() {
        reset()
        phase = .pressed
    }

    private func mouseDragged() {
        switch phase {
        case .pressed:
            // Find the window under the cursor only once a drag starts, so plain clicks cost nothing.
            guard AX.isTrusted,
                  let w = AX.window(at: NSScreen.axMouseLocation),
                  AX.pid(w) != getpid(),
                  let pos = AX.position(w), let size = AX.size(w) else {
                phase = .ignored
                return
            }
            window = w
            startPosition = pos
            startSize = size
            phase = .probing

        case .probing:
            // Is the window moving (a title bar drag), being resized, or not changing at all
            // (text selection, file drag)?
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastProbe > 0.03, let w = window else { return }
            lastProbe = now
            guard let pos = AX.position(w), let size = AX.size(w),
                  let p0 = startPosition, let s0 = startSize else { phase = .ignored; return }
            if abs(size.width - s0.width) > 1 || abs(size.height - s0.height) > 1 {
                phase = .ignored
            } else if abs(pos.x - p0.x) > 2 || abs(pos.y - p0.y) > 2 {
                phase = .moving
                updatePanel()
            }

        case .moving:
            updatePanel()

        case .idle, .ignored:
            break
        }
    }

    private func mouseUp() {
        defer { reset() }
        guard phase == .moving, panel.isVisible,
              let layout = panel.hoveredLayout, let screen = panel.screen, let w = window else { return }
        let target = layout.frame(in: screen.axVisibleFrame)
        // Let the window server finish the drag before we move the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AX.setFrame(w, target)
        }
    }

    private func updatePanel() {
        let optionDown = NSEvent.modifierFlags.contains(.option)
        let show: Bool
        switch AppSettings.shared.prefs.optionMode {
        case .optionHides: show = !optionDown
        case .optionShows: show = optionDown
        case .ignore: show = true
        }
        guard show else {
            if panel.isVisible { panel.hide() }
            return
        }
        // The icons follow the window onto whichever screen the cursor is on.
        let screen = NSScreen.withMouse
        if !panel.isVisible || panel.screen != screen {
            panel.show(on: screen, mouse: NSEvent.mouseLocation)
        }
        panel.updateHover(mouse: NSEvent.mouseLocation)
    }

    private func reset() {
        if panel.isVisible { panel.hide() }
        phase = .idle
        window = nil
        startPosition = nil
        startSize = nil
    }
}
