import AppKit
import SwiftUI

/// Colour that carries a meaning: this needs attention, this failed, this is on.
///
/// The same argument as `HelmText`, one class of colour over: the system
/// palette is tuned for dark and fails in light against the window, where
/// orange and green fall under even the 3:1 floor for a meaningful mark.
///
/// One threshold rather than two: these are used for icons and for body text,
/// so they answer to the stricter 4.5:1 everywhere. The light values are the
/// system colours blended toward black by the smallest fraction that clears it,
/// solved rather than chosen. Dark keeps the system colours: they already pass,
/// and they are the palette people recognise.
///
/// Resolved colours, not hierarchical styles, so they are safe inside
/// measured-height blocks (`HelmAccordion`).
public enum HelmSignal {
    /// Something needs attention and can still be acted on. 4.54:1 / 7.47:1,
    /// and 7.06:1 / 7.47:1 under Increase Contrast.
    public static var warning: Color { warning(increased: HelmAccessibility.system.increasedContrast) }
    /// Granted, done, up to date. 4.59:1 / 8.25:1, and 7.06:1 / 8.25:1 under
    /// Increase Contrast.
    public static var success: Color { success(increased: HelmAccessibility.system.increasedContrast) }
    /// It failed. 4.52:1 / 4.86:1, and 7.06:1 / 7.03:1 under Increase Contrast.
    ///
    /// The only one whose dark value moves under Increase Contrast: the system
    /// red does not clear 7:1 against a dark window, so the increased value is
    /// the smallest blend toward white that does.
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
    /// Rendered on a bench, each read once by hand, no guard, light / dark: on a card at rest 5.69 /
    /// 6.00, bare at rest 6.05 / 6.51. On the tinted banner of Autopilot's tampered state, hover and
    /// press forced: rest 5.18 / 5.15, hover 4.70 / 4.43, pressed 4.52 / 4.23; under Increase Contrast
    /// 6.77 / 6.37, 6.06 / 5.33, 5.77 / 5.02. So, without Increase Contrast, dark hover and pressed stand under 4.5:1 there. On
    /// a card under the pointer, and on any other ground, 4.5:1 is unproved. Internal: only the style reads it.
    static func dangerOnWell(increased: Bool) -> Color { increased ? dangerOnWellIncreased : dangerOnWellOrdinary }

    /// Stored, not built on demand, for identity: `Color` compares by the object
    /// inside it, so a fresh `NSColor(name:)` per read is never equal to itself,
    /// and SwiftUI would see a changed input on every compare. The flag above
    /// stays computed.
    private static let warningOrdinary = HelmSurface.pair(
        light: NSColor(srgbRed: 0.700, green: 0.380, blue: 0.097, alpha: 1), dark: .systemOrange)
    private static let warningIncreased = HelmSurface.pair(
        light: NSColor(srgbRed: 0.526, green: 0.285, blue: 0.074, alpha: 1), dark: .systemOrange)
    private static let successOrdinary = HelmSurface.pair(
        light: NSColor(srgbRed: 0.126, green: 0.529, blue: 0.227, alpha: 1), dark: .systemGreen)
    private static let successIncreased = HelmSurface.pair(
        light: NSColor(srgbRed: 0.095, green: 0.400, blue: 0.172, alpha: 1), dark: .systemGreen)
    private static let dangerOrdinary = HelmSurface.pair(
        light: NSColor(srgbRed: 0.879, green: 0.188, blue: 0.202, alpha: 1), dark: .systemRed)
    private static let dangerIncreased = HelmSurface.pair(
        light: NSColor(srgbRed: 0.663, green: 0.142, blue: 0.154, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.515, blue: 0.522, alpha: 1))

    private static let dangerOnWellOrdinary = HelmSurface.pair(
        light: NSColor(srgbRed: 0.693, green: 0.148, blue: 0.159, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.545, blue: 0.518, alpha: 1))
    private static let dangerOnWellIncreased = HelmSurface.pair(
        light: NSColor(srgbRed: 0.543, green: 0.116, blue: 0.125, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.698, blue: 0.680, alpha: 1))
}
