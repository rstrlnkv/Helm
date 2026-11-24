import Foundation
import HelmRuntime

/// Credentials some VPNs (L2TP/IPSec) need at connect time; a VPN that connects
/// on its own (IKEv2) is answered `VPNCredentialRead.notNeeded`. Secrets never
/// reach an argument list, the environment, a file or the log.
public struct VPNCredentials: Equatable, Sendable {
    var user: String?
    var password: String?
    var secret: String?
    init(user: String? = nil, password: String? = nil, secret: String? = nil) {
        self.user = user; self.password = password; self.secret = secret
    }
}

/// What a credential read found — **four answers, because an optional would
/// fold three of them into one nil.**
///
/// «This configuration keeps no secret Helm has to supply» (IKEv2, WireGuard —
/// the ordinary case) and «there is one, in the System keychain, and this caller
/// may not open the dialog macOS guards it with» (an automatic connect against an
/// empty cache — the tunnel cannot come up) need different words: folded, the
/// engine could only warn under every automatic connect or say nothing.
///
/// **`.unreadable` is neither of those.** A read that timed out or failed says
/// nothing about whether a secret is kept: as `.notNeeded` it would start and
/// announce a connect that may need one, and as `.behindAPrompt` it would send
/// the person to press Connect for a prompt that is not the problem
/// (Architecture/ModulePattern.md § Module pattern: the port answers the
/// question it is actually being asked).
public enum VPNCredentialRead: Equatable, Sendable {
    /// Read, and usable: the secret is in hand. Only ever built with a non-empty
    /// secret — the fake stands where the real port stands, and a `.ready` with
    /// nothing in it is a state neither can produce.
    case ready(VPNCredentials)
    /// This configuration keeps no secret Helm supplies. `scutil --nc start`
    /// connects it on its own, and there is nothing to say to anybody.
    ///
    /// **Two reasons give this answer:** `scutil --nc show` ran to the end and
    /// printed no `AuthPassword` field — the configuration keeps no secret (the
    /// ordinary case) — or printed nothing at all. A show that exited non-zero or
    /// timed out is not either: that is `.unreadable`.
    case notNeeded
    /// The configuration could not be read, so nobody knows whether a secret is
    /// kept: `scutil --nc show` timed out or exited non-zero (whatever it
    /// printed before — a half-printed `AuthPassword` field is not trusted).
    /// **A connect on this answer neither starts nor announces.** A start without
    /// a secret the configuration may need reports success whether it worked or
    /// not, so a rule would announce "connected" with no tunnel. The person's press says so
    /// (`VPNFailure.Reason.secretUnreadable`); a rule's connect logs it. Not
    /// `.behindAPrompt`: no prompt is the problem, and the next connect asks again.
    case unreadable
    /// There is a secret and this read did not get it: it lives in the System
    /// keychain, which macOS gates behind an authorization dialog. For an
    /// automatic connect that is Helm declining to ask — not the tool refusing —
    /// and it is the one answer the person has to be told about, because until
    /// somebody presses Connect the rule cannot work.
    case behindAPrompt
}

/// Runs `scutil` with the given args and hands back everything it answered.
///
/// **The status is half the answer.** A bare `String` would make `scutil`
/// succeeding silently — which is how it reports a connect it performed — and
/// `scutil` never running at all one empty string, so a tool that did not run
/// would be announced as a tunnel that came up, and no fake could separate what
/// the port had folded together (Architecture/ModulePattern.md § Module pattern).
///
/// `HelmProcess.Result` rather than a type of this module's own: it is already
/// the shape of "what a command-line tool answered", and there is one of those.
///
/// **A start that carries a secret is a second entry point, not a longer
/// argument list.** `scutil --nc start` takes `--user`, `--password` and
/// `--secret` only as arguments, which stand in `ps auxww` for every process of
/// this user while the child lives, and it has no terminal form. The secret goes
/// to the system in process instead (`SCNetworkConnectionStart`), so the answer
/// is its own enum: the tool's printed sentence does not exist on this path.
///
/// **Two entry points, because a read and a command are not bounded alike.**
/// `read(_:timeout:)` is for the queries (`--nc list`, `status`, `show`): a
/// `scutil` that does not answer is ended at the deadline and the answer is
/// `HelmProcess.timedOutStatus` with no output, so the module's one serial queue
/// is never parked behind it. `run(_:)` is for `--nc start` and `stop`, which
/// change state and are not cut short.
public protocol VPNRunnerPort: AnyObject {
    /// A command, unbounded.
    func run(_ args: [String]) -> HelmProcess.Result
    /// A read-only query, ended at `timeout` seconds with `timedOutStatus`.
    func read(_ args: [String], timeout: TimeInterval) -> HelmProcess.Result
    /// Starts the configuration called `name`, handing the system `credentials`
    /// without any process seeing them. The answer names three reasons and no
    /// text: no configuration by that name in the list the system gave, the
    /// system's configuration unreadable (so nothing is known about the name),
    /// the system refusing the start with its `SCError`, or the start taken.
    func start(_ name: String, supplying credentials: VPNCredentials) -> VPNStartAnswer
}

/// How long a read-only `scutil` query may take: it is local IPC to the network
/// configuration daemon and answers in milliseconds, so five seconds clears a
/// loaded Mac many times over and still frees the queue inside one sitting
/// (Homebrew's ninety seconds is for queries that reach the network).
let vpnReadDeadline: TimeInterval = 5

