import CoreGraphics
import HelmRuntime

/// What the person chose for the window's grid: seven columns and five rows that the screen's size scales (automatic, with `sizeMultiplier` to make it all a
/// little smaller or larger) or a fixed number of rows and columns with the icon's size in points.
///
/// **Not sealed** (`Architecture/StoredSettings.md`): sealing is for settings that steer unattended work. These pick a grid
/// with the person present, and a forged value can only pick a number inside the ranges below, so a plain store read is
/// all they need. They are read when the model is made, when a window is about to open and when the page appears, and
/// written only through the model; never per frame, never in a SwiftUI initial value.
struct LaunchpadGridSettings: Equatable, Sendable {
    var automatic = true
    var rows: Int
    var columns: Int
    /// The icon asked for, in points, under Manual; a grid that does not fit the screen shrinks it (`LaunchpadGeometry`). Automatic ignores it.
    var iconSize: Double
    /// Under Automatic, the icon asked for as a multiple of the one the screen's scale gives (1 is that size); Manual ignores it.
    var sizeMultiplier = 1.0
    /// Whether an app's name is drawn under its icon. Folder, category and Hidden block names stay either way.
    var showNames = true

    static let rowRange = 2...8
    static let columnRange = 3...10
    static let iconRange = 48.0...128.0
    static let multiplierRange = 0.8...1.25

    /// Automatic, the default icon; the manual seeds are what the page shows the first time Automatic is turned off: seven columns by four rows, as they always were
    /// (a person who turned Automatic off before pass 22 has no rows key stored, and reads this seed). Automatic ignores the seed rows.
    static let standard = LaunchpadGridSettings(automatic: true, rows: 4, columns: LaunchpadMetrics.automaticColumns,
                                                iconSize: Double(LaunchpadMetrics.windowIcon), showNames: true)

    /// Deployed stored data: these names never move.
    enum Key {
        static let automatic = "grid.automatic"
        static let rows = "grid.rows"
        static let columns = "grid.columns"
        static let iconSize = "grid.iconSize"
        /// A new setting has its own key: `grid.iconSize` is the points Manual asks for and is never read as a multiple.
        static let sizeMultiplier = "grid.sizeMultiplier"
        static let showNames = "grid.showNames"
    }

    var isStandard: Bool { self == .standard }

    /// The one clamp. A size that is no number names no size, so it is the standard one; an infinite one goes to its end, and
    /// shrink-to-fit keeps that safe. Whole points, so a slider cannot write a different number for every pixel. A multiplier that is no number is 1, the
    /// automatic size itself, and is held to hundredths, so a slider cannot write a different number for every pixel either.
    func normalized() -> LaunchpadGridSettings {
        LaunchpadGridSettings(
            automatic: automatic, rows: rows.clamped(to: Self.rowRange), columns: columns.clamped(to: Self.columnRange),
            iconSize: iconSize.rounded().clamped(to: Self.iconRange, whenNotANumber: Double(LaunchpadMetrics.windowIcon)),
            sizeMultiplier: (sizeMultiplier * 100).rounded().clamped(to: Self.multiplierRange.lowerBound * 100...Self.multiplierRange.upperBound * 100, whenNotANumber: 100) / 100,
            showNames: showNames)
    }

    /// A key that is missing or of another type is the standard value; the result is always inside the ranges.
    static func read(from store: NamespacedStore) -> LaunchpadGridSettings {
        LaunchpadGridSettings(
            automatic: store.bool(Key.automatic, default: standard.automatic),
            rows: store.int(Key.rows, default: standard.rows),
            columns: store.int(Key.columns, default: standard.columns),
            iconSize: store.double(Key.iconSize, default: standard.iconSize),
            sizeMultiplier: store.double(Key.sizeMultiplier, default: standard.sizeMultiplier),
            showNames: store.bool(Key.showNames, default: standard.showNames)).normalized()
    }

    /// Only the keys that differ from `old`.
    func write(changedFrom old: LaunchpadGridSettings, to store: NamespacedStore) {
        if automatic != old.automatic { store.set(automatic, for: Key.automatic) }
        if rows != old.rows { store.set(rows, for: Key.rows) }
        if columns != old.columns { store.set(columns, for: Key.columns) }
        if iconSize != old.iconSize { store.set(iconSize, for: Key.iconSize) }
        if sizeMultiplier != old.sizeMultiplier { store.set(sizeMultiplier, for: Key.sizeMultiplier) }
        if showNames != old.showNames { store.set(showNames, for: Key.showNames) }
    }
}
