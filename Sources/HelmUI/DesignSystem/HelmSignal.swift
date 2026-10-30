import AppKit
import SwiftUI

/// Colour that carries a meaning: this needs attention, this failed, this is on.
///
/// The same argument as `HelmText`, one class of colour over. The system
/// palette is tuned for dark, where all three are comfortable, and it is light
/// where they fail — measured against both
/// `windowBackgroundColor` and `controlBackgroundColor`, which are the same
/// colour on macOS 26:
///
///     light   orange 2.31:1   green 2.22:1   red 3.57:1
///     dark    orange 7.47:1   green 8.25:1   red 4.86:1
///
/// against a 4.5:1 body-text floor and a 3:1 floor for a mark that carries
/// meaning. So the icon on every "needs a permission" banner — the most
/// important warning the app has — was its least visible mark in light mode,
/// and `HelmHotkeyRecorder`'s "this shortcut does nothing" note was body text
/// at 2.31:1. This is the defect `HelmText` and `HelmBadge` were built to
/// eliminate, never generalised past text tokens.
///
/// One threshold rather than two: these are used for icons *and* for body text,
/// so they answer to the stricter one everywhere rather than to whichever the
/// current call site happens to need. The light values are the system colours
/// blended toward black by the smallest fraction that clears 4.5:1 (0.36, 0.38,
/// 0.15) — solved for, not chosen and described afterwards. Dark keeps the
/// system colours untouched: they already pass, and the palette macOS ships is
/// the one people recognise.
///
/// Resolved colours, not hierarchical styles, so they are safe inside the
/// measured-height blocks the Motion rules warn about.
public enum HelmSignal {
    /// Something needs attention and can still be acted on. 4.54:1 / 7.47:1,
    /// and 7.06:1 / 7.47:1 under Increase Contrast.
    public static var warning: Color { warning(increased: HelmAccessibility.system.increasedContrast) }
    /// Granted, done, up to date. 4.59:1 / 8.25:1, and 7.06:1 / 8.25:1 under
    /// Increase Contrast.
    public static var success: Color { success(increased: HelmAccessibility.system.increasedContrast) }
    /// It failed. 4.52:1 / 4.86:1, and 7.06:1 / 7.03:1 under Increase Contrast.
    ///
    /// The only one of the three whose **dark** value moves. Warning and success
    /// are the system's own orange and green there, and both already clear 7:1
    /// against the window; red does not, at 4,86:1, so the increased value is a
    /// literal — the smallest blend toward white that reaches the higher floor,
    /// because on a dark window contrast is bought by going lighter.
    public static var danger: Color { danger(increased: HelmAccessibility.system.increasedContrast) }

    /// The setting as an argument rather than a reading, so each floor can be
    /// measured without the machine's own switch — `HelmMotion.spins(requested:
    /// reduceMotion:)`'s shape.
    public static func warning(increased: Bool) -> Color { increased ? warningIncreased : warningOrdinary }
    public static func success(increased: Bool) -> Color { increased ? successIncreased : successOrdinary }
    public static func danger(increased: Bool) -> Color { increased ? dangerIncreased : dangerOrdinary }

    /// `danger` for a label on a button's well (`HelmButtonStyle`), which is a surface of its own:
    /// `danger` is solved against the bare window, and the well, a card under it and the pointer
    /// over it all move the ground toward the ink. Solved by arithmetic on assumed grounds (window
    /// `#FFFFFF` / `#1E1E1E`, the fills of `HelmSurface`) to 4.9:1 on a card under the pointer and
    /// to 7.6:1 on a card at rest under Increase Contrast; a press on a card comes to 4.68 / 4.59.
    /// Rendered on a bench window, at rest only: 5.69 / 6.00 on a card, 6.05 / 6.51 bare (read once
    /// by hand, no guard). Under the pointer, and on any other ground, a tinted banner among them,
    /// 4.5:1 is unproved. Internal: only the style reads it.
    static func dangerOnWell(increased: Bool) -> Color { increased ? dangerOnWellIncreased : dangerOnWellOrdinary }

    /// Eight stored colours rather than eight built on demand, and the reason is
    /// identity rather than cost. `Color` compares by the object inside it, so a
    /// property that builds a fresh `NSColor(name:)` on every access is a colour
    /// that is never equal to itself: two reads of `warning` compared unequal,
    /// and SwiftUI compares the same way when it decides whether a view's input
    /// changed. The **flag** above stays computed, which is what the setting
    /// needs; these do not move.
    private static let warningOrdinary = adaptive(
        light: NSColor(srgbRed: 0.700, green: 0.380, blue: 0.097, alpha: 1), dark: .systemOrange)
    private static let warningIncreased = adaptive(
        light: NSColor(srgbRed: 0.526, green: 0.285, blue: 0.074, alpha: 1), dark: .systemOrange)
    private static let successOrdinary = adaptive(
        light: NSColor(srgbRed: 0.126, green: 0.529, blue: 0.227, alpha: 1), dark: .systemGreen)
    private static let successIncreased = adaptive(
        light: NSColor(srgbRed: 0.095, green: 0.400, blue: 0.172, alpha: 1), dark: .systemGreen)
    private static let dangerOrdinary = adaptive(
        light: NSColor(srgbRed: 0.879, green: 0.188, blue: 0.202, alpha: 1), dark: .systemRed)
    private static let dangerIncreased = adaptive(
        light: NSColor(srgbRed: 0.663, green: 0.142, blue: 0.154, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.515, blue: 0.522, alpha: 1))

    private static let dangerOnWellOrdinary = adaptive(
        light: NSColor(srgbRed: 0.693, green: 0.148, blue: 0.159, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.545, blue: 0.518, alpha: 1))
    private static let dangerOnWellIncreased = adaptive(
        light: NSColor(srgbRed: 0.543, green: 0.116, blue: 0.125, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.698, blue: 0.680, alpha: 1))

    /// One colour that answers for itself in either appearance, so no call site
    /// has to read the environment to stay legible.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
