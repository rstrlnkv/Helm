import AppKit
import SwiftUI

/// The system's accessibility display settings Helm knows of. Increased Contrast and Reduce Motion change
/// Helm's tokens. Reduce Transparency changes two inks, the plates behind words on the capture overlay
/// (`OverlayInk`). No kit token answers it; of the system's materials the window ground and the header
/// tabs were measured to follow it, the others are assumed.
///
/// **One reader.** `system` is the one place Helm asks the workspace for them;
/// the static accessors AppKit code uses (`HelmSignal.warning`,
/// `ModuleTint.colour`, `HelmMotion.reduceMotion`, `OverlayInk`) read it too,
/// and a kit view reads them through `HelmTraits`.
///
/// Apple asks a colour you define yourself for light and dark variants and an
/// increased-contrast option for each; `ModuleTint` and `HelmSignal` define
/// their own because the system palette fails the light appearance.
///
/// **A flag, not an appearance**: asked inside an `NSColor(name:)` handler,
/// `bestMatch(from:)` returns `NSAppearanceNameAqua` while the drawing
/// appearance is `NSAppearanceNameAccessibilityAqua`, whatever order the names
/// are given in. The appearance carries the setting and will not say so, so
/// the workspace flag is the only channel there is.
public struct HelmAccessibility: Equatable, Sendable {
    public var increasedContrast: Bool
    public var reducedTransparency: Bool
    var reducedMotion: Bool

    init(increasedContrast: Bool, reducedTransparency: Bool, reducedMotion: Bool) {
        self.increasedContrast = increasedContrast
        self.reducedTransparency = reducedTransparency
        self.reducedMotion = reducedMotion
    }

    /// The one place Helm reads the system's accessibility display settings.
    ///
    /// **Computed, never stored**, for `HelmMotion.reduceMotion`'s reason: in a
    /// `let` it freezes at launch, and the person who notices is the one who turned
    /// the setting on. Every token that reads it is computed too, so a view's next
    /// body evaluation is meant to pick up the change, and a view under
    /// `helmRoot()` (its tracker) to be told the moment the switch is flipped —
    /// intent, untried: the tracker has not been seen to fire, and whether SwiftUI
    /// caches the `@Entry` default is unchecked.
    public static var system: HelmAccessibility {
        let workspace = NSWorkspace.shared
        return HelmAccessibility(
            increasedContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reducedTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reducedMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// What a kit view needs to know to pick a token: light or dark, and the three
/// accessibility settings. Read from `\.helmTraits`.
public struct HelmTraits: Equatable, Sendable {
    let scheme: ColorScheme
    let accessibility: HelmAccessibility

    public var increasedContrast: Bool { accessibility.increasedContrast }
    var reducedMotion: Bool { accessibility.reducedMotion }
}

extension EnvironmentValues {
    @Entry public var helmAccessibility: HelmAccessibility = .system

    public var helmTraits: HelmTraits { HelmTraits(scheme: colorScheme, accessibility: helmAccessibility) }
}

extension View {
    /// Reached through `helmRoot()`, which a hosting root carries: the views under it are told when the person
    /// changes an accessibility display setting.
    func helmTracksAccessibilityDisplay() -> some View { modifier(HelmAccessibilityDisplayTracker()) }
}

private struct HelmAccessibilityDisplayTracker: ViewModifier {
    @State private var accessibility: HelmAccessibility?

    func body(content: Content) -> some View {
        content
            .environment(\.helmAccessibility, accessibility ?? .system)
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
                accessibility = .system
            }
    }
}
