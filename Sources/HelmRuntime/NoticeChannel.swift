import Foundation

/// The whole conversation with macOS about one banner, in the order the
/// permission allows.
///
/// Shared by everything that speaks to an empty chair (Keep Awake's battery
/// veto, a background scan's finding, Autopilot's sweep): one conversation
/// cannot prompt somebody twice, or trust a permission revoked an hour ago.
///
/// **Notification authorization is keyed to the bundle identifier**, not to the
/// code signature, so unlike Full Disk Access and Accessibility it survives
/// every ad-hoc rebuild: a grant given once is still there after the next
/// `package-app.sh`. That is why this channel may be built on «ask once, ever»
/// where the two TCC grants cannot be.
public enum NoticeChannel {

    /// What to do with a notification macOS may never have been asked about.
    ///
    /// Internal: `tell` below is the whole interface.
    ///
    /// Three cases and no `default`: a fourth authorization state has to be
    /// decided here rather than falling into whichever of these the compiler
    /// reaches first.
    enum Step: Sendable, Equatable {
        /// Nobody has been asked yet, and something wants to be said now.
        case ask
        /// Say it.
        case post
        /// Refused. Not asked again — macOS would not prompt a second time anyway.
        case stayQuiet
    }

    /// How the conversation ended, so a caller can say the right thing in the
    /// log. Three cases and no `default`, for the same reason as `Step`: a
    /// silence because macOS refuses and a silence because the module was
    /// switched off mid-prompt are different sentences.
    public enum Outcome: Sendable, Equatable {
        case posted
        case notAllowed
        case cancelled
    }

    static func step(given: NoticeAuthorization) -> Step {
        switch given {
        case .notDetermined: return .ask
        case .authorized: return .post
        case .denied: return .stayQuiet
        }
    }

    /// Read the permission, ask once if macOS has never been asked, and post if
    /// it may.
    ///
    /// **The permission is read, never remembered.** It can be revoked in System
    /// Settings at any moment and nothing tells the app; a remembered
    /// `authorized` would be a local flag standing in for a live external fact.
    ///
    /// **The one prompt macOS allows is spent at the first moment there is
    /// something to say**, not at launch, where people learn to refuse it.
    /// Asking from `.denied` is not attempted: macOS answers the standing
    /// refusal without showing anything.
    @discardableResult
    public static func tell(_ port: AutomationNoticePort, _ words: NoticeText) async -> Outcome {
        var heard = await port.authorizationState()
        if step(given: heard) == .ask { heard = await port.requestAuthorization() }
        // A prompt can stand on screen for minutes, and whatever wanted to speak
        // may have been switched off in that time. Callers cancel this task from
        // their own teardown; a banner from a module that no longer exists is
        // worse than none.
        guard !Task.isCancelled else { return .cancelled }
        switch step(given: heard) {
        case .post:
            await port.post(title: words.title, body: words.body)
            return .posted
        // `.ask` here is macOS answering «not determined» to a request, which
        // cannot happen — folded in rather than given a `default`, so a fourth
        // authorization state stays a build error in `step` above.
        case .ask, .stayQuiet:
            return .notAllowed
        }
    }
}
