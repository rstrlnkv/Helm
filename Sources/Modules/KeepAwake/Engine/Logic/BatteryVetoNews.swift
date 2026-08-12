import HelmRuntime

/// Where the battery veto's one notification goes, and the words for it.
///
/// **One value rather than two settings on the engine.** A port with no sentence
/// is as silent as a sentence with no port, and neither half means anything
/// alone — so the half-configured pair is a state worth making unrepresentable
/// rather than a pair of optionals to check.
///
/// The words are a function of the floor because the floor is a setting somebody
/// can move while the app runs, and they are written *outside* the engine
/// because `L()` lives in `HelmUI`, which no engine target may import.
public struct BatteryVetoChannel: Sendable {
    let port: AutomationNoticePort
    let words: @Sendable (Int) -> NoticeText

    public init(port: AutomationNoticePort, words: @escaping @Sendable (Int) -> NoticeText) {
        self.port = port
        self.words = words
    }
}

/// Whether the battery veto's arrival is worth interrupting somebody for, and
/// what to do about the permission that would carry it.
///
/// Pure, and separate from the engine that calls it, because both halves are
/// rules rather than side effects: the arrival that is *not* news is the whole
/// difference between a notification and a nuisance.
enum BatteryVetoNews {

    /// What to do with a notification macOS may never have been asked about.
    ///
    /// Three cases and no `default`: a fourth authorization state has to be
    /// decided here rather than falling into whichever of these the compiler
    /// reaches first. Nested, because it is this rule's answer and not a noun the
    /// rest of the engine target has any use for.
    enum Step {
        /// Nobody has been asked yet, and something wants to be said now.
        case ask
        /// Say it.
        case post
        /// Refused. Not asked again — macOS would not prompt a second time anyway.
        case stayQuiet
    }

    /// Did the veto take anything away?
    ///
    /// The rising edge alone is not news. `recompute` runs from every power
    /// event, so a Mac woken on a low battery vetoes before anybody has asked
    /// for anything, and a banner then names a session that never existed.
    ///
    /// A session that was only **asked for** counts: pressing «15 min» at 5 %
    /// is refused on arrival rather than holding the Mac until the next tick,
    /// and a refusal nobody is told about is this module failing silently at the
    /// one thing it was asked to do. `releaseForBattery` asks the same question
    /// for its log line, from here, so the log and the banner cannot come to
    /// disagree about whether anything happened.
    static func tookSomethingAway(active: Bool, manual: Bool, hasDeadline: Bool) -> Bool {
        active || manual || hasDeadline
    }

    /// The permission, at the moment something wants it.
    ///
    /// VPN asks when the person picks the banner mode, which is a gesture with
    /// somebody present. This guard has no such gesture: it ships **on**, so the
    /// people it protects are mostly people who never opened its row, and a
    /// permission asked for at launch is the one people learn to refuse. So it is
    /// asked here, the first time there is something to say — and only ever
    /// once, because that is all macOS allows.
    static func step(given: NoticeAuthorization) -> Step {
        switch given {
        case .notDetermined: return .ask
        case .authorized: return .post
        case .denied: return .stayQuiet
        }
    }

    /// The whole conversation with macOS, in the order the permission allows.
    ///
    /// Here rather than in the engine because every line of it is `step`'s rule
    /// applied twice — once to what macOS already says, once to what the person
    /// answers — and an engine method spelling that out again is the second copy
    /// of a decision.
    ///
    /// **The permission is read, never remembered.** It can be revoked in System
    /// Settings at any moment and nothing tells the app, and this is the one
    /// instant where being wrong costs somebody the news.
    static func tell(_ port: AutomationNoticePort, _ words: NoticeText) async {
        var heard = await port.authorizationState()
        if step(given: heard) == .ask { heard = await port.requestAuthorization() }
        // A prompt can stand on screen for minutes; the module may be switched
        // off in that time, and the caller cancels this task when it is.
        guard !Task.isCancelled else { return }
        switch step(given: heard) {
        case .post:
            await port.post(title: words.title, body: words.body)
        // `.ask` here is macOS answering «not determined» to a request, which
        // cannot happen — folded in rather than given a `default`, so a fourth
        // authorization state stays a build error in `step` above.
        case .ask, .stayQuiet:
            HelmLog.shared.info("keepawake", "the battery guard's stop was not announced: "
                                + "macOS says banners are not allowed")
        }
    }
}
