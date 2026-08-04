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
