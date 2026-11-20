import Foundation
import Combine

/// A rectangle on a grid, measured in cells. Row 0 is the top row.
struct GridRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func contains(column: Int, row: Int) -> Bool {
        column >= x && column < x + width && row >= y && row < y + height
    }
}

/// One saved layout: a grid size plus the area of it the window fills.
struct GridLayout: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var columns: Int
    var rows: Int
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var rect: GridRect {
        get { GridRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.x; y = newValue.y
            width = newValue.width; height = newValue.height
            self = clamped()
        }
    }

    /// Keeps the area inside the grid after the grid size changed.
    func clamped() -> GridLayout {
        var l = self
        l.columns = min(max(l.columns, 1), 24)
        l.rows = min(max(l.rows, 1), 24)
        l.x = min(max(l.x, 0), l.columns - 1)
        l.y = min(max(l.y, 0), l.rows - 1)
        l.width = min(max(l.width, 1), l.columns - l.x)
        l.height = min(max(l.height, 1), l.rows - l.y)
        return l
    }

    /// The target frame inside `area`. Both use a top-left origin with y growing downwards.
    func frame(in area: CGRect) -> CGRect {
        let cw = area.width / CGFloat(columns)
        let ch = area.height / CGFloat(rows)
        let minX = (area.minX + cw * CGFloat(x)).rounded()
        let minY = (area.minY + ch * CGFloat(y)).rounded()
        let maxX = (area.minX + cw * CGFloat(x + width)).rounded()
        let maxY = (area.minY + ch * CGFloat(y + height)).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static let defaults: [GridLayout] = [
        GridLayout(name: "Left Third", columns: 3, rows: 1, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Left Half", columns: 2, rows: 1, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Left Two Thirds", columns: 3, rows: 1, x: 0, y: 0, width: 2, height: 1),
        GridLayout(name: "Full Screen", columns: 1, rows: 1, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Right Two Thirds", columns: 3, rows: 1, x: 1, y: 0, width: 2, height: 1),
        GridLayout(name: "Right Half", columns: 2, rows: 1, x: 1, y: 0, width: 1, height: 1),
        GridLayout(name: "Right Third", columns: 3, rows: 1, x: 2, y: 0, width: 1, height: 1),
    ].sortedLeftToRight()

    /// Layouts that used to be defaults. Saved lists from before version 3 drop them once.
    static let retiredDefaults: [GridLayout] = [
        GridLayout(name: "Center", columns: 6, rows: 6, x: 1, y: 1, width: 4, height: 4),
        GridLayout(name: "Top Left", columns: 2, rows: 2, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Bottom Left", columns: 2, rows: 2, x: 0, y: 1, width: 1, height: 1),
        GridLayout(name: "Top Right", columns: 2, rows: 2, x: 1, y: 0, width: 1, height: 1),
        GridLayout(name: "Bottom Right", columns: 2, rows: 2, x: 1, y: 1, width: 1, height: 1),
    ]

    /// Position and size as fractions of the screen: left, top, width, height.
    var fractions: [Double] {
        [Double(x) / Double(columns), Double(y) / Double(rows),
         Double(width) / Double(columns), Double(height) / Double(rows)]
    }

    /// True when both layouts cover the same part of the screen, even with different grids.
    func coversSameArea(as other: GridLayout) -> Bool {
        zip(fractions, other.fractions).allSatisfy { abs($0 - $1) < 0.001 }
    }
}

extension Array where Element == GridLayout {
    /// Orders layouts by where they sit on the screen: by horizontal center first,
    /// then top to bottom, then larger before smaller.
    func sortedLeftToRight() -> [GridLayout] {
        func key(_ l: GridLayout) -> [Double] {
            let f = l.fractions
            return [f[0] + f[2] / 2, f[1] + f[3] / 2, -(f[2] * f[3])]
        }
        return sorted { a, b in
            for (ka, kb) in zip(key(a), key(b)) where abs(ka - kb) > 0.001 {
                return ka < kb
            }
            return false
        }
    }
}

enum PanelPosition: String, Codable, CaseIterable, Identifiable {
    case top, bottom, left, right, center, followMouse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .followMouse: "Follow Mouse"
        case .top: "Top"
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        case .center: "Center"
        }
    }
}

enum OptionKeyMode: String, Codable, CaseIterable, Identifiable {
    case optionHides, optionShows, ignore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .optionHides: "Hold Option to hide the icons"
        case .optionShows: "Show icons only while holding Option"
        case .ignore: "Always show the icons"
        }
    }
}

struct Prefs: Codable, Equatable {
    var layouts: [GridLayout] = GridLayout.defaults
    var iconSize: Double = 72
    var position: PanelPosition = .top
    var optionMode: OptionKeyMode = .optionHides
    var showPreview: Bool = true
    var quickColumns: Int = 6
    var quickRows: Int = 4
    var layoutShortcuts: Bool = false
    /// Bumped when new default layouts ship, so they are merged into saved settings once.
    var defaultsVersion: Int = Prefs.currentDefaultsVersion

    static let currentDefaultsVersion = 3

    init() {}

    // Missing keys fall back to the defaults, so new settings never wipe old ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Prefs()
        layouts = try c.decodeIfPresent([GridLayout].self, forKey: .layouts) ?? d.layouts
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        position = try c.decodeIfPresent(PanelPosition.self, forKey: .position) ?? d.position
        optionMode = try c.decodeIfPresent(OptionKeyMode.self, forKey: .optionMode) ?? d.optionMode
        showPreview = try c.decodeIfPresent(Bool.self, forKey: .showPreview) ?? d.showPreview
        quickColumns = try c.decodeIfPresent(Int.self, forKey: .quickColumns) ?? d.quickColumns
        quickRows = try c.decodeIfPresent(Int.self, forKey: .quickRows) ?? d.quickRows
        layoutShortcuts = try c.decodeIfPresent(Bool.self, forKey: .layoutShortcuts) ?? d.layoutShortcuts
        defaultsVersion = try c.decodeIfPresent(Int.self, forKey: .defaultsVersion) ?? 1
    }

    /// Brings a saved list up to the current defaults once: drops retired defaults,
    /// adds new ones it does not cover yet, and sorts it left to right.
    mutating func mergeNewDefaults() {
        guard defaultsVersion < Prefs.currentDefaultsVersion else { return }
        if defaultsVersion < 3 {
            layouts.removeAll { l in GridLayout.retiredDefaults.contains { l.coversSameArea(as: $0) } }
        }
        for d in GridLayout.defaults where !layouts.contains(where: { $0.coversSameArea(as: d) }) {
            layouts.append(d)
        }
        layouts = layouts.sortedLeftToRight()
        defaultsVersion = Prefs.currentDefaultsVersion
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let key = "prefs"

    @Published var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           var p = try? JSONDecoder().decode(Prefs.self, from: data) {
            let before = p
            p.mergeNewDefaults()
            prefs = p
            if p != before { save() }
        } else {
            prefs = Prefs()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
