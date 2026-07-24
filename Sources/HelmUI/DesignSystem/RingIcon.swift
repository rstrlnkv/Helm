import AppKit
public enum RingIcon {
    /// 18x18 ring. `tintToken` nil → template (system-colored). Non-nil → drawn in that palette color (non-template).
    public static func make(tintToken: String?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let inset: CGFloat = 2, lineWidth: CGFloat = 2
        let rect = NSRect(x: inset, y: inset, width: size.width - 2*inset, height: size.height - 2*inset)
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth
        let color: NSColor = RingIcon.nsColor(tintToken: tintToken)
        color.setStroke()
        path.stroke()
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)   // template only when untinted
        return img
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
