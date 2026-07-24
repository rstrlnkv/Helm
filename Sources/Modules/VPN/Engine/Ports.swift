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
