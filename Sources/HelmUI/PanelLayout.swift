import SwiftUI

/// How much horizontal room a module's panel tile wants in the grid layout.
public enum PanelTileSpan: String, Sendable, Codable {
    /// Full panel width — for tiles with live state or a row of controls.
    case wide
    /// Half width — pairs up with another compact tile in one row.
    case compact
}

/// Panel presentation the user picked. `list` is the original stacked layout,
/// kept so the grid can be rolled back without a rebuild.
public enum PanelLayoutStyle: String, CaseIterable, Sendable {
    case grid, list

    public var label: String {
        switch self {
        case .grid: return L("Grid", [.ru: "Сетка", .es: "Cuadrícula", .fr: "Grille", .de: "Raster", .ja: "グリッド", .zh: "网格", .pt: "Grade"])
        case .list: return L("List", [.ru: "Список", .es: "Lista", .fr: "Liste", .de: "Liste", .ja: "リスト", .zh: "列表", .pt: "Lista"])
        }
    }
}

/// Pure layout maths for the grid: turns the ordered tile spans into rows.
/// Compact tiles pair up; a wide tile always takes its own row; a trailing
/// unpaired compact tile keeps its own row (rendered half-width, left-aligned).
public enum PanelGridLayout {
    /// Indices of the tiles, grouped per row.
    public static func rows(of spans: [PanelTileSpan]) -> [[Int]] {
        var rows: [[Int]] = []
        var pending: Int?
        for (i, span) in spans.enumerated() {
            switch span {
            case .wide:
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([i])
            case .compact:
                if let p = pending {
                    rows.append([p, i])
                    pending = nil
                } else {
                    pending = i
                }
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }
}

// MARK: - Environment

private struct PanelTileSpanKey: EnvironmentKey {
    static let defaultValue: PanelTileSpan = .wide
}

public extension EnvironmentValues {
    /// The span the panel is rendering this tile at, so a tile can show a
    /// condensed form when it only gets half the width.
    var helmTileSpan: PanelTileSpan {
        get { self[PanelTileSpanKey.self] }
        set { self[PanelTileSpanKey.self] = newValue }
    }
}
