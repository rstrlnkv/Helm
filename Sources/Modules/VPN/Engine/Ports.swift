import Foundation
import HelmRuntime

/// Credentials some VPNs (L2TP/IPSec) need at connect time; nil for VPNs that
/// connect on their own (IKEv2). Secrets never logged.
public struct VPNCredentials: Equatable, Sendable {
    public var user: String?
    public var password: String?
    public var secret: String?
    public init(user: String? = nil, password: String? = nil, secret: String? = nil) {
        self.user = user; self.password = password; self.secret = secret
    }
}

/// What a credential read found — **three answers, because the nil it replaced
/// was two of them.**
///
/// `credentials(for:promptingAllowed:)` used to answer `VPNCredentials?`, and nil
/// meant either «this configuration keeps no secret Helm has to supply» (IKEv2,
/// WireGuard — the ordinary case, and nothing is wrong) or «there is one, in the
/// System keychain, and this caller may not open the dialog macOS guards it with»
/// (an automatic connect against an empty cache — the tunnel cannot come up and
/// nobody is told). Folded together, the engine could report neither: saying
/// something about every nil would put a warning under every automatic connect on
/// the machine, and saying nothing is what shipped.
///
/// This is the repair ARCHITECTURE.md § A nil from a system read can be folding
/// two questions into one records for `PowerSource.supply()`, in the same shape:
/// the port answers the question it is actually being asked.
public enum VPNCredentialRead: Equatable, Sendable {
    /// Read, and usable: the secret is in hand. Only ever built with a non-empty
    /// secret — the fake stands where the real port stands, and a `.ready` with
    /// nothing in it is a state neither can produce.
    case ready(VPNCredentials)
    /// This configuration keeps no secret Helm supplies. `scutil --nc start`
    /// connects it on its own, and there is nothing to say to anybody.
    case notNeeded
    /// There is a secret and this read did not get it: it lives in the System
    /// keychain, which macOS gates behind an authorization dialog. For an
    /// automatic connect that is Helm declining to ask — not the tool refusing —
    /// and it is the one answer the person has to be told about, because until
    /// somebody presses Connect the rule cannot work.
    case behindAPrompt
}

/// Runs `scutil` with the given args and hands back everything it answered.
///
/// **The status is half the answer, and this port used to drop it.** It returned
/// a bare `String`, so `scutil` succeeding silently — which is how it reports a
/// connect it performed — and `scutil` never running at all were one value: the
/// same empty string, indistinguishable to every caller, though `HelmProcess`
/// had read the status and thrown it away one line earlier. A tool that did not
/// run was therefore announced as a tunnel that came up, and no fake could have
/// caught it, because no fake can separate what the port has already folded
/// together (ARCHITECTURE.md § A nil from a system read is two questions in one).
///
/// `HelmProcess.Result` rather than a type of this module's own: it is already
/// the shape of "what a command-line tool answered", and there is one of those.
public protocol VPNRunnerPort: AnyObject {
    func run(_ args: [String]) -> HelmProcess.Result
}

/// Supplies --user/--password/--secret for a keychain-backed VPN.
///
/// - Parameter promptingAllowed: whether this read may reach somewhere macOS
///   guards with a dialog. **False for anything a rule started.** The secret
///   lives in the System keychain, and a third-party app reading it there is
///   gated behind an authorization prompt attributed to `/usr/bin/security`;
///   `vpnAppRules` is an unsealed plist decoded during `activate()`, so a forged
///   rule otherwise chooses both the configuration and the moment that prompt
///   appears in front of somebody who did nothing. Helm's own cache needs no
///   prompt and stays readable either way, so an automatic connect that has been
///   made once before is unaffected; one that has not answers `.behindAPrompt`,
///   and the System keychain then waits for the gesture of a person pressing
///   Connect. That answer is a state the screen draws, not a silence: giving up
///   quietly is what left a rule reaching the same dead end three times in an
///   hour with only the log to say so.
public protocol VPNCredentialsPort: AnyObject {
    func credentials(for name: String, promptingAllowed: Bool) -> VPNCredentialRead
}

