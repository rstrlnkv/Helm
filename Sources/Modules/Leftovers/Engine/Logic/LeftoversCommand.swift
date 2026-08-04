import Foundation
import HelmRuntime

/// Everything the login-items module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. The
/// unknown-name door stays open one step earlier: a string this enum cannot
/// parse is a command the engine does not know, which is what the transport
/// should say about it.
public enum LeftoversCommand: String, CaseIterable, Sendable {
    case scan
    case setDisabled
    case trash
}