/// Why a read answered nothing, in the words the log carries.
func vpnReadFailureReason(_ status: Int32) -> String {
    status == HelmProcess.timedOutStatus ? "timed out after \(Int(vpnReadDeadline)) s" : "exit status \(status)"
}

/// What `VPNRunnerPort.start(_:supplying:)` found. **No text, so no name in
/// it** — the system's error is a number, and a number names nobody's VPN.
public enum VPNStartAnswer: Equatable, Sendable {
    /// The system took the start. Like `scutil` saying nothing, this is not yet a
    /// tunnel that is up; the poll that follows reads that.
    case started
    /// The current network set was read and holds no configuration of that name.
    case noSuchService
    /// The set, the service or its connection could not be read, so the name is
    /// neither found nor missing.
    case unreadable
    /// The system refused it, with the `SCError` it gave.
    case refused(code: Int32)
}

/// Supplies the user, password and secret for a keychain-backed VPN: a `.ready`
/// goes to `VPNRunnerPort.start(_:supplying:)` in process, as no argument.
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
///   Connect. That answer is a state the screen draws, not a silence.
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
    /// alone would let a bundle nobody signed raise and drop somebody's tunnel
    /// (`VPNRuleTrust`). Nil is «could not tell», which is treated as no rule
    /// rather than as permission.
    func identity(of bundleID: String) -> CodeIdentity?
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    /// Ends the observation, so no further change is reported. The engine calls it
    /// from `deactivate()` and `deinit`; a second `startObserving` after it arms
    /// the observer once, it never stacks.
    func stopObserving()
}

/// Notifies when the machine's network configuration or state changes.
///
/// A tunnel can be raised from the macOS menu bar, dropped by the network, or
/// stopped in System Settings, and none of that comes back through Helm. The
/// port carries no detail: what changed is `scutil`'s answer to give, and the
/// engine re-reads the list either way.
///
/// `stopObserving` is not optional courtesy: the host calls `deactivate()` and
/// drops the engine, and a callback still holding it holds freed memory
/// (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
public protocol NetworkWatchPort: AnyObject {
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

/// Which interface the machine's default route goes out of, and what an
/// interface has carried.
///
/// Two questions rather than one call answering both, because they fail
/// separately: the machine always has some default route (or none, when it is
/// offline), and an interface that has gone has no counters even though its name
/// is still known.
///
/// **Which interface a given tunnel is on is not asked here.** The id the module
/// has comes from `scutil --nc list` — the identifier of a *configuration*, which
/// is the identifier of a *network service* only for classic PPP/IPSec — so a
/// lookup in `State:/Network/Service/<id>/IPv4` answers nil for every
/// NetworkExtension tunnel. The question is `scutil`'s, asked by name through
/// `VPNRunnerPort` and read by `VPNStatusParser`, and a fake cannot be planted
/// with a pair the system cannot produce.
public protocol VPNInterfacePort: AnyObject {
    /// The interface carrying the default route, or nil when the machine has
    /// none (a Mac with no network at all) or when the store could not be read.
    /// A nil here does not mean the machine is offline.
    func primaryInterface() -> String?
    /// What that interface has carried, or nil when the kernel has no counters
    /// for it.
    ///
    /// A port rather than a call straight to `VPNInterfaceCounters`, because a
    /// counter is the one thing about a tunnel that moves while nobody touches
    /// it: what that costs the page is a decision this module makes
    /// (`VPNInterfaceCounters.onTheWire`), and a decision needs a fake that can
    /// carry a packet between two readings for anything to test it with.
    func bytes(on interface: String) -> (in: UInt64, out: UInt64)?
}

/// What the machine looks like from outside: a two-letter region code, or nil
/// when nothing could be read.
///
/// **The address itself never leaves this port.** The verdict on screen names a
/// country and the log names neither, so there is nowhere for an address to be kept — and a port that
/// never returns one cannot leak one later.
public protocol VPNExitPort: AnyObject {
    func regionCode() async -> String?
}

/// One measurement of the link, bound to an interface when the caller knows it.
public protocol VPNSpeedPort: AnyObject {
    /// **This blocks its thread for `NetworkQualitySpeed.typicalRun`, and up to sixty at
    /// its deadline. Never call it on the module's serial queue.**
    ///
    /// Said at the protocol because the cost is not visible at the call site:
    /// `networkQuality` measures by moving real traffic, so the implementation is
    /// a subprocess this waits out. On `VPNWorkQueue` that is the whole module
    /// deaf, and on the cooperative pool it is one of the machine's few pool
    /// threads held for the same time. `VPNEngine.measureSpeed` goes through
    /// `offTheCooperativePool` and comes back to the queue only to write what it learned.
    ///
    /// Nil when the tool did not run, was killed at its deadline, or printed
    /// something this build cannot read.
    func measure(onInterface: String?) -> VPNSpeedReading?
}

// MARK: - Banners

// `AutomationNoticePort`, `NoticeAuthorization` and the `UNUserNotificationCenter`
// implementation live in `HelmRuntime`: Keep Awake posts a banner too. What stays
// here is this module's own policy about *when* to ask and when to post.

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
    /// revoked in System Settings at any moment and nothing tells the app, and
    /// this is the one instant where being wrong costs the person the news:
    /// `.system` suppresses the menu-bar name because the banner is meant to
    /// carry it, so a stale yes means nothing is said. `authorizationState()`
    /// prompts nobody, which makes asking on every firing affordable.
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
    /// The words come in already written: `L()` lives in `HelmUI`, which an
    /// engine cannot import. The decision stays here, pure and tested; `VPNStr`
    /// writes the banner and `VPNViewModel` hands it over.
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