/// Reports currently-running app bundle IDs and notifies on any change; the
/// engine computes launch/quit diffs itself.
public protocol AppObserverPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    /// What the instance running under that identifier is **signed** as, or nil
    /// when nothing could be read.
    ///
    /// A second question because the first one cannot be trusted: a bundle
    /// identifier is a string in a plist anybody can write, and a rule keyed on it
    /// alone let a bundle nobody signed raise and drop somebody's tunnel by
    /// launching and quitting (`VPNRuleTrust`). Nil is «could not tell», which is
    /// treated as no rule rather than as permission.
    func identity(of bundleID: String) -> CodeIdentity?
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

/// Which interface a configuration is on, and which interface the machine's
/// default route goes out of.
///
/// Two questions rather than one call answering both, because they fail
/// separately: a service that is not up has no interface at all, while the
/// machine always has some default route (or none, when it is offline).
public protocol VPNInterfacePort: AnyObject {
    /// e.g. `utun4` for the service with this identifier, or nil when the
    /// service is down or the store could not be read.
    func interface(forServiceID id: String) -> String?
    /// The interface carrying the default route, or nil when the machine has
    /// none — which is the honest answer for a Mac with no network at all.
    func primaryInterface() -> String?
}

/// What the machine looks like from outside: a two-letter region code, or nil
/// when nothing could be read.
///
/// **The address itself never leaves this port.** The verdict on screen names a
/// country and the log names neither (CLAUDE.md § The log carries no names), so
/// there is nowhere for an address to be kept — and a port that never returns
/// one cannot leak one later.
public protocol VPNExitPort: AnyObject {
    func regionCode() async -> String?
}

/// One measurement of the link, bound to an interface when the caller knows it.
public protocol VPNSpeedPort: AnyObject {
    /// Nil when the tool did not run, was killed at its deadline, or printed
    /// something this build cannot read.
    func measure(onInterface: String?) -> VPNSpeedReading?
}

// MARK: - Banners

// `AutomationNoticePort`, `NoticeAuthorization` and the `UNUserNotificationCenter`
// implementation of the port live in `HelmRuntime`: Keep Awake's battery veto
// needed a banner too, and a port two modules speak is plumbing. What stays here
// is this module's own policy about *when* to ask and when to post, below.

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

    /// Says a rule fired, in the one mode that says it with a banner, and
    /// answers what macOS said about banners while it was there.
    ///
    /// **It asks macOS now rather than being told.** The permission can be
    /// revoked in System Settings at any moment and nothing tells the app; a
    /// stored mirror of the last answer is therefore a memory, and this is the
    /// one instant where being wrong costs the person the news — `.system`
    /// suppresses the menu-bar name because the banner is meant to carry it, so
    /// a stale yes means macOS drops the banner and nothing else is said.
    /// Measured: the ring turned for 1.1 s and the connection was never named.
    /// `authorizationState()` is a read that prompts nobody, which is what
    /// makes asking on every firing affordable.
    ///
    /// Only the banner mode asks: for the other two the answer cannot change
    /// what happens, and a permission nobody needs is not worth a question.
    /// Hence the optional — nil is "macOS was not asked", not "no".
    ///
    /// Routed through `effective(bannerAuthorized:)` rather than through
    /// `postsBanner` directly, so a refused banner falls back to the menu-bar
    /// label — which posts nothing here — instead of to silence. The caller
    /// puts the returned answer where the label decision reads it.
    ///
    /// The words come in already written. `L()` lives in `HelmUI`, which an
    /// engine target cannot import, and moving `L()` down into `HelmRuntime` to
    /// serve one sentence would put the app's whole string layer under every
    /// engine. So the decision stays here, where it is pure and tested, and the
    /// caller that already speaks eight languages says it: `VPNStr` writes the
    /// banner, `VPNViewModel` hands it over.
    @discardableResult
    public static func announce(notice: VPNNotice, title: String, body: String,
                                port: AutomationNoticePort) async -> NoticeAuthorization? {
        guard notice.postsBanner else { return nil }
        let heard = await port.authorizationState()
        guard notice.effective(bannerAuthorized: heard == .authorized).postsBanner else {
            return heard
        }
        await port.post(title: title, body: body)
        return heard
    }
}
