import AppKit
import SwiftUI

/// The system's accessibility display settings Helm knows of. Increased Contrast and Reduce Motion change
/// Helm's tokens. Reduce Transparency changes two inks, the plates behind words on the capture overlay
/// (`OverlayInk`). No kit token answers it; of the system's materials the window ground and the header
/// tabs were measured to follow it, the others are assumed.
///
/// **One reader.** `system` is the one place Helm asks the workspace for them;
/// the static accessors that AppKit code and not-yet-rebuilt pages still use
/// (`HelmSignal.warning`, `ModuleTint.colour`, `HelmMotion.reduceMotion`, `OverlayInk`) read
/// it too, and a kit view reads them through `HelmTraits`.
///
/// Apple's guidance on a colour you define yourself is three variants, not two:
/// "supply light and dark variants, **and an increased contrast option for each
/// variant** that provides a significantly higher amount of visual
/// differentiation". A system colour carries those variants already —
/// `ModuleTint` and `HelmSignal`'s light values are the price of not using one,
/// because the system palette fails the light appearance and both types exist to
/// fix that.
///
/// **Why a flag and not an appearance.** `HelmSignal` and `ModuleTint` both
/// answer the light/dark question inside an `NSColor(name:)` handler, from the
/// appearance the drawing is happening in, and the obvious extension is to ask
/// the same handler for the high-contrast appearance. It does not work on
/// macOS 26: measured here, `bestMatch(from:)` returns `NSAppearanceNameAqua`
/// while the drawing appearance **is** `NSAppearanceNameAccessibilityAqua`, and
/// it does so whichever order the names are given in. The appearance carries the
/// setting and will not say so, so the workspace flag is the only channel there
/// is.
public struct HelmAccessibility: Equatable, Sendable {
    public var increasedContrast: Bool
    public var reducedTransparency: Bool
    public var reducedMotion: Bool

    public init(increasedContrast: Bool, reducedTransparency: Bool, reducedMotion: Bool) {
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
    public let scheme: ColorScheme
    public let accessibility: HelmAccessibility

    public var increasedContrast: Bool { accessibility.increasedContrast }
    public var reducedMotion: Bool { accessibility.reducedMotion }
}

public extension EnvironmentValues {
    @Entry var helmAccessibility: HelmAccessibility = .system

    var helmTraits: HelmTraits { HelmTraits(scheme: colorScheme, accessibility: helmAccessibility) }
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
