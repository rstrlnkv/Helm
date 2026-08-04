import SwiftUI
import AppKit

/// The colour a module is known by, and the only place those nine are written.
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
/// Keyboard is the one that is not a system colour at all. `.pink` sits 0,107
/// from `.red`, which Uninstaller keeps because red on the tool that deletes
/// things is worth more than red anywhere else. Magenta at 320° is 0,237 away
/// and reads at 4,33:1.
public enum ModuleTint: String, CaseIterable, Sendable {
    case keepAwake, vpn, uninstaller, disk, duplicates, autopilot, homebrew, leftovers, keyboard

    public var colour: Color {
        switch self {
        case .keepAwake:
            return adaptive(light: (0.871, 0.478, 0.131), dark: (0.854, 0.486, 0.155))
        case .vpn:
            return adaptive(light: (0.380, 0.333, 0.961), dark: (0.427, 0.486, 1.000))
        case .uninstaller:
            return adaptive(light: (1.000, 0.220, 0.235), dark: (1.000, 0.259, 0.271))
        case .disk:
            return adaptive(light: (0.796, 0.208, 0.878), dark: (0.859, 0.227, 0.949))
        case .duplicates:
            return adaptive(light: (0.000, 0.645, 0.688), dark: (0.000, 0.646, 0.690))
        case .autopilot:
            return adaptive(light: (0.000, 0.533, 1.000), dark: (0.000, 0.569, 1.000))
        case .homebrew:
            return adaptive(light: (0.168, 0.665, 0.293), dark: (0.145, 0.664, 0.274))
        case .leftovers:
            return adaptive(light: (0.675, 0.498, 0.369), dark: (0.718, 0.541, 0.400))
        case .keyboard:
            return adaptive(light: (0.850, 0.150, 0.650), dark: (0.850, 0.150, 0.650))
        }
    }

    /// One colour that answers for itself in either appearance, so no call site
    /// reads the environment to stay legible. The same shape `HelmSignal` uses.
    private func adaptive(light: (Double, Double, Double),
                          dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
