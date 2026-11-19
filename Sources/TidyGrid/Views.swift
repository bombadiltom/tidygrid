import SwiftUI

/// A small picture of a layout: the grid with the filled area highlighted.
struct LayoutIcon: View {
    let layout: GridLayout
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            let inner = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            let target = layout.frame(in: inner).insetBy(dx: 1, dy: 1)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(highlighted ? 0.16 : 0.07))
                Path { p in
                    for c in 1..<max(layout.columns, 1) {
                        let x = inner.minX + inner.width * CGFloat(c) / CGFloat(layout.columns)
                        p.move(to: CGPoint(x: x, y: inner.minY))
                        p.addLine(to: CGPoint(x: x, y: inner.maxY))
                    }
                    for r in 1..<max(layout.rows, 1) {
                        let y = inner.minY + inner.height * CGFloat(r) / CGFloat(layout.rows)
                        p.move(to: CGPoint(x: inner.minX, y: y))
                        p.addLine(to: CGPoint(x: inner.maxX, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(highlighted ? 1 : 0.7))
                    .frame(width: max(target.width, 1), height: max(target.height, 1))
                    .offset(x: target.minX, y: target.minY)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.15),
                              lineWidth: highlighted ? 2 : 0.5)
        )
        .scaleEffect(highlighted ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}

/// A grid you drag across to pick an area. Used by the layout editor and by Quick Layout.
struct GridSelector: View {
    let columns: Int
    let rows: Int
    @Binding var selection: GridRect?
    var onCommit: ((GridRect) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(columns)
            let ch = geo.size.height / CGFloat(rows)
            let cell = { (p: CGPoint) -> (Int, Int) in
                (min(max(Int(p.x / cw), 0), columns - 1), min(max(Int(p.y / ch), 0), rows - 1))
            }

            ZStack(alignment: .topLeading) {
                ForEach(0..<(columns * rows), id: \.self) { i in
                    let c = i % columns
                    let r = i / columns
                    let selected = selection?.contains(column: c, row: r) ?? false
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
                        .frame(width: max(cw - 4, 1), height: max(ch - 4, 1))
                        .offset(x: CGFloat(c) * cw + 2, y: CGFloat(r) * ch + 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let (c0, r0) = cell(v.startLocation)
                        let (c1, r1) = cell(v.location)
                        selection = GridRect(x: min(c0, c1), y: min(r0, r1),
                                             width: abs(c1 - c0) + 1, height: abs(r1 - r0) + 1)
                    }
                    .onEnded { _ in
                        if let s = selection { onCommit?(s) }
                    }
            )
        }
    }
}
