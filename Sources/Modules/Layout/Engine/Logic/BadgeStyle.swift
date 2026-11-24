import Foundation

/// How the input source is drawn in the menu bar.
public enum BadgeStyle: String, CaseIterable, Sendable {
    case plain, filled, outlined, flagDrawn, sourceName

    /// Whether this style needs a country. Flags do; letters do not — and a
    /// layout with no country falls back to letters rather than showing a gap.
    public var needsRegion: Bool { self == .flagDrawn }

    /// The layout's whole name instead of a badge, the way the system's own
    /// indicator draws it under «Show Input Source Name».
    ///
    /// A style and not a switch of its own, so «Style» and its preview grid
    /// always describe what is drawn, and there is one place a person changes
    /// how the indicator looks.
    public var isName: Bool { self == .sourceName }

    /// A flag is the default: it is what people recognise without reading, and
    /// letters are the alternative for anyone who prefers them — or for a
    /// layout with no country to name.
    public static let `default` = BadgeStyle.flagDrawn

    /// A stored style this build does not know reads as the default,
    /// `flagDrawn`: a stored `flagEmoji` keeps a flag, which is what that
    /// person was choosing.
    public static func from(_ raw: String?) -> BadgeStyle {
        guard let raw, let value = BadgeStyle(rawValue: raw) else { return .default }
        return value
    }
}
