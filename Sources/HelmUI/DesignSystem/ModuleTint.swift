import SwiftUI
import AppKit

/// The colour a module is known by, and the only place they are written.
///
/// **Why not `ModuleCategory.tint`.** That gave one colour to a category, so
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
/// So the values below are **solved, not chosen**. Each is the system colour
/// blended toward black by the smallest fraction that lets white clear 3:1,
/// per appearance — the same shape `HelmSignal` uses — and then checked pairwise
/// so no two are closer than 0,15 in sRGB. `ModuleTintTests` measures both and
/// is what may change these numbers; do not hand-edit one and trust the eye.
///
/// **Three variants, not two.** Apple asks a colour you define yourself for a
/// light value, a dark value *and* an increased-contrast option for each; a
/// system colour carries those already, and these are literals precisely
/// because the system palette failed the light appearance. So there is a second
/// solved set against a higher floor, and `HelmContrast` explains why the switch
/// has to be read as a flag rather than asked of the appearance.
///
/// Keyboard is the one that is not a system colour at all. `.pink` sits 0,107
/// from `.red`, which Uninstaller keeps because red on the tool that deletes
/// things is worth more than red anywhere else. Magenta at 320° is 0,237 away
/// and reads at 4,33:1.
public enum ModuleTint: String, CaseIterable, Sendable {
    case keepAwake, vpn, uninstaller, disk, duplicates, autopilot, homebrew, leftovers, keyboard, hosts

    public var colour: Color { colour(increased: HelmContrast.increased) }

    /// The setting as an argument rather than a reading, so the rule can be
    /// measured without the machine's own switch — `HelmMotion.spins(requested:
    /// reduceMotion:)`'s shape, and for its reason: a value this file cannot be
    /// asked about is a value nothing can check.
    func colour(increased: Bool) -> Color {
        let pair = increased ? increasedContrast : ordinary
        return adaptive(light: pair.light, dark: pair.dark)
    }

    private typealias Component = (Double, Double, Double)
    private typealias Pair = (light: Component, dark: Component)

    /// White clears 3:1 on every one of these, and no two are closer than 0,15.
    private var ordinary: Pair {
        switch self {
        case .keepAwake:   return (light: (0.871, 0.478, 0.131), dark: (0.854, 0.486, 0.155))
        case .vpn:         return (light: (0.380, 0.333, 0.961), dark: (0.427, 0.486, 1.000))
        case .uninstaller: return (light: (1.000, 0.220, 0.235), dark: (1.000, 0.259, 0.271))
        case .disk:        return (light: (0.796, 0.208, 0.878), dark: (0.859, 0.227, 0.949))
        case .duplicates:  return (light: (0.000, 0.645, 0.688), dark: (0.000, 0.646, 0.690))
        case .autopilot:   return (light: (0.000, 0.533, 1.000), dark: (0.000, 0.569, 1.000))
        case .homebrew:    return (light: (0.168, 0.665, 0.293), dark: (0.145, 0.664, 0.274))
        case .leftovers:   return (light: (0.675, 0.498, 0.369), dark: (0.718, 0.541, 0.400))
        case .keyboard:    return (light: (0.850, 0.150, 0.650), dark: (0.850, 0.150, 0.650))
        case .hosts:       return (light: (0.180, 0.412, 0.573), dark: (0.212, 0.463, 0.639))
        }
    }

    /// The same solve against a higher floor: the smallest blend toward black at
    /// which white clears **4,5:1** rather than 3:1, per appearance.
    ///
    /// Not every value moves, and that is the method working rather than a gap.
    /// VPN's light already reads 5,09:1 and Hosts reads 5,91 and 4,91, so the
    /// blend that clears the higher floor is zero and the colour is the ordinary
    /// one. A tint that was chosen with room to spare does not owe a second
    /// value.
    ///
    /// The blend is solved against the **rounded** literal rather than before it.
    /// Solved the other way round, Uninstaller's dark came out at 4,4988:1 —
    /// short by a thousandth of a ratio, because three decimal places of a
    /// component is a step of about a quarter of a level and the solve landed on
    /// the wrong side of it. A value that is short because of how it was written
    /// down is the worst kind: it looks measured.
    ///
    /// The pairwise check is re-run on this set rather than inherited: blending
    /// ten colours toward one point moves them toward each other. The closest
    /// pair here is Duplicates and Hosts at 0,209 in light and Disk and Keyboard
    /// at 0,215 in dark, both past the 0,15 floor. `ModuleTintTests` measures
    /// both halves on both sets.
    private var increasedContrast: Pair {
        switch self {
        case .keepAwake:   return (light: (0.699, 0.384, 0.105), dark: (0.687, 0.391, 0.125))
        case .vpn:         return (light: (0.380, 0.333, 0.961), dark: (0.371, 0.422, 0.869))
        case .uninstaller: return (light: (0.878, 0.193, 0.206), dark: (0.859, 0.222, 0.233))
        case .disk:        return (light: (0.754, 0.197, 0.831), dark: (0.752, 0.199, 0.831))
        case .duplicates:  return (light: (0.000, 0.516, 0.550), dark: (0.000, 0.516, 0.551))
        case .autopilot:   return (light: (0.000, 0.464, 0.870), dark: (0.000, 0.472, 0.830))
        case .homebrew:    return (light: (0.135, 0.533, 0.235), dark: (0.117, 0.535, 0.221))
        case .leftovers:   return (light: (0.587, 0.433, 0.321), dark: (0.579, 0.436, 0.322))
        case .keyboard:    return (light: (0.838, 0.148, 0.641), dark: (0.838, 0.148, 0.641))
        case .hosts:       return (light: (0.180, 0.412, 0.573), dark: (0.212, 0.463, 0.639))
        }
    }

    /// One colour that answers for itself in either appearance, so no call site
    /// reads the environment to stay legible. The same shape `HelmSignal` uses.
    ///
    /// The increased-contrast question is answered *before* this, in `colour`,
    /// rather than inside the handler: the appearance cannot be asked about it
    /// (`HelmContrast` records the measurement), and a handler that read the flag
    /// would be answering from inside a colour AppKit is free to resolve once.
    private func adaptive(light: Component, dark: Component) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
