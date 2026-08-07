import Foundation

/// Everything Keep Awake's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum KeepAwakeCommand: String, CaseIterable, Sendable {
    case toggle
    case start
    case stop
    case settingsChanged
}

/// Everything the engine says about itself.
///
/// One name, and it was a literal in the engine's `emit` and a literal again in
/// the view model's `guard event.name == …`. The module's own history says what
/// that costs: `ModuleViewModel` decoded a payload named `state` that VPN also
/// emits under a different shape, and five properties sat at their defaults
/// forever because nothing failed loudly. Both targets read this file.
public enum KeepAwakeEvent: String, Sendable {
    /// Held or not, why, and until when.
    case state
}

/// How long a timed session runs. It was `private struct StartPayload` in the
/// engine and `struct P { let minutes: Int }` inside a free function in the
/// panel tile — the very shape `StatePayload`'s doc comment says was fixed once
/// and then re-created: two declarations matched by field name across a JSON
/// hop with no compiler in between.
public struct KeepAwakeStart: Codable, Sendable {
    public let minutes: Int
    public init(minutes: Int) { self.minutes = minutes }
}
