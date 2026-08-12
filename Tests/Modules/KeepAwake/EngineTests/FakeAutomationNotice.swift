import Foundation
import HelmRuntime

/// Stands in for macOS's notification centre, which no test may touch: the real
/// `UNUserNotificationCenter.current()` raises `bundleProxyForCurrentProcess is
/// nil` outside an app bundle, and an ObjC exception does not fail a case — it
/// ends the whole run.
///
/// **This is the third fake for one port**, and it is here rather than in
/// `HelmTestSupport` for one reason worth writing down: the harness target
/// declares no dependencies, so sharing it means putting `HelmRuntime` under
/// every test target — including `HelmContractTests`, whose subject is a target
/// that depends on nothing. That is a manifest decision, and until it is taken
/// the two VPN copies and this one are what there is. VPN's are the weaker
/// pair: `FakeNotice` records a post macOS would have dropped.
///
/// **It can be everywhere the real one can, and nowhere it cannot.** The
/// permission is a standing answer macOS keeps, promptable exactly once:
/// `requestAuthorization` records the ask and *moves* the state to the answer,
/// so «the person refused, and the guard fired again next week» is a state a
/// test can write down — and asking from `.denied` cannot grant, because macOS
/// returns the standing refusal without prompting anybody. And a banner posted
/// without the permission is dropped, so `posted` records what somebody was
/// actually shown rather than what was attempted: recording the attempt would
/// let «the person was told» pass on a notification that went nowhere.
///
/// Locked rather than actor-isolated because a banner is posted from a detached
/// task while the test reads the result on the main actor.
final class FakeAutomationNotice: AutomationNoticePort, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: NoticeAuthorization
    private let _answer: NoticeAuthorization?
    private var _reads = 0
    private var _requests = 0
    private var _posted: [NoticeText] = []

    /// - Parameters:
    ///   - state: what macOS says now, before anybody asks.
    ///   - answersRequest: what the person taps when the prompt appears. Only
    ///     reachable from `.notDetermined`, which is the only state macOS
    ///     prompts from; nil means the standing answer, unchanged.
    init(state: NoticeAuthorization = .authorized,
         answersRequest: NoticeAuthorization? = nil) {
        _state = state
        _answer = answersRequest
    }

    /// How many times macOS was *read* — a read prompts nobody, and code that
    /// trusts a remembered answer instead of reading is the defect this counts.
    var reads: Int { lock.withLock { _reads } }
    /// How many times the person was actually prompted. macOS shows that prompt
    /// once ever, so a second one is a defect rather than a nuisance.
    var requests: Int { lock.withLock { _requests } }
    /// What the person was actually shown.
    var posted: [NoticeText] { lock.withLock { _posted } }

    /// Settable, so a test can revoke the permission behind the app's back —
    /// the only way System Settings ever does it.
    var state: NoticeAuthorization {
        get { lock.withLock { _state } }
        set { lock.withLock { _state = newValue } }
    }

    func authorizationState() async -> NoticeAuthorization {
        lock.withLock { _reads += 1; return _state }
    }

    func requestAuthorization() async -> NoticeAuthorization {
        lock.withLock {
            _requests += 1
            // Only `.notDetermined` puts a prompt on screen; from either settled
            // state macOS answers what it already holds.
            if _state == .notDetermined, let answer = _answer { _state = answer }
            return _state
        }
    }

    func post(title: String, body: String) async {
        lock.withLock {
            guard _state == .authorized else { return }
            _posted.append(NoticeText(title: title, body: body))
        }
    }
}
