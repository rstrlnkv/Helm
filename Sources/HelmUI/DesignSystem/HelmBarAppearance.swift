import SwiftUI

/// **The two looks the settings window's bar has a stored choice between: a
/// flat plate, or Liquid Glass.**
///
/// One stored value, flat unless the other is stored:
///
/// - `flat` — a tint of `HelmSurface.barPlate` under a group.
/// - `liquidGlass` — the system's own glass under a group. What nothing says
///   is this look.
///
/// The look also picks the window's ground (`ShellContentView`): flat is the system's flat sidebar material,
/// `liquidGlass` is `NSGlassEffectView`.
///
/// The window sets the look at the root of the detail pane (`helmTracksBarAppearance`), and the header row reads
/// it (Architecture/ThePageHeader.md § The page header): under `liquidGlass` the tabs are the window's `NSToolbar`
/// item (`SettingsToolbar`), which carries items under this look only.
///
/// **The key is its own, and it is not `appearance`.** That key, in the same
/// namespace, already holds light, dark or the system's choice
/// (`AppAppearance`); a second meaning under a deployed key would read one
/// setting's value as the other's.
///
/// **Unknown reads flat.** `init(stored:)` answers `.flat` for nothing stored
/// and for any spelling it does not know, so a case retired later, or a value
/// written by a newer build, still reads as a look that exists.
///
/// **Two defaults, and they differ.** The stored one, `init(stored:)`, is
/// `flat`: it is the value read back for a person who chose nothing. The
/// environment's, below, is `liquidGlass`: it is what a view mounted with
/// nobody having set a look gets. The settings window sets a look on its pane;
/// Launchpad's `HelmHeaderTabs` (`LaunchpadScreen`) and
/// `LivePageUnderTheHeaderFixture` mount without one and read the default.
///
/// **Not sealed:** nothing unattended reads it (`AppSettings.barAppearance`).
public enum HelmBarAppearance: String, CaseIterable, Sendable {
    case flat, liquidGlass

    public static let storageKey = "barAppearance"

    /// Anything unknown, including nothing stored, is `flat`.
    public init(stored: String) {
        self = HelmBarAppearance(rawValue: stored) ?? .flat
    }
}

extension Notification.Name {
    public static let helmBarAppearanceChanged = Notification.Name("helmBarAppearanceChanged")
}

extension EnvironmentValues {
    /// `liquidGlass`, not the stored default: see `HelmBarAppearance`.
    @Entry public var helmBarAppearance: HelmBarAppearance = .liquidGlass
}

extension View {
    /// Sets `helmBarAppearance` from `current` and again whenever `.helmBarAppearanceChanged` is posted. It is
    /// set only at the settings pane's root. No new identity: the page below is not
    /// rebuilt for a look it does not draw.
    public func helmTracksBarAppearance(_ current: @escaping () -> HelmBarAppearance) -> some View {
        modifier(HelmBarAppearanceTracker(current: current))
    }
}

extension View {
    /// **The capsule a header group stands on** (`HelmHeaderTabs`, `HelmHeaderSearch`): under `.flat` a
    /// `HelmSurface.barPlate` behind it; under `.liquidGlass` a glass capsule of `glass` in a
    /// `GlassEffectContainer` of its own, `spacing` apart from another.
    @ViewBuilder
    func helmBarCapsule(_ look: HelmBarAppearance, glass: Glass = .regular, spacing: CGFloat? = nil) -> some View {
        switch look {
        case .flat:
            background(HelmSurface.barPlate, in: Capsule())
        case .liquidGlass:
            GlassEffectContainer(spacing: spacing) {
                glassEffect(glass, in: Capsule())
            }
        }
    }
}

private struct HelmBarAppearanceTracker: ViewModifier {
    let current: () -> HelmBarAppearance
    @State private var look: HelmBarAppearance?

    func body(content: Content) -> some View {
        content
            .environment(\.helmBarAppearance, look ?? current())
            .onReceive(NotificationCenter.default.publisher(for: .helmBarAppearanceChanged)) { _ in
                look = current()
            }
    }
}
