import Foundation
import HelmRuntime

/// A coordinate this module keeps in its store, which any process running as the user can write: the one ceiling every
/// stored coordinate is held to, and the one reading of what a stored number is. No display is a million points across,
/// and the bound keeps a hand-written number from ever reaching a multiplication. What a value that is not a number
/// becomes, and what an infinity does, is each reader's to say: `RememberedSelection` drops the whole record for either,
/// `PanelOffset` reads NaN as no move and holds an infinity at the ceiling on its own side.
enum StoredNumber {
    static let ceiling: Double = 1_000_000

    /// An integer is a number too — a property list written by hand holds `<integer>` for a whole number — and
    /// anything else is not one: nil.
    static func read(_ store: NamespacedStore, _ key: String) -> Double? {
        guard let value = store.object(key) as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }
}
