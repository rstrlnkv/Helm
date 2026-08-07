import Foundation

/// Everything the keyboard module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum LayoutCommand: String, CaseIterable, Sendable {
    case fix
    case convertSelection
    case settingsChanged
}

/// Everything the engine says about itself.
///
/// One name, and it was a literal in the engine's `emit` and a literal again in
/// the view model's `guard event.name == …`. The fifth module found with that
/// pair. What it costs is quiet: the engine keeps publishing, the `guard` keeps
/// not matching, and the page shows the state it launched with — which for this
/// module is «no conversions yet», forever.
public enum LayoutEvent: String, Sendable {
    /// The language, the badge, and the last conversion.
    case layoutState
}
