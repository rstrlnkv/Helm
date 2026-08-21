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

/// Whether the battery veto's arrival is worth interrupting somebody for.
///
/// Pure, and separate from the engine that calls it, because it is a rule rather
/// than a side effect: the arrival that is *not* news is the whole difference
/// between a notification and a nuisance.
enum BatteryVetoNews {

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

    /// The permission, at the moment something wants it — and this module's own
    /// reason for asking *here*.
    ///
    /// VPN asks when the person picks the banner mode, which is a gesture with
    /// somebody present. This guard has no such gesture: it ships **on**, so the
    /// people it protects are mostly people who never opened its row, and a
    /// permission asked for at launch is the one people learn to refuse. So it
    /// is asked at the first moment there is something to say — and only ever
    /// once, because that is all macOS allows.
    ///
    /// The conversation itself is `NoticeChannel.tell`'s, in `HelmRuntime` —
    /// read the permission, ask once if macOS has never been asked, post if it
    /// may — since the scan and sweep channels ask macOS the same question in
    /// the same order. What stays here is the reason above, and the line below:
    /// a silence because macOS refuses and a silence because the module was
    /// switched off while the prompt stood are different facts, and only the
    /// first is worth saying.
    static func tell(_ port: AutomationNoticePort, _ words: NoticeText) async {
        switch await NoticeChannel.tell(port, words) {
        case .notAllowed:
            HelmLog.shared.info(KeepAwakeEngine.moduleID, "the battery guard's stop was not announced: "
                                + "macOS says banners are not allowed")
        // Nothing to say about either: the banner arrived, or the module was
        // switched off while the prompt stood and its own teardown is the
        // account of that. No `default` — a fourth outcome is a decision.
        case .posted, .cancelled:
            break
        }
    }
}
