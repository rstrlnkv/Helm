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
    public static func announce(_ firing: VPNAutomation, notice: VPNNotice,
                                authorized: Bool, port: AutomationNoticePort) async {
        guard notice.effective(bannerAuthorized: authorized).postsBanner else { return }
        await port.post(title: Words.title(firing.kind), body: Words.body(firing))
    }

    /// The banner's words, in English only — **all eight languages are still
    /// owed, and Task 9 owes them.**
    ///
    /// They cannot go through `L()` where they are needed: `L()` lives in
    /// `HelmUI`, and an engine target depends on `HelmContract` + `HelmRuntime`
    /// alone, which is what keeps the engines testable without a UI. This is
    /// the first engine-side string in the app, so no module has had to answer
    /// this before; the answer is either to hand the words in from the UI side
    /// or to move `L()` down into `HelmRuntime`.
    ///
    /// The translations are not a translation job: macOS ships this exact
    /// sentence in all eight in
    /// `Network.appex/Contents/Resources/Localizable.loctable` — `VPN_CONNECTED`
    /// is `%@ is connected`, `%@ подключен`, `„%@“ ist verbunden`, `%@已连接`.
    /// Read it out of there rather than translating it again
    /// (ARCHITECTURE.md § Localization).
    enum Words {
        static func title(_ kind: VPNAutomation.Kind) -> String {
            switch kind {
            case .connected: "VPN connected"
            case .disconnected: "VPN disconnected"
            }
        }

        static func body(_ firing: VPNAutomation) -> String {
            switch firing.kind {
            case .connected: "\(firing.name) is connected"
            case .disconnected: "\(firing.name) is disconnected"
            }
        }
    }
}
