import AppKit

/// Menu-bar icon shape. The host icon is configurable; Keep Awake tints it while active.
public enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case ring, disc, ringDot, dot

    public var label: String {
        switch self {
        case .ring: return L("Ring", [.ru: "Кольцо", .es: "Anillo", .fr: "Anneau", .de: "Ring", .ja: "リング", .zh: "圆环", .pt: "Anel"])
        case .disc: return L("Filled", [.ru: "Залитый", .es: "Relleno", .fr: "Plein", .de: "Gefüllt", .ja: "塗りつぶし", .zh: "实心", .pt: "Preenchido"])
        case .ringDot: return L("Ring + dot", [.ru: "Кольцо + точка", .es: "Anillo + punto", .fr: "Anneau + point", .de: "Ring + Punkt", .ja: "リング＋点", .zh: "圆环+点", .pt: "Anel + ponto"])
        case .dot: return L("Dot", [.ru: "Точка", .es: "Punto", .fr: "Point", .de: "Punkt", .ja: "点", .zh: "点", .pt: "Ponto"])
        }
    }
}

/// Menu-bar icon size (canvas point size).
public enum MenuBarIconSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var points: CGFloat {
        switch self {
        case .small: return 15
        case .medium: return 18
        case .large: return 22
        }
    }
    public var label: String {
        switch self {
        case .small: return L("Small", [.ru: "Маленький", .es: "Pequeño", .fr: "Petit", .de: "Klein", .ja: "小", .zh: "小", .pt: "Pequeno"])
        case .medium: return L("Medium", [.ru: "Средний", .es: "Mediano", .fr: "Moyen", .de: "Mittel", .ja: "中", .zh: "中", .pt: "Médio"])
        case .large: return L("Large", [.ru: "Большой", .es: "Grande", .fr: "Grand", .de: "Groß", .ja: "大", .zh: "大", .pt: "Grande"])
        }
    }
}

public enum RingIcon {
    /// Backwards-compatible: a medium ring in the given tint.
    public static func make(tintToken: String?) -> NSImage {
        make(style: .ring, size: .medium, tintToken: tintToken)
    }

    public static func make(style: MenuBarIconStyle, tintToken: String?) -> NSImage {
        make(style: style, size: .medium, tintToken: tintToken)
    }

    /// Menu-bar glyph. `tintToken` nil → template (system-recolored, white/inactive).
    /// Non-nil → drawn in that palette color (non-template, shows while active).
    public static func make(style: MenuBarIconStyle, size: MenuBarIconSize, tintToken: String?) -> NSImage {
        let s = size.points
        let dim = NSSize(width: s, height: s)
        let lineWidth = max(1.5, s * 0.12)
        let inset = lineWidth
        let img = NSImage(size: dim)
        img.lockFocus()
        let color = nsColor(tintToken: tintToken)
        color.setStroke()
        color.setFill()
        switch style {
        case .ring:
            strokeOval(inset: inset, lineWidth: lineWidth, size: dim)
        case .disc:
            NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)).fill()
        case .ringDot:
            strokeOval(inset: inset, lineWidth: lineWidth, size: dim)
            let d = s * 0.24
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
        case .dot:
            let d = s * 0.5
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
        }
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)
        return img
    }

    private static func strokeOval(inset: CGFloat, lineWidth: CGFloat, size: NSSize) {
        let rect = NSRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let p = NSBezierPath(ovalIn: rect)
        p.lineWidth = lineWidth
        p.stroke()
    }

    private static func nsColor(tintToken: String?) -> NSColor {
        switch tintToken {
        case nil, "white": return .white
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "mint": return .systemMint
        case "cyan": return .systemCyan
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        default: return .white
        }
    }
}
