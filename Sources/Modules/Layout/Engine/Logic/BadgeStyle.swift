import Foundation

/// How the input source is drawn in the menu bar.
public enum BadgeStyle: String, CaseIterable, Sendable {
    case plain, filled, outlined, flagEmoji, flagDrawn

    /// Whether this style needs a country. Flags do; letters do not — and a
    /// layout with no country falls back to letters rather than showing a gap.
    public var needsRegion: Bool {
        self == .flagEmoji || self == .flagDrawn
    }

    public static func from(_ raw: String?) -> BadgeStyle {
        guard let raw, let value = BadgeStyle(rawValue: raw) else { return .plain }
        return value
    }
}
