import AppKit
import SwiftUI

final class PanelModel: ObservableObject {
    @Published var layouts: [GridLayout] = []
    @Published var hovered: UUID?
    @Published var iconSize: CGSize = CGSize(width: 72, height: 45)
    @Published var vertical = false
}

private enum Metrics {
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 10
    static let margin: CGFloat = 40
}

private struct PanelView: View {
    @ObservedObject var model: PanelModel

    private var icons: some View {
        ForEach(model.layouts) { layout in
            LayoutIcon(layout: layout, highlighted: model.hovered == layout.id)
                .frame(width: model.iconSize.width, height: model.iconSize.height)
        }
    }

    var body: some View {
        Group {
            if model.vertical {
                VStack(spacing: Metrics.spacing) { icons }
            } else {
                HStack(spacing: Metrics.spacing) { icons }
            }
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// The pop-up row of layout icons shown while a window is dragged, plus the
/// translucent preview of where the window will land.
final class LayoutPanel {
    let model = PanelModel()
    private let panel: NSPanel
    private let preview: NSPanel
    private(set) var screen: NSScreen?

    var isVisible: Bool { panel.isVisible }

    var hoveredLayout: GridLayout? {
        model.layouts.first { $0.id == model.hovered }
    }

    init() {
        panel = LayoutPanel.makeOverlayPanel(level: .popUpMenu)
        let host = NSHostingView(rootView: PanelView(model: model))
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        panel.contentView = host
        panel.hasShadow = true

        preview = LayoutPanel.makeOverlayPanel(level: NSWindow.Level(NSWindow.Level.popUpMenu.rawValue - 1))
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        box.layer?.borderWidth = 2
        box.layer?.cornerRadius = 12
        preview.contentView = box
    }

    private static func makeOverlayPanel(level: NSWindow.Level) -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = level
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }

    func show(on screen: NSScreen) {
        let prefs = AppSettings.shared.prefs
        self.screen = screen
        model.layouts = prefs.layouts
        model.hovered = nil
        model.vertical = prefs.position == .left || prefs.position == .right
        guard !prefs.layouts.isEmpty else { hide(); return }

        let vis = screen.visibleFrame
        let n = CGFloat(prefs.layouts.count)
        let aspect = vis.height / vis.width
        let pad = Metrics.padding, sp = Metrics.spacing

        // Shrink the icons when they would not fit on the screen.
        var w = CGFloat(prefs.iconSize)
        if model.vertical {
            let maxH = vis.height - 2 * Metrics.margin
            let h = w * aspect
            if n * h + (n - 1) * sp + 2 * pad > maxH {
                w = ((maxH - 2 * pad - (n - 1) * sp) / n) / aspect
            }
        } else {
            let maxW = vis.width - 2 * Metrics.margin
            if n * w + (n - 1) * sp + 2 * pad > maxW {
                w = (maxW - 2 * pad - (n - 1) * sp) / n
            }
        }
        w = max(w.rounded(), 20)
        let h = (w * aspect).rounded()
        model.iconSize = CGSize(width: w, height: h)

        let size = model.vertical
            ? CGSize(width: w + 2 * pad, height: n * h + (n - 1) * sp + 2 * pad)
            : CGSize(width: n * w + (n - 1) * sp + 2 * pad, height: h + 2 * pad)

        var origin = CGPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2)
        switch prefs.position {
        case .top: origin.y = vis.maxY - Metrics.margin - size.height
        case .bottom: origin.y = vis.minY + Metrics.margin
        case .left: origin.x = vis.minX + Metrics.margin
        case .right: origin.x = vis.maxX - Metrics.margin - size.width
        case .center: break
        }

        panel.setFrame(CGRect(origin: origin, size: size).integral, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        preview.orderOut(nil)
        model.hovered = nil
        screen = nil
    }

    /// Updates the highlighted icon for a mouse location in AppKit coordinates.
    func updateHover(mouse: CGPoint) {
        guard isVisible, let screen else { return }
        let f = panel.frame
        var hovered: UUID?
        if f.insetBy(dx: -8, dy: -8).contains(mouse) {
            let pad = Metrics.padding, sp = Metrics.spacing
            let along = model.vertical ? (f.maxY - mouse.y) : (mouse.x - f.minX)
            let step = (model.vertical ? model.iconSize.height : model.iconSize.width) + sp
            let i = Int(((along - pad + sp / 2) / step).rounded(.down))
            let clamped = min(max(i, 0), model.layouts.count - 1)
            hovered = model.layouts.indices.contains(clamped) ? model.layouts[clamped].id : nil
        }
        if model.hovered != hovered { model.hovered = hovered }

        if AppSettings.shared.prefs.showPreview, let layout = hoveredLayout {
            let target = NSScreen.flip(layout.frame(in: screen.axVisibleFrame))
            preview.setFrame(target.insetBy(dx: 4, dy: 4), display: true)
            preview.orderFrontRegardless()
        } else {
            preview.orderOut(nil)
        }
    }
}
