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
