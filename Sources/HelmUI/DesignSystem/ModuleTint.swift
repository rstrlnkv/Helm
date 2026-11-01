import SwiftUI
import AppKit

/// The colour a module is known by; a module's value is written in its descriptor, the method here, with the two the host owns (`hostColour`, `whatsNewColour`).
///
/// **Why not a colour per category.** That gave one colour to a category, so
/// Uninstaller, Disk, Duplicates and Autopilot were one blue and Homebrew,
/// Login Items and Keyboard were one pink. A colour four modules share does not
/// tell you which of them you are looking at, which is the whole job.
///
/// **Why not the system palette either.** `HelmIconPlate` draws the symbol in
/// **white** on this colour, so it answers to the 3:1 floor for a mark that
/// carries meaning — and measured against white, `.orange` is 2,31:1, `.teal`
/// 2,16:1 and `.green` 2,22:1. This is the defect `HelmSignal` was built to
/// close, one class of colour over: the system palette is tuned for a dark
/// background and fails on a light one.
///
/// So the values in the descriptors are **solved, not chosen**. Each but two is the system colour
/// blended toward black by the smallest fraction that lets white clear 3:1,
/// per appearance — the same shape `HelmSignal` uses — and then checked pairwise
/// so no two are closer than 0,15 in sRGB; do not hand-edit one and trust the eye.
///
/// **Three variants, not two.** Apple asks a colour you define yourself for a
/// light value, a dark value *and* an increased-contrast option for each; a
/// system colour carries those already, and these are literals precisely
/// because the system palette failed the light appearance. So there is a second
/// solved set against a higher floor, and `HelmAccessibility` explains why the switch
/// has to be read as a flag rather than asked of the appearance.
///
/// Keyboard is not a system colour at all, and neither is Screenshots' olive. `.pink` sits 0,107
/// from `.red`, which Uninstaller keeps because red on the tool that deletes
/// things is worth more than red anywhere else. Magenta at 320° is 0,237 away
/// and reads at 4,33:1.
public struct ModuleTint: Sendable {
    public typealias Component = (Double, Double, Double)
    public typealias Pair = (light: Component, dark: Component)

    /// Each module declares its own pair of pairs in its descriptor. A new one is
    /// solved against all of `ModuleRegistry.all`, not alone: white clears 3:1 on
    /// `ordinary` and 4,5:1 on `increasedContrast`, and no two modules' values are
    /// closer than 0,15 in sRGB.
    ///
    /// `ordinary`: white clears 3:1 on it, and no two modules' values are closer than 0,15.
    ///
    /// `increasedContrast`: the same solve against a higher floor, the smallest
    /// blend toward black at which white clears **4,5:1** rather than 3:1, per
    /// appearance.
    ///
    /// Not every value moves, and that is the method working rather than a gap.
    /// VPN's light already reads 5,09:1, so the blend that clears the higher
    /// floor is zero and the colour is the ordinary one. A tint that was chosen
    /// with room to spare does not owe a second value.
    ///
    /// The blend is solved against the **rounded** literal rather than before it.
    /// Solved the other way round, Uninstaller's dark came out at 4,4988:1 —
    /// short by a thousandth of a ratio, because three decimal places of a
    /// component is a step of about a quarter of a level and the solve landed on
    /// the wrong side of it. A value that is short because of how it was written
    /// down is the worst kind: it looks measured.
    ///
    /// The pairwise check is re-run on the blended values rather than inherited: blending
    /// colours toward one point moves them toward each other. When it was run, the closest
    /// pair was Disk and Keyboard, at 0,213 in light and 0,215 in dark, both
    /// past the 0,15 floor.
    public init(ordinary: Pair, increasedContrast: Pair) {
        self.ordinary = ordinary
        self.increasedContrast = increasedContrast
    }

    private let ordinary: Pair
    private let increasedContrast: Pair

    /// The page that belongs to no module — General, Log and About — is known by this (`ShellPageIdentity.of`,
    /// `Sources/HelmApp/SettingsWindow.swift`).
    public static let hostColour = Color.gray
    /// The What's New sheet's.
    public static let whatsNewColour = Color.indigo

    public var colour: Color { colour(increased: HelmAccessibility.system.increasedContrast) }

    /// The setting as an argument rather than a reading, so the rule can be
    /// measured without the machine's own switch — `HelmMotion.spins(requested:
    /// reduceMotion:)`'s shape, and for its reason: a value this file cannot be
    /// asked about is a value nothing can check.
    public func colour(increased: Bool) -> Color {
        let pair = increased ? increasedContrast : ordinary
        return adaptive(light: pair.light, dark: pair.dark)
    }

    /// One colour that answers for itself in either appearance, so no call site
    /// reads the environment to stay legible. The same shape `HelmSignal` uses.
    ///
    /// The increased-contrast question is answered *before* this, in `colour`,
    /// rather than inside the handler: the appearance cannot be asked about it
    /// (`HelmAccessibility` records the measurement), and a handler that read the flag
    /// would be answering from inside a colour AppKit is free to resolve once.
    private func adaptive(light: Component, dark: Component) -> Color {
        HelmSurface.pair(light: Self.ink(light), dark: Self.ink(dark))
    }

    private static func ink(_ c: Component) -> NSColor {
        NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}
