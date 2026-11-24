import SwiftUI
import AppKit

/// The colour a module is known by; a module's value is written in its descriptor, the method here, with the two the host owns (`hostColour`, `whatsNewColour`).
///
/// **Not a colour per category**: a colour four modules share does not tell
/// you which of them you are looking at, which is the whole job.
///
/// **Not the system palette either.** `HelmIconPlate` draws its symbol in white
/// on this colour, so it answers to the 3:1 floor for a meaningful mark, and
/// `.orange`, `.teal` and `.green` fail it against white: the system palette is
/// tuned for a dark background (`HelmSignal` closes the same gap for ink).
///
/// So the values in the descriptors are **solved, not chosen**: the system
/// colour blended toward black by the smallest fraction that lets white clear
/// 3:1, per appearance, then checked pairwise so no two are closer than 0.15 in
/// sRGB. Do not hand-edit one and trust the eye. Keyboard's magenta and
/// Screenshots' olive are literals of their own that pass the same check;
/// Uninstaller keeps red, close to `.pink`, because red on the tool that
/// deletes things is worth more than anywhere else.
///
/// **Three variants, not two**: Apple asks a colour you define for a light
/// value, a dark value and an increased-contrast option for each, so there is a
/// second set solved against a higher floor (Architecture/DesignSystem.md § Ink and contrast).
public struct ModuleTint: Sendable {
    public typealias Component = (Double, Double, Double)
    public typealias Pair = (light: Component, dark: Component)

    /// Each module declares its own pair of pairs in its descriptor, solved
    /// against all of `ModuleRegistry.all`, not alone. `ordinary`: white clears
    /// 3:1. `increasedContrast`: the smallest blend toward black at which white
    /// clears 4.5:1, per appearance; a tint that already clears it keeps its
    /// ordinary value.
    ///
    /// The blend is solved against the **rounded** literal: solved before
    /// rounding, a value can land a thousandth short of the floor and look
    /// measured. The pairwise check is re-run on the blended values, since
    /// blending toward one point moves colours toward each other.
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
    /// reads the environment to stay legible. Increased contrast is decided
    /// before this, in `colour`: the appearance cannot be asked about it
    /// (`HelmAccessibility`), and AppKit may resolve a dynamic colour once.
    private func adaptive(light: Component, dark: Component) -> Color {
        HelmSurface.pair(light: Self.ink(light), dark: Self.ink(dark))
    }

    private static func ink(_ c: Component) -> NSColor {
        NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}
