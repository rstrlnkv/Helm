import Foundation

/// Everything the keyboard module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum LayoutCommand: String, CaseIterable, Sendable {
    case fix
    case settingsChanged
}

/// The chord this module registers with the host, named once.
///
/// Two names, both of which used to be typed on each side of a target boundary —
/// the host registering the shortcut and the page drawing the row for it. Neither
/// half is an error when the other changes: the slot name only has to *match*, so
/// a rename leaves the page asking `HotkeyStatus` about a binding nobody filed;
/// and the store prefix is where the recorded combination lives, so a rename
/// there means somebody's chord is read from keys nothing writes. Both fail the
/// same way — the row draws a shortcut and pressing it does nothing.
///
/// Beside `LayoutCommand` because it is the same kind of fact, and re-exported
/// through the descriptor for the same reason.
public enum LayoutHotkey {
    /// The slot `HotkeyManager` files the binding under, which is this module's
    /// id and the command it sends. Not stored anywhere: it only has to be one
    /// string in two targets.
    public static let fix = "\(LayoutEngine.moduleID).\(LayoutCommand.fix.rawValue)"

    /// Where the recorded combination is kept — `<prefix>KeyCode`,
    /// `<prefix>Modifiers`, `<prefix>Label` inside the module's own store.
    /// **Deployed stored data: this name never moves.** A new shortcut takes a
    /// new prefix instead.
    public static let storePrefix = "convertHotkey"
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
