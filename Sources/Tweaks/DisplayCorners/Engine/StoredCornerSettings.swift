import CoreGraphics
import HelmRuntime

/// **Display Corners' settings as the tweak's store holds them.** There is no `enabled` key: the host owns
/// that flag, in the same store (`TweakHost.isEnabled`).
///
/// Read when the engine is built and again at each `activate()`, and not cached across an activation. A value that is not a number or a boolean (a string,
/// a list) answers the default. A property list hands a number and a boolean over as the same `NSNumber`, so a
/// boolean reads as 1 or 0 under a numeric key and a 1 or 0 as a boolean under a switch (any other number
/// under a switch is no boolean and takes the default). A number that came from a file is bounded in two places:
/// the remembered scale here, by `scaleBounds`, and the radius not here but where it is used, by `RadiusMath`.
struct StoredCornerSettings {
    static let scaleBounds: ClosedRange<Double> = 0.5...8

    private let store: NamespacedStore
    private(set) var builtIn: Bool
    private(set) var external: Bool
    /// As stored, unbounded: `RadiusMath.pixels(stored:scale:)` bounds it, or answers the default when it is
    /// missing, of the wrong type or not a number. The default depends on the scale of the moment, so it is not stored.
    private(set) var radiusPixels: Double?
    /// The built-in display's pixels per point as last seen; nil when never seen or not a number.
    private(set) var builtInScale: CGFloat?

    init(store: NamespacedStore) {
        self.store = store
        builtIn = store.bool("builtIn", default: true)
        external = store.bool("external", default: false)
        radiusPixels = store.object("radiusPixels") as? Double
        builtInScale = (store.object("builtInScale") as? Double)?.clampedIfFinite(to: Self.scaleBounds).map { CGFloat($0) }
    }

    /// Each write refuses a value equal to the one stored.
    mutating func setBuiltIn(_ value: Bool) {
        builtIn = value
        if store.object("builtIn") as? Bool != value { store.set(value, for: "builtIn") }
    }

    mutating func setExternal(_ value: Bool) {
        external = value
        if store.object("external") as? Bool != value { store.set(value, for: "external") }
    }

    mutating func setRadiusPixels(_ value: Double) {
        radiusPixels = value
        if store.object("radiusPixels") as? Double != value { store.set(value, for: "radiusPixels") }
    }

    /// A scale that is not a number is not remembered.
    mutating func setBuiltInScale(_ value: CGFloat) {
        guard let bounded = Double(value).clampedIfFinite(to: Self.scaleBounds) else { return }
        builtInScale = CGFloat(bounded)
        if store.object("builtInScale") as? Double != bounded { store.set(bounded, for: "builtInScale") }
    }
}
