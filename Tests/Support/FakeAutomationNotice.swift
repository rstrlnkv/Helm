import Foundation
import HelmRuntime

/// Stands in for macOS's notification centre, which no test may touch: the real
/// `UNUserNotificationCenter.current()` raises `bundleProxyForCurrentProcess is
/// nil` in any process that is not a bundled app, and an ObjC exception does not
/// fail a case — it ends the whole `swift test` run.
///
/// One shared fake, in `HelmTestSupport`, which every test target depends on.
///
/// It has every state the real one has and no other. The permission is a
/// standing answer macOS keeps, promptable once: `requestAuthorization` moves
/// the state to the answer, and asking from `.denied` cannot grant. A banner
/// posted without the permission is dropped, so `posted` records what somebody
/// was shown, not what was attempted.
///
/// A post can also fail with the permission in hand: `UNUserNotificationCenter.add`
/// throws and `SystemAutomationNotice` logs it and returns, so to the caller
/// a banner nobody saw looks like one they did. `postFails` is that state.
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
    private var _posted: [NoticeText] = []

    /// - Parameters:
    ///   - state: what macOS says now, before anybody asks.
    ///   - answersRequest: what the person taps when the prompt appears. Only
    ///     reachable from `.notDetermined`, which is the only state macOS
    ///     prompts from; nil means the standing answer, unchanged.
    ///   - postFails: macOS took the request and threw: the banner was allowed
    ///     and still never appeared.
    ///   - whileAsking: a prompt can stand on screen for minutes, and a fake
    ///     that answers instantly makes a test of what happens during it
    ///     vacuous. Given one, the ask stalls where macOS's does. A `let`,
    ///     because this class is `@unchecked Sendable` and a field written
    ///     outside the lock guards nothing.
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
        // Counted before the stall, in macOS's order, so a test can see the
        // prompt raised while it is still up.
        lock.withLock { _requests += 1 }
        // Outside the lock: `NSLock` may not be held across a suspension.
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
            guard _state == .authorized, !_postFails else { return }
            _posted.append(NoticeText(title: title, body: body))
        }
    }
}
