import AppKit

/// Menu-bar icon shape. The host icon is configurable; Keep Awake tints it while active.
public enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case ring, doubleRing, ringDot, disc, dot

    public var label: String {
        switch self {
        case .ring: return L("Ring", [.ru: "Кольцо", .es: "Anillo", .fr: "Anneau", .de: "Ring", .ja: "リング", .zh: "圆环", .pt: "Anel"])
        case .doubleRing: return L("Double ring", [.ru: "Двойное кольцо", .es: "Anillo doble", .fr: "Double anneau", .de: "Doppelring", .ja: "二重リング", .zh: "双环", .pt: "Anel duplo"])
        case .ringDot: return L("Ring + dot", [.ru: "Кольцо + точка", .es: "Anillo + punto", .fr: "Anneau + point", .de: "Ring + Punkt", .ja: "リング＋点", .zh: "圆环+点", .pt: "Anel + ponto"])
        case .disc: return L("Filled", [.ru: "Залитый", .es: "Relleno", .fr: "Plein", .de: "Gefüllt", .ja: "塗りつぶし", .zh: "实心", .pt: "Preenchido"])
        case .dot: return L("Dot", [.ru: "Точка", .es: "Punto", .fr: "Point", .de: "Punkt", .ja: "点", .zh: "点", .pt: "Ponto"])
        }
    }
}

/// Menu-bar icon size (canvas point size).
public enum MenuBarIconSize: String, CaseIterable, Sendable {
    // rawValues kept stable for stored-settings compatibility; the small end was
    // extended (xxSmall/xxxSmall) and the large end dropped per design.
    case xxxSmall, xxSmall, extraSmall, small, medium

    public var points: CGFloat {
        switch self {
        case .xxxSmall: return 9
        case .xxSmall: return 11
        case .extraSmall: return 13
        case .small: return 15
        case .medium: return 18
        }
    }
    /// Human, localized size name (shown once for the selected size in the picker).
    public var label: String {
        switch self {
        case .xxxSmall: return L("Tiny", [.ru: "Крошечный", .es: "Diminuto", .fr: "Minuscule", .de: "Winzig", .ja: "極小", .zh: "极小", .pt: "Minúsculo"])
        case .xxSmall: return L("Very small", [.ru: "Очень маленький", .es: "Muy pequeño", .fr: "Très petit", .de: "Sehr klein", .ja: "とても小さい", .zh: "很小", .pt: "Muito pequeno"])
        case .extraSmall: return L("Small", [.ru: "Маленький", .es: "Pequeño", .fr: "Petit", .de: "Klein", .ja: "小", .zh: "小", .pt: "Pequeno"])
        case .small: return L("Medium", [.ru: "Средний", .es: "Mediano", .fr: "Moyen", .de: "Mittel", .ja: "中", .zh: "中", .pt: "Médio"])
        case .medium: return L("Large", [.ru: "Большой", .es: "Grande", .fr: "Grand", .de: "Groß", .ja: "大", .zh: "大", .pt: "Grande"])
        }
    }
}

public enum RingIcon {
    /// Menu-bar glyph. `tintToken` nil → template (system-recolored, white/inactive).
    /// Non-nil → drawn in that palette color (non-template, shows while active).
    /// `progress` (0…1) draws the ring as a countdown arc: full at 1, empty at
    /// 0, consumed clockwise from 12 o'clock. nil = the plain glyph.
    public static func make(style: MenuBarIconStyle, size: MenuBarIconSize,
                            tintToken: String?, progress: Double? = nil) -> NSImage {
        // The shape and the countdown are two separate things somebody switched
        // on, and both have to survive. The arc takes the place of the outer
        // ring — which is what a countdown *is* on this icon — and whatever the
        // shape draws inside that ring is drawn on top of it. `.dot` and
        // `.disc` have no outer ring of their own, so they used to be excluded
        // from the countdown altogether: the setting sits beside them on the
        // page and meant nothing.
        if let progress {
            return makeArc(style: style, size: size, tintToken: tintToken, progress: progress)
        }
        return makeGlyph(style: style, size: size, tintToken: tintToken)
    }

    /// Ring drawn as an arc, plus a faint track so the icon keeps its footprint.
    private static func makeArc(style: MenuBarIconStyle, size: MenuBarIconSize,
                                tintToken: String?, progress: Double) -> NSImage {
        let s = size.points
        let lineWidth = max(1.5, s * 0.12)
        let radius = (s - lineWidth) / 2
        let center = CGPoint(x: s / 2, y: s / 2)
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let color = nsColor(tintToken: tintToken)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let remaining = min(1, max(0, progress))
        if remaining > 0 {
            // Clockwise from 12 o'clock: AppKit angles are counter-clockwise
            // from 3 o'clock, so start at 90° and sweep backwards.
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * remaining, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }

        // What the shape puts inside its ring, kept. Without this every style
        // collapsed to a plain ring the moment a timed session started.
        color.setFill()
        let inner = s * 0.2 + lineWidth
        switch style {
        case .ring:
            break                       // the arc is the ring
        case .doubleRing:
            let ring = NSBezierPath(ovalIn: NSRect(x: inner, y: inner,
                                                   width: s - 2 * inner, height: s - 2 * inner))
            ring.lineWidth = max(1, lineWidth * 0.7)
            ring.stroke()
        case .ringDot:
            fillCentred(diameter: s * 0.24, in: s)
        case .disc:
            // Inset clear of the arc, so the countdown stays legible against it.
            NSBezierPath(ovalIn: NSRect(x: inner, y: inner,
                                        width: s - 2 * inner, height: s - 2 * inner)).fill()
        case .dot:
            fillCentred(diameter: s * 0.5, in: s)
        }
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)
        return img
    }

    private static func makeGlyph(style: MenuBarIconStyle, size: MenuBarIconSize, tintToken: String?) -> NSImage {
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
        case .doubleRing:
            strokeOval(inset: inset, lineWidth: lineWidth, size: dim)
            let innerInset = inset + s * 0.2
            let inner = NSBezierPath(ovalIn: NSRect(x: innerInset, y: innerInset,
                                                    width: s - 2 * innerInset, height: s - 2 * innerInset))
            inner.lineWidth = max(1, lineWidth * 0.7)
            inner.stroke()
        case .ringDot:
            strokeOval(inset: inset, lineWidth: lineWidth, size: dim)
            let d = s * 0.24
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
        case .disc:
            NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)).fill()
        case .dot:
            let d = s * 0.5
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
        }
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)
        return img
    }

    private static func fillCentred(diameter d: CGFloat, in s: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
    }

    private static func strokeOval(inset: CGFloat, lineWidth: CGFloat, size: NSSize) {
        let rect = NSRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let p = NSBezierPath(ovalIn: rect)
        p.lineWidth = lineWidth
        p.stroke()
    }

    /// Palette lookup, also used for menu-bar text drawn beside the glyph.
    public static func nsColor(forTintToken token: String?) -> NSColor { nsColor(tintToken: token) }

    private static func nsColor(tintToken: String?) -> NSColor {
        switch tintToken {
        case nil, "white": return .white
        // Theme-adaptive, and a trap in a baked bitmap: `makeGlyph` draws with
        // `lockFocus`, so this resolves once against whatever appearance was
        // current — not the one the image is shown in. In-app previews should
        // ask for `nil` (a template) and tint with `foregroundStyle`, or go
        // through `HelmAppearance`. Kept for callers that draw at a moment
        // when the appearance is known to be right.
        case "primary": return .labelColor
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
