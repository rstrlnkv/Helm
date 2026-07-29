import Foundation

/// Credentials some VPNs (L2TP/IPSec) need at connect time; nil for VPNs that
/// connect on their own (IKEv2). Secrets never logged.
public struct VPNCredentials: Sendable {
    public var user: String?
    public var password: String?
    public var secret: String?
    public init(user: String? = nil, password: String? = nil, secret: String? = nil) {
        self.user = user; self.password = password; self.secret = secret
    }
}

/// Runs `scutil` with the given args, returns stdout.
public protocol VPNRunnerPort: AnyObject {
    func run(_ args: [String]) -> String
}

/// Supplies --user/--password/--secret for a keychain-backed VPN.
public protocol VPNCredentialsPort: AnyObject {
    func credentials(for name: String) -> VPNCredentials?
}

/// Reports currently-running app bundle IDs and notifies on any change; the
/// engine computes launch/quit diffs itself.
public protocol AppObserverPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
}

/// Notifies when the machine's network configuration or state changes.
///
/// A tunnel can be raised from the macOS menu bar, dropped by the network, or
/// stopped in System Settings, and none of that comes back through Helm. The
/// port carries no detail: what changed is `scutil`'s answer to give, and the
/// engine re-reads the list either way.
///
/// `stopObserving` is not optional courtesy — ARCHITECTURE.md § "An observer
/// outlives the thing it points at": the host calls `deactivate()` and drops
/// the engine, and a callback still holding it holds freed memory.
public protocol NetworkWatchPort: AnyObject {
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}
