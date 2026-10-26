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
/// The toolbar the window wears reads the stored value (`SettingsToolbar`, in the shape of each bar it
/// builds): under `flat` its tabs are `HelmFlatSegmentedCell` drawing the pick, `HelmSurface.barPick`
/// (`HelmToolbarSwitcher`'s header), on a flat plate, and its actions capsule is the flat one; under
/// `liquidGlass` its tabs wear AppKit's cell and its capsule is glass.
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
/// nobody having set a look gets: for a bare actions capsule `liquidGlass`
/// is the plate that existed before the setting did (its strip wears the flat
/// cell). `SettingsToolbar` is the builder in `Sources/` that sets a look on it, from the look its bar was built under.
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

public extension Notification.Name {
    static let helmBarAppearanceChanged = Notification.Name("helmBarAppearanceChanged")
}

public extension EnvironmentValues {
    /// `liquidGlass`, not the stored default: see `HelmBarAppearance`.
    @Entry var helmBarAppearance: HelmBarAppearance = .liquidGlass
}
