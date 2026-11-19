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
        GridLayout(name: "Left Half", columns: 2, rows: 1, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Right Half", columns: 2, rows: 1, x: 1, y: 0, width: 1, height: 1),
        GridLayout(name: "Full Screen", columns: 1, rows: 1, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Center", columns: 6, rows: 6, x: 1, y: 1, width: 4, height: 4),
        GridLayout(name: "Left Two Thirds", columns: 3, rows: 1, x: 0, y: 0, width: 2, height: 1),
        GridLayout(name: "Right Third", columns: 3, rows: 1, x: 2, y: 0, width: 1, height: 1),
        GridLayout(name: "Top Left", columns: 2, rows: 2, x: 0, y: 0, width: 1, height: 1),
        GridLayout(name: "Top Right", columns: 2, rows: 2, x: 1, y: 0, width: 1, height: 1),
        GridLayout(name: "Bottom Left", columns: 2, rows: 2, x: 0, y: 1, width: 1, height: 1),
        GridLayout(name: "Bottom Right", columns: 2, rows: 2, x: 1, y: 1, width: 1, height: 1),
    ]
}

enum PanelPosition: String, Codable, CaseIterable, Identifiable {
    case top, bottom, left, right, center
    var id: String { rawValue }
    var title: String {
        switch self {
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
           let p = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = p
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
