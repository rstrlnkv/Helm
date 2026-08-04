import Foundation

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
