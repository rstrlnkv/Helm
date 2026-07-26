import Foundation

/// Light, dark, or whatever the system is doing.
///
/// Stored as a string rather than an index: a number in a settings file means
/// nothing to the next person to read it, and reordering the cases would
/// silently change what everyone had chosen.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    /// Anything unrecognised is the system's choice — the answer that is never
    /// wrong, and what a fresh install gets.
    public static func from(_ raw: String?) -> AppAppearance {
        guard let raw, let value = AppAppearance(rawValue: raw) else { return .system }
        return value
    }

    /// The `NSAppearance` name to force, or nil to follow the system.
    ///
    /// The names rather than the objects, so this type stays free of AppKit and
    /// can be tested without a running app.
    public var appearanceName: String? {
        switch self {
        case .system: return nil
        case .light: return "NSAppearanceNameAqua"
        case .dark: return "NSAppearanceNameDarkAqua"
        }
    }
}
