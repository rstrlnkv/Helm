import Foundation

/// How the input source is drawn in the menu bar.
public enum BadgeStyle: String, CaseIterable, Sendable {
    case plain, filled, outlined, flagEmoji, flagDrawn

    /// Whether this style needs a country. Flags do; letters do not — and a
    /// layout with no country falls back to letters rather than showing a gap.
    public var needsRegion: Bool {
        self == .flagEmoji || self == .flagDrawn
    }

    /// A flag is the default: it is what people recognise without reading, and
    /// letters are the alternative for anyone who prefers them — or for a
    /// layout with no country to name.
    public static let `default` = BadgeStyle.flagEmoji

    public static func from(_ raw: String?) -> BadgeStyle {
        guard let raw, let value = BadgeStyle(rawValue: raw) else { return .default }
        return value
    }
}
