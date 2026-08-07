import Foundation

/// Everything the Homebrew module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum HomebrewCommand: String, CaseIterable, Sendable {
    case status
    case listInstalled
    case outdated
    case descriptions
    case search
    case install
    case uninstall
    case upgrade
    case upgradeAll
    case installBrew
}

/// Everything the module's engine says while a long operation runs.
///
/// **A name that crosses a target boundary is a constant both sides read.** The
/// engine spelled `"opLog"` and `"opState"` into `EngineEvent`, and the view
/// model spelled them again in the `switch` that receives them — the same
/// literal typed twice, which is an error nowhere. Rename one and the console
/// simply stops filling: the events keep arriving, the `switch` keeps not
/// matching, and nothing anywhere says so. The engine and the UI target both
/// import this file, so there is no reason for two spellings.
public enum HomebrewEvent: String, Sendable {
    /// One line of the tool's output, as it arrives.
    case opLog
    /// Where the operation is now: running, done or failed.
    case opState
}
