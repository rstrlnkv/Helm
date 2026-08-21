import Foundation
import HelmRuntime

/// Which unattended pass is worth interrupting somebody for, and with what.
///
/// `SweepAnnouncement` next door decides which pass gets a **log line**; this
/// decides which gets a **banner**, and the two are deliberately different
/// questions. The log may carry every hour of an idle sentinel because nobody
/// reads it until something has gone wrong. A banner is read whether or not it
/// was worth reading, so an hourly sweep that announced itself would be an
/// hourly banner — and a channel switched off after a day cannot tell anybody
/// the one thing that matters.
///
/// Over the pass's own records rather than its `SweepReport`, and that is the
/// point: the sweep and the FSEvents leg each build `[ActionRecord]` and neither
/// builds the other's numbers, so one rule read from one structure is what keeps
/// the two triggers from drifting into different ideas of what is news.
///
/// Only `Tally`'s three counts cross the target boundary — the UI writes the
/// sentence from them — so only those are public. Everything else is answered
/// inside this target, and `public` here means «another target uses this» and
/// nothing else.
public enum SweepNews {

    /// What a pass did that somebody would want to know about, per kind.
    ///
    /// The three are not folded into one number. A file in the Trash, a rule the
    /// gate refused and a move the filesystem rejected are three different
    /// things to do about it, and a banner reading «3 problems» is a banner that
    /// sends the person to the log to find out which.
    public struct Tally: Equatable, Sendable {
        public let trashed: Int
        public let refused: Int
        public let failed: Int

        /// Whether there is anything to say at all.
        var isSomething: Bool { trashed + refused + failed > 0 }

        /// Two folders swept in one pass are one banner, so the tallies add.
        static func + (lhs: Tally, rhs: Tally) -> Tally {
            Tally(trashed: lhs.trashed + rhs.trashed,
                  refused: lhs.refused + rhs.refused,
                  failed: lhs.failed + rhs.failed)
        }
    }

    /// What a pass did, whether or not it is worth saying.
    ///
    /// The switch is exhaustive with no `default`: a seventh kind of action has
    /// to be decided here — is this something Helm can take back? — rather than
    /// falling silently into the tidy half.
    static func tally(of records: [ActionRecord]) -> Tally {
        var trashed = 0, refused = 0, failed = 0
        for record in records {
            switch record.kind {
            case .trashed: trashed += 1
            case .refused: refused += 1
            case .failed: failed += 1
            // **A move it can undo and has recorded in History stays silent.**
            // Undoing it is one press on a page that is already keeping the
            // account, so the banner would be telling somebody about something
            // they can see whenever they like.
            case .moved, .renamed, .tagged: break
            }
        }
        return Tally(trashed: trashed, refused: refused, failed: failed)
    }

    /// The pass a banner may be posted about, or nil for silence.
    static func worthTelling(_ records: [ActionRecord]) -> Tally? {
        let counted = tally(of: records)
        return counted.isSomething ? counted : nil
    }
}

/// Where an unattended pass's one banner goes, the words for it, and the task
/// that waits on macOS.
///
/// **One value rather than three settings on the engine**, the shape
/// `BatteryVetoChannel` already has one module over: a port with no sentence is
/// as silent as a sentence with no port, so the half-configured pair is made
/// unrepresentable rather than left as optionals to check. The words are written
/// outside the engine because `L()` lives in `HelmUI`, which no engine target
/// may import.
///
/// The **task** lives here too, and that is the part `BatteryVetoChannel` leaves
/// to its engine. Nothing in the engine waits for macOS — a notification prompt
/// can stand on screen for minutes — so somebody has to hold the task and cancel
/// it when the module is switched off, and the object that owns the port is the
/// one that can do it without the engine growing a second field to forget.
///
/// Locked rather than actor-isolated: `tell` arrives from the engine's own
/// serial queue on the FSEvents leg and from the sweep timer on the other, and
/// `cancel` from `deactivate` on the main actor.
public final class SweepNotifier: @unchecked Sendable {
    private let port: AutomationNoticePort
    private let words: @Sendable (SweepNews.Tally) -> NoticeText
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(port: AutomationNoticePort,
                words: @escaping @Sendable (SweepNews.Tally) -> NoticeText) {
        self.port = port
        self.words = words
    }

    /// A banner about a pass nobody watched, or silence.
    ///
    /// What is worth saying is `SweepNews`'; the conversation with macOS is
    /// `NoticeChannel`'s. Holds nothing of the engine, so a task waiting on a
    /// prompt cannot keep it alive on its own.
    ///
    /// One task, replaced rather than accumulated: two unattended passes
    /// overlapping means a prompt still standing an hour later, which macOS
    /// answers once and for all anyway.
    func tell(_ records: [ActionRecord]) {
        guard let tally = SweepNews.worthTelling(records) else { return }
        let said = words(tally)
        let centre = port
        let started = Task {
            switch await NoticeChannel.tell(centre, said) {
            case .notAllowed:
                HelmLog.shared.info(AutopilotEngine.moduleID, "the sweep was not announced: "
                                    + "macOS says banners are not allowed")
            // Nothing to say about either: the banner arrived, or the module was
            // switched off while the prompt stood and `cancel` is the account of
            // that. No `default` — a fourth outcome is a decision.
            case .posted, .cancelled:
                break
            }
        }
        lock.withLock {
            task?.cancel()
            task = started
        }
    }

    /// The module has been switched off. A banner about it now is worse than
    /// none — and the task retains nothing, so this is about the banner rather
    /// than about the memory.
    func cancel() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }
}
