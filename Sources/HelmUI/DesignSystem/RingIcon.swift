import AppKit

/// Menu-bar icon shape. The host icon is configurable; Keep Awake tints it while active.
public enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case ring, doubleRing, ringDot, disc, dot

    public var label: String {
        switch self {
        case .ring: return L("Ring")
        case .doubleRing: return L("Double ring")
        case .ringDot: return L("Ring + dot")
        case .disc: return L("Filled")
        case .dot: return L("Dot")
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
        case .xxxSmall: return L("Tiny")
        case .xxSmall: return L("Very small")
        case .extraSmall: return L("Small")
        case .small: return L("Medium")
        case .medium: return L("Large")
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

        drawInterior(style: style, size: s, lineWidth: lineWidth, color: color)
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)
        return img
    }

    /// The ring as a quarter segment at a turning angle, over the countdown's
    /// faint track so the icon keeps its footprint while it moves.
    ///
    /// `phase` runs 0…1 across the whole spin and the segment turns *twice* in
    /// it, so half way is one whole revolution and the two ends meet.
    public static func makeSpinner(style: MenuBarIconStyle, size: MenuBarIconSize,
                                   tintToken: String?, phase: Double) -> NSImage {
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

        // Clockwise from 12 o'clock, like the countdown: AppKit angles run
        // counter-clockwise from 3 o'clock, so the start angle counts down.
        let start = CGFloat(90 - 720 * phase)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: start, endAngle: start - 90, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()

        drawInterior(style: style, size: s, lineWidth: lineWidth, color: color)
        img.unlockFocus()
        img.isTemplate = (tintToken == nil)
        return img
    }

    /// The whole spin as `frameCount` still images, built once per appearance
    /// and kept.
    ///
    /// The menu bar wants about thirty frames a second for as long as the spin
    /// lasts, and every one of them is a bitmap the size of the icon: drawing
    /// on demand allocates thirty a second, indefinitely, while a module can
    /// ask for a spin as often as a VPN rule fires. Thirty-six, once, cover
    /// every angle the eye can tell apart at this size.
    public static func spinnerFrames(style: MenuBarIconStyle, size: MenuBarIconSize,
                                     tintToken: String?) -> [NSImage] {
        spinnerCache.frames(for: SpinnerKey(style: style, size: size, tint: tintToken,
                                            appearance: currentAppearanceName)) {
            (0..<frameCount).map {
                makeSpinner(style: style, size: size, tintToken: tintToken,
                            phase: Double($0) / Double(frameCount))
            }
        }
    }

    /// Frames in one spin: two revolutions over `StatusPlan.spinDuration` at
    /// the thirty frames a second the menu bar redraws at.
    public static let frameCount = 36

    /// What the shape puts inside its ring, kept — for the countdown and the
    /// spin alike. Without this every style collapsed to a plain ring the
    /// moment a timed session started, and a spin would do the same for its
    /// second and a bit.
    private static func drawInterior(style: MenuBarIconStyle, size s: CGFloat,
                                     lineWidth: CGFloat, color: NSColor) {
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
            // Inset clear of the arc, so the arc stays legible against it.
            NSBezierPath(ovalIn: NSRect(x: inner, y: inner,
                                        width: s - 2 * inner, height: s - 2 * inner)).fill()
        case .dot:
            fillCentred(diameter: s * 0.5, in: s)
        }
    }

    /// Every palette colour here is dynamic — `.labelColor` and the system
    /// colours all differ between light and dark — and `lockFocus` bakes the
    /// one that was current. A cache keyed only by style, size and tint would
    /// therefore keep drawing yesterday's appearance after the user switched,
    /// so the appearance is part of the key.
    private static var currentAppearanceName: String {
        NSAppearance.currentDrawing().name.rawValue
    }

    private struct SpinnerKey: Hashable {
        let style: MenuBarIconStyle
        let size: MenuBarIconSize
        let tint: String?
        let appearance: String
    }

    private static let spinnerCache = SpinnerCache()

    private final class SpinnerCache: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [SpinnerKey: [NSImage]] = [:]

        func frames(for key: SpinnerKey, build: () -> [NSImage]) -> [NSImage] {
            lock.lock()
            if let hit = stored[key] { lock.unlock(); return hit }
            lock.unlock()
            let built = build()
            lock.lock(); stored[key] = built; lock.unlock()
            return built
        }
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
