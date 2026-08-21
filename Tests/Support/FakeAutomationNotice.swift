import Foundation
import HelmRuntime

/// Stands in for macOS's notification centre, which no test may touch: the real
/// `UNUserNotificationCenter.current()` raises `bundleProxyForCurrentProcess is
/// nil` in any process that is not a bundled app, and an ObjC exception does not
/// fail a case — it ends the whole `swift test` run.
///
/// **It lives here because the reason it did not is no longer true.** There were
/// three copies of this class, and the comment on the richest of them said
/// sharing would mean putting `HelmRuntime` under every test target — a manifest
/// decision nobody had taken. `Package.swift` has taken it: `HelmTestSupport`
/// depends on `HelmRuntime` and `HelmUI` today, for `SealKeyPort` and for
/// `MountedRender`, and every test target already depends on this one. A fourth
/// and fifth copy were about to be written for the scan and sweep channels,
/// which is when a stale reason stops being harmless.
///
/// **It can be everywhere the real one can, and nowhere it cannot.** The
/// permission is a standing answer macOS keeps, promptable exactly once:
/// `requestAuthorization` records the ask and *moves* the state to the answer,
/// so «the person refused, and the guard fired again next week» is a state a
/// test can write down — and asking from `.denied` cannot grant, because macOS
/// answers the standing refusal without prompting anybody. A banner posted
/// without the permission is dropped, so `posted` records what somebody was
/// actually shown rather than what was attempted: recording the attempt would
/// let «the person was told» pass on a notification that went nowhere.
///
/// **And a post can fail with the permission in hand.** `UNUserNotificationCenter.add`
/// throws — a malformed request, a centre that has gone away — and
/// `SystemAutomationNotice` logs it and returns, so from the caller's side a
/// banner nobody saw looks exactly like one they did. `postFails` is that state,
/// and `attempts` is the only way to tell the two apart, which is the shape the
/// real port has.
///
/// Locked rather than actor-isolated because a banner is posted from a detached
/// task while the test reads the result on the main actor.
public final class FakeAutomationNotice: AutomationNoticePort, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: NoticeAuthorization
    private let _answer: NoticeAuthorization?
    private let _postFails: Bool
    private let _whileAsking: (@Sendable () async -> Void)?
    private var _reads = 0
    private var _requests = 0
    private var _attempts = 0
    private var _posted: [NoticeText] = []

    /// - Parameters:
    ///   - state: what macOS says now, before anybody asks.
    ///   - answersRequest: what the person taps when the prompt appears. Only
    ///     reachable from `.notDetermined`, which is the only state macOS
    ///     prompts from; nil means the standing answer, unchanged.
    ///   - postFails: macOS took the request and threw. The permission is not
    ///     the question here — this is the banner that was allowed and still
    ///     never appeared.
    ///   - whileAsking: **a prompt can stand on screen for minutes**, and a fake
    ///     that answers instantly makes any test of what happens *during* it
    ///     vacuous — the subject is over before the code under test is reached.
    ///     Given one, the ask stalls where macOS's does, which is the only
    ///     moment a caller's task can be cancelled between reading the
    ///     permission and posting. A `let` rather than a settable property: this
    ///     class is `@unchecked Sendable`, and a field written on one side of
    ///     the lock guards nothing.
    public init(state: NoticeAuthorization = .authorized,
                answersRequest: NoticeAuthorization? = nil,
                postFails: Bool = false,
                whileAsking: (@Sendable () async -> Void)? = nil) {
        _state = state
        _answer = answersRequest
        _postFails = postFails
        _whileAsking = whileAsking
    }

    /// How many times macOS was *read* — a read prompts nobody, and code that
    /// trusts a remembered answer instead of reading is the defect this counts.
    public var reads: Int { lock.withLock { _reads } }
    /// How many times the person was actually prompted. macOS shows that prompt
    /// once ever, so a second one is a defect rather than a nuisance.
    public var requests: Int { lock.withLock { _requests } }
    /// How many banners were handed to macOS, shown or not.
    public var attempts: Int { lock.withLock { _attempts } }
    /// What the person was actually shown.
    public var posted: [NoticeText] { lock.withLock { _posted } }

    /// Settable, so a test can revoke the permission behind the app's back —
    /// the only way System Settings ever does it.
    public var state: NoticeAuthorization {
        get { lock.withLock { _state } }
        set { lock.withLock { _state = newValue } }
    }

    public func authorizationState() async -> NoticeAuthorization {
        lock.withLock { _reads += 1; return _state }
    }

    public func requestAuthorization() async -> NoticeAuthorization {
        // Counted *before* the stall, in the order macOS does it: the request is
        // made, the prompt stands, the person answers. Counting afterwards would
        // make «the prompt was actually raised» unreadable from outside while it
        // is up, which is the one moment a test of the wait has to look at.
        lock.withLock { _requests += 1 }
        // Outside the lock, because it is `async` and the lock is not — and
        // `NSLock` may not be held across a suspension in any case.
        await _whileAsking?()
        return lock.withLock {
            // Only `.notDetermined` puts a prompt on screen; from either settled
            // state macOS answers what it already holds.
            if _state == .notDetermined, let answer = _answer { _state = answer }
            return _state
        }
    }

    public func post(title: String, body: String) async {
        lock.withLock {
            _attempts += 1
            guard _state == .authorized, !_postFails else { return }
            _posted.append(NoticeText(title: title, body: body))
        }
    }
}
