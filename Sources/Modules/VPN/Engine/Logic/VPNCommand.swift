import Foundation

/// Everything the VPN module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum VPNCommand: String, CaseIterable, Sendable {
    case toggle
    case connect
    case disconnect
    case refresh
    case reloadRules
    /// One `networkQuality` run against the tunnel carrying the traffic. Asked
    /// for, never scheduled: the tool runs for about fifteen seconds and puts
    /// the link under load while it does, which is a thing to do when somebody
    /// presses a button and not on a timer.
    case measureSpeed
}

/// Everything the engine says about itself.
///
/// One name, and it was a literal in the engine's `emit` and a literal again in
/// the view model's `guard e.name == …`. This module has the sharper version of
/// what that costs written down already: `KeepAwakeViewModel`'s own doc records
/// five properties sitting at their defaults forever because the *host* view
/// model decoded a payload named `state` that this module also emits, under a
/// different shape. The name is shared here; the shape is each module's own.
public enum VPNEvent: String, Sendable {
    /// Connections, what Helm raised, and the last rule firing.
    case state
}

/// Which connection a command is about.
///
/// It crossed the transport as a `private struct NamePayload` in the engine and
/// a `struct P { let name: String }` declared inside `nameData` in the view
/// model. The third module found with that pair — Keep Awake's `StartPayload`
/// and Homebrew's `PkgReq` were the others — and the failure is the same every
/// time: rename the field on one side and the decode returns nil, the handler
/// does nothing, and the button is simply inert.
public struct VPNConnectionRef: Codable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}
