import Foundation

/// How the input source is drawn in the menu bar.
public enum BadgeStyle: String, CaseIterable, Sendable {
    case plain, filled, outlined, flagEmoji, flagDrawn, sourceName

    /// Whether this style needs a country. Flags do; letters do not — and a
    /// layout with no country falls back to letters rather than showing a gap.
    public var needsRegion: Bool {
        self == .flagEmoji || self == .flagDrawn
    }

    /// The layout's whole name instead of a badge, the way the system's own
    /// indicator draws it under «Show Input Source Name».
    ///
    /// **It was a separate stored key, and being separate is what made it a
    /// defect.** `indicatorShowsName` could only be switched from the status
    /// item's own menu — nowhere on the settings page — and turning it on made
    /// three controls there lie: Style, Size and the preview grid captioned
    /// «your layouts, as they will look» all went on describing a badge that
    /// was no longer being drawn, with nothing saying why. A style is what this
    /// always was, so it is a style: «Вид» is total again, and there is one
    /// place a person changes how the indicator looks.
    public var isName: Bool { self == .sourceName }

    /// A flag is the default: it is what people recognise without reading, and
    /// letters are the alternative for anyone who prefers them — or for a
    /// layout with no country to name.
    public static let `default` = BadgeStyle.flagDrawn

    public static func from(_ raw: String?) -> BadgeStyle {
        guard let raw, let value = BadgeStyle(rawValue: raw) else { return .default }
        return value
    }
}
