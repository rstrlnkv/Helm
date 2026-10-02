import CoreGraphics
import Foundation
import HelmRuntime

/// The last area a person confirmed, kept so the panel's Area mode can open on it.
///
/// One record: the display's UUID and a rectangle in that display's own top-left
/// points. **The UUID and not the display id**, because the id is the session's
/// and the UUID survives a re-plug; and **a rectangle in points of that display**,
/// so a record is meaningful only where the same display is still there.
///
/// Read from a property list any process running as the user can write, so
/// every number is judged: a value that is not a finite number is no record, a
/// extent below a point is no record, and a coordinate is held to a ceiling so
/// the arithmetic after it cannot meet `Double.greatestFiniteMagnitude`. And the
/// record is a *reading* made at one moment on one desk: `landing(in:)` asks
/// again, against the displays of the freeze about to be used, and answers
/// nothing for a display that is gone, and only the part of the rectangle that
/// still fits for one that got smaller.
public struct RememberedSelection: Equatable, Sendable {
    public let display: String
    public let rect: CGRect

    /// No display is a million points across; the bound keeps a hand-written
    /// number from ever reaching a multiplication.
    static let ceiling: Double = 1_000_000
    /// A selection narrower than this is not one anybody made.
    static let smallest: CGFloat = 1
    /// A UUID is 36 characters; a longer string is not one.
    static let longestUUID = 64

    public init?(display: String, rect: CGRect) {
        self.init(display: display, x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }

    /// From the four numbers as they were stored, and **not** through a
    /// `CGRect`: its `width` is the absolute value, so a stored width of -300
    /// would have come back as a selection 300 wide, on the other side of the
    /// origin from the one anybody drew.
    init?(display: String, x: Double, y: Double, width: Double, height: Double) {
        guard !display.isEmpty, display.count <= Self.longestUUID,
              let x = x.clampedIfFinite(to: -Self.ceiling...Self.ceiling),
              let y = y.clampedIfFinite(to: -Self.ceiling...Self.ceiling),
              let width = width.clampedIfFinite(to: 0...Self.ceiling),
              let height = height.clampedIfFinite(to: 0...Self.ceiling),
              width >= Double(Self.smallest), height >= Double(Self.smallest)
        else { return nil }
        self.display = display
        self.rect = CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - The store

    /// **Deployed stored data: these names never move.**
    public enum Key {
        public static let display = "rememberedDisplay"
        public static let x = "rememberedX"
        public static let y = "rememberedY"
        public static let width = "rememberedWidth"
        public static let height = "rememberedHeight"
    }

    /// Nil for none — never written, partly written, or written with something
    /// that is not a number.
    public static func read(_ store: NamespacedStore) -> RememberedSelection? {
        let display = store.string(Key.display, default: "")
        guard !display.isEmpty,
              let x = number(store, Key.x), let y = number(store, Key.y),
              let width = number(store, Key.width), let height = number(store, Key.height)
        else { return nil }
        return RememberedSelection(display: display, x: x, y: y, width: width, height: height)
    }

    /// An integer is a number too — a property list written by hand holds
    /// `<integer>` for a whole number — and anything else is not one.
    private static func number(_ store: NamespacedStore, _ key: String) -> Double? {
        guard let value = store.object(key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    public func write(to store: NamespacedStore) {
        store.set(display, for: Key.display)
        store.set(Double(rect.origin.x), for: Key.x)
        store.set(Double(rect.origin.y), for: Key.y)
        store.set(Double(rect.width), for: Key.width)
        store.set(Double(rect.height), for: Key.height)
    }

    /// Forgets the record: all five keys, so a partly written one is gone too.
    public static func erase(from store: NamespacedStore) {
        for key in [Key.display, Key.x, Key.y, Key.width, Key.height] { store.set(nil, for: key) }
    }

    // MARK: - Where it lands

    /// The display and the rectangle the overlay opens on, or nil for an overlay
    /// that opens empty. The display must be one of `frames`, by UUID; the
    /// rectangle is cut to that display as it is now, and a sliver of less than
    /// a point is none.
    public func landing(in frames: [FrozenDisplay]) -> (display: DisplayID, rect: CGRect)? {
        guard let frame = frames.first(where: { $0.uuid == display }) else { return nil }
        let bounds = CGRect(origin: .zero, size: frame.frame.size)
        let fitted = rect.intersection(bounds)
        guard !fitted.isNull, fitted.width >= Self.smallest, fitted.height >= Self.smallest else { return nil }
        return (frame.id, fitted)
    }
}
