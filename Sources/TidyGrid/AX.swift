import AppKit
import ApplicationServices

/// Small helpers around the Accessibility API. All coordinates here use the
/// Accessibility convention: origin at the top-left of the primary screen, y grows downwards.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static let systemWide: AXUIElement = {
        let e = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(e, 0.25)
        return e
    }()

    // MARK: Attribute access

    private static func value(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v
    }

    private static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = value(e, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func role(_ e: AXUIElement) -> String? {
        value(e, kAXRoleAttribute) as? String
    }

    static func pid(_ e: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(e, &pid) == .success ? pid : nil
    }

    // MARK: Finding windows

    /// The window under a point, or nil when there is none.
    static func window(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var e = hit else { return nil }
        for _ in 0..<40 {
            if role(e) == kAXWindowRole as String { return e }
            if let w = element(e, kAXWindowAttribute) { return w }
            guard let parent = element(e, kAXParentAttribute) else { return nil }
            e = parent
        }
        return nil
    }

    /// The focused window of the frontmost app.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        return focusedWindow(pid: app.processIdentifier)
    }

    /// The focused window of the given app.
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        return element(axApp, kAXFocusedWindowAttribute) ?? element(axApp, kAXMainWindowAttribute)
    }

    // MARK: Geometry

    static func position(_ w: AXUIElement) -> CGPoint? {
        guard let v = value(w, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ w: AXUIElement) -> CGSize? {
        guard let v = value(w, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    static func frame(_ w: AXUIElement) -> CGRect? {
        guard let p = position(w), let s = size(w) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        // Some apps (Chrome, Electron) animate frame changes while "enhanced UI" is on,
        // which makes the size step land in the wrong place. Switch it off for the move.
        var app: AXUIElement?
        var enhanced = false
        if let pid = pid(w) {
            let a = AXUIElementCreateApplication(pid)
            if let v = value(a, "AXEnhancedUserInterface") as? Bool, v {
                enhanced = true
                app = a
                AXUIElementSetAttributeValue(a, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
        }

        var origin = r.origin
        var size = r.size
        let pos = AXValueCreate(.cgPoint, &origin)!
        let sz = AXValueCreate(.cgSize, &size)!
        // Resize before moving: moving a big window first can leave it hanging over onto a
        // neighbouring screen, and macOS then refuses or clamps the resize. Resize again after the
        // move, because the first resize may have been limited by the screen the window started on.
        // Repeat once if the app still nudged the window (it may just have a minimum size).
        for _ in 0..<2 {
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sz)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pos)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sz)
            guard let f = frame(w) else { break }
            if abs(f.minX - r.minX) <= 1, abs(f.minY - r.minY) <= 1,
               abs(f.width - r.width) <= 1, abs(f.height - r.height) <= 1 { break }
        }

        // A window with a minimum size larger than the target can end up past the screen edge
        // (a Right Third that cannot get that narrow). Slide it back onto the screen.
        if let f = frame(w),
           let screen = NSScreen.screens.first(where: { $0.axFrame.contains(CGPoint(x: r.midX, y: r.midY)) }) {
            let vis = screen.axVisibleFrame
            var p = f.origin
            if f.maxX > vis.maxX { p.x = max(vis.minX, vis.maxX - f.width) }
            if f.maxY > vis.maxY { p.y = max(vis.minY, vis.maxY - f.height) }
            if p != f.origin {
                var o = p
                AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &o)!)
            }
        }

        if enhanced, let app {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// The screen that shows the largest part of the window.
    static func screen(of w: AXUIElement) -> NSScreen? {
        guard let f = frame(w) else { return nil }
        return NSScreen.screens.max { a, b in
            a.axFrame.intersection(f).area < b.axFrame.intersection(f).area
        }
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

extension NSScreen {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Converts between AppKit (bottom-left origin) and Accessibility (top-left origin) rects.
    /// The conversion is its own inverse.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    var axFrame: CGRect { NSScreen.flip(frame) }
    var axVisibleFrame: CGRect { NSScreen.flip(visibleFrame) }

    static var withMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }

    /// The mouse location in Accessibility coordinates.
    static var axMouseLocation: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
