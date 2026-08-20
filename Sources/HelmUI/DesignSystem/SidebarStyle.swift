import SwiftUI

/// How the sidebar draws a module: on its own colour, or as a plain glyph.
///
/// A preference rather than a decision, because the two answer different
/// people. A colour plate is faster to find by eye once you know the app; a
/// grey glyph is quieter on a screen somebody looks at all day. Neither is
/// wrong, so neither is hard-coded.
///
/// The colour it selects between is the module's own — see `ModuleDescriptor`.
/// Until that landed the plate took `ModuleCategory.tint`, which four «files»
/// modules share, and a choice between "four things in one blue" and "grey" is
/// not a choice worth offering.
public enum SidebarStyle: String, CaseIterable, Sendable {
    case colour, plain

    /// The key this is stored under, named once so the control that writes it
    /// and the sidebar that reads it cannot be renamed apart.
    public static let storageKey = "sidebarStyle"

    /// A value read back from disk, including one this build has never heard
    /// of — which is what a downgrade looks like after a newer build wrote a
    /// case that did not exist yet.
    public init(stored: String) {
        self = SidebarStyle(rawValue: stored) ?? .colour
    }
}

public extension Notification.Name {
    /// Posted when the module-icon style changes, so a window already drawn
    /// redraws: the setting lives in `UserDefaults` through `AppSettings`, which
    /// SwiftUI cannot watch, and it is written from a window it also changes.
    ///
    /// **Here rather than in `HelmApp`**, beside the type it announces and the
    /// key that type is stored under. It was declared where it is posted, one
    /// target away from `helmTracksModuleIconStyle`, which is the shape
    /// `EventNamesAreNotLiteralsTests` exists for: a name only one side can
    /// change is an error nowhere.
    static let helmSidebarStyleChanged = Notification.Name("helmSidebarStyleChanged")
}

public extension EnvironmentValues {
    /// How a module icon below here is drawn.
    ///
    /// **`.colour` by default, which is the shipped answer**, so a surface that
    /// has not been told draws exactly what it drew before this existed — and a
    /// measurement can name the other one without changing a stored setting.
    @Entry var helmModuleIconStyle: SidebarStyle = .colour
}

public extension View {
    /// Draws every `HelmIconPlate` below this the way the person asked for, and
    /// keeps doing so when they change their mind.
    ///
    /// The setting reached exactly one screen for as long as it existed: the
    /// settings sidebar. Its label says «Module icons», and someone who chose
    /// «Plain» to quiet the app down still got colour plates in the panel — the
    /// surface they actually look at. The mechanics live here because they are
    /// the same three lines at every root; where the value comes from is
    /// `HelmApp`'s, which is what the closure is.
    func helmTracksModuleIconStyle(_ current: @escaping () -> SidebarStyle) -> some View {
        modifier(HelmModuleIconStyleTracker(current: current))
    }
}

private struct HelmModuleIconStyleTracker: ViewModifier {
    let current: () -> SidebarStyle
    @State private var style: SidebarStyle?

    func body(content: Content) -> some View {
        content
            .environment(\.helmModuleIconStyle, style ?? current())
            .onReceive(NotificationCenter.default.publisher(for: .helmSidebarStyleChanged)) { _ in
                style = current()
            }
    }
}
