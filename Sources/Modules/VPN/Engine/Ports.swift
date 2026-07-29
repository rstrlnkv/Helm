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

// MARK: - Banners

/// What macOS says about this app's permission to post banners.
public enum NoticeAuthorization: Sendable {
    case notDetermined, authorized, denied
}

/// Posts a macOS banner, and answers for the permission macOS gates it behind.
///
/// Reading the state and asking for it are separate calls on purpose: reading
/// prompts nobody, asking prompts once and is never undone. `AutomationNotice`
/// is the only thing that decides which of the two happens.
public protocol AutomationNoticePort: AnyObject, Sendable {
    func authorizationState() async -> NoticeAuthorization
    func requestAuthorization() async -> NoticeAuthorization
    func post(title: String, body: String) async
}

/// Who gets asked for a permission, and what the banner says when a rule fires.
public enum AutomationNotice {

    /// The permission the chosen mode needs, asked for only if that mode is the
    /// one that posts banners.
    ///
    /// Called when the person picks a mode, and nowhere else — never at launch.
    /// A permission asked for before anything wants it is the one people learn
    /// to refuse, and macOS lets an app ask exactly once.
    public static func prepare(for notice: VPNNotice,
                               port: AutomationNoticePort) async -> NoticeAuthorization {
        notice.postsBanner ? await port.requestAuthorization() : await port.authorizationState()
    }

    /// Says a rule fired, in the one mode that says it with a banner.
    ///
    /// Routed through `effective(bannerAuthorized:)` rather than through
    /// `postsBanner` directly, so a refused banner falls back to the menu-bar
    /// label — which posts nothing here — instead of to silence.
    ///
    /// The words come in already written. `L()` lives in `HelmUI`, which an
    /// engine target cannot import, and moving `L()` down into `HelmRuntime` to
    /// serve one sentence would put the app's whole string layer under every
    /// engine. So the decision stays here, where it is pure and tested, and the
    /// caller that already speaks eight languages says it: `VPNStr` writes the
    /// banner, `VPNViewModel` hands it over.
    public static func announce(notice: VPNNotice, authorized: Bool,
                                title: String, body: String,
                                port: AutomationNoticePort) async {
        guard notice.effective(bannerAuthorized: authorized).postsBanner else { return }
        await port.post(title: title, body: body)
    }
}
