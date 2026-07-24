import AppKit

/// Menu-bar icon shape. The host icon is configurable; Keep Awake tints it while active.
public enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case ring, disc, ringDot, dot

    public var label: String {
        switch self {
        case .ring: return "Ring"
        case .disc: return "Filled"
        case .ringDot: return "Ring + dot"
        case .dot: return "Dot"
        }
    }

    /// SF Symbol used only to represent the style in pickers (not the real glyph).
    public var previewSymbol: String {
        switch self {
        case .ring: return "circle"
        case .disc: return "circle.fill"
        case .ringDot: return "circle.circle"
        case .dot: return "smallcircle.filled.circle.fill"
        }
    }
}

public enum RingIcon {
    /// Backwards-compatible: a ring in the given tint.
    public static func make(tintToken: String?) -> NSImage {
        make(style: .ring, tintToken: tintToken)
    }

    /// Menu-bar glyph. `tintToken` nil → template (system-recolored, white/inactive).
    /// Non-nil → drawn in that palette color (non-template, shows while active).
    public static func make(style: MenuBarIconStyle, tintToken: String?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let color = nsColor(tintToken: tintToken)
        color.setStroke()
        color.setFill()
        switch style {
        case .ring:
            strokeOval(inset: 2, lineWidth: 2, size: size)
        case .disc:
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)).fill()
        case .ringDot:
            strokeOval(inset: 2, lineWidth: 2, size: size)
            NSBezierPath(ovalIn: NSRect(x: size.width / 2 - 2, y: size.height / 2 - 2, width: 4, height: 4)).fill()
        case .dot:
            NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: size.width - 10, height: size.height - 10)).fill()
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
