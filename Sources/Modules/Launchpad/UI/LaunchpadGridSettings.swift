import CoreGraphics
import HelmRuntime

/// What the person chose for the window's grid: as many icons as the screen holds (automatic) or a fixed number of rows and
/// columns, and how big an icon is asked to be.
///
/// **Not sealed** (`Architecture/StoredSettings.md`): sealing is for settings that steer unattended work. These pick a grid
/// with the person present, and a forged value can only pick a number inside the ranges below, so a plain store read is
/// all they need. They are read when the model is made, when a window is about to open and when the page appears, and
/// written only through the model; never per frame, never in a SwiftUI initial value.
struct LaunchpadGridSettings: Equatable, Sendable {
    var automatic = true
    var rows: Int
    var columns: Int
    /// The icon asked for, in points; a grid that does not fit the screen shrinks it (`LaunchpadGeometry`).
    var iconSize: Double

    static let rowRange = 2...8
    static let columnRange = 3...10
    static let iconRange = 48.0...128.0

    /// Automatic, the default icon; the manual seeds are what the page shows the first time Automatic is turned off.
    static let standard = LaunchpadGridSettings(automatic: true, rows: 4, columns: 7, iconSize: Double(LaunchpadMetrics.windowIcon))

    /// Deployed stored data: these names never move.
    enum Key {
        static let automatic = "grid.automatic"
        static let rows = "grid.rows"
        static let columns = "grid.columns"
        static let iconSize = "grid.iconSize"
    }

    var isStandard: Bool { self == .standard }

    /// The one clamp. A size that is no number names no size, so it is the standard one; an infinite one goes to its end, and
    /// shrink-to-fit keeps that safe. Whole points, so a slider cannot write a different number for every pixel.
    func normalized() -> LaunchpadGridSettings {
        LaunchpadGridSettings(
            automatic: automatic, rows: rows.clamped(to: Self.rowRange), columns: columns.clamped(to: Self.columnRange),
            iconSize: iconSize.rounded().clamped(to: Self.iconRange, whenNotANumber: Double(LaunchpadMetrics.windowIcon)))
    }

    /// A key that is missing or of another type is the standard value; the result is always inside the ranges.
    static func read(from store: NamespacedStore) -> LaunchpadGridSettings {
        LaunchpadGridSettings(
            automatic: store.bool(Key.automatic, default: standard.automatic),
            rows: store.int(Key.rows, default: standard.rows),
            columns: store.int(Key.columns, default: standard.columns),
            iconSize: store.double(Key.iconSize, default: standard.iconSize)).normalized()
    }

    /// Only the keys that differ from `old`.
    func write(changedFrom old: LaunchpadGridSettings, to store: NamespacedStore) {
        if automatic != old.automatic { store.set(automatic, for: Key.automatic) }
        if rows != old.rows { store.set(rows, for: Key.rows) }
        if columns != old.columns { store.set(columns, for: Key.columns) }
        if iconSize != old.iconSize { store.set(iconSize, for: Key.iconSize) }
    }
}
