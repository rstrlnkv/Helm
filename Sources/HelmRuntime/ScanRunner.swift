import Foundation

/// The arithmetic a background scan runs on.
///
/// **Here rather than in the coordinator, and that is the whole point.**
/// `ScanCoordinator` lives in `HelmApp` and this lives here, where a test per
/// verdict holds it with its ordering mutation-checked — four defects found in
/// the coordinator on 2026-08-03 could be argued about and not pinned. What is
/// left up there is the clock, the observer and the transport call: the parts
/// that genuinely need a running app.
///
/// This paragraph used to say `HelmApp` had no test target anywhere in
/// `Package.swift`. It has one — `HelmAppTests`, declared there like any other —
/// and the assumption is what `ListsAgreeWithTheTreeTests` was written to
/// disprove. Pure logic still belongs here; the reason is the rigour, not an
/// impossibility.
///
/// The line number that used to be in that sentence is gone: adding one target
/// to the manifest moved it, and a figure nobody re-reads is worse than the
/// name, which `grep` finds.
public enum ScanRunner {

    /// Which modules have a background scan.
    ///
    /// A literal list, deliberately: a module gaining a scan is a decision that
    /// costs a walk of the volume, and it should take an edit rather than
    /// following from a protocol somebody conformed to. The list living beside
    /// the schedule instead of inside the app layer is what lets a test hold it
    /// against the registry.
    public static let scannableModules = ["duplicates", "uninstaller", "disk"]

    // MARK: - Idleness

    /// What the last reading concluded, carried to the next one.
    ///
    /// The estimate is a *floor*: it is never below the system counter, because
    /// a counter that has climbed past it is a counter telling the truth.
    public struct Idle: Equatable, Sendable {
        /// How long the **person** has been away, which is not what the counter
        /// answers once Helm has nudged the pointer.
        public var personSeconds: TimeInterval
        /// What the counter said at this reading, so the next one can tell a
        /// reset from a climb.
        public var systemSeconds: TimeInterval
        public var readAt: Date

        public init(personSeconds: TimeInterval, systemSeconds: TimeInterval, readAt: Date) {
            self.personSeconds = personSeconds
            self.systemSeconds = systemSeconds
            self.readAt = readAt
        }
    }

    /// Fold one reading of the system idle counter into the estimate.
    ///
    /// **The counter cannot tell Helm's own events from a person's.** Keep
    /// Awake's pointer nudge posts a `mouseMoved` and the counter drops to
    /// nothing — measured, 284,97 s to 0,30 s — while the person has not moved.
    /// Its default interval is five minutes, exactly `ScanSchedule.idleThreshold`,
    /// so a caller that trusts the counter finds that no scan ever runs for
    /// anybody with that switch on.
    ///
    /// The first attempt at the discount answered `sinceNudge + system`, and its
    /// own guard fired precisely when those two were equal — so it returned
    /// **roughly double**, and a scan whose threshold is five minutes could
    /// start after two and a half of real stillness. The repair is not a better
    /// formula over one reading: two readings of a counter that was reset by a
    /// known event carry the answer, and one does not. So the estimate
    /// accumulates across ticks, and a reset only clears it when the reset was
    /// somebody's hand rather than ours.
    ///
    /// - Parameter tolerance: the notification and the counter are not read at
    ///   the same instant, so the moment of the reset is compared against the
    ///   nudge with a couple of seconds of slack.
    public static func advance(_ previous: Idle?,
                               systemIdle: TimeInterval,
                               lastOwnNudge: Date?,
                               now: Date,
                               tolerance: TimeInterval = 2) -> Idle {
        guard let previous else {
            return Idle(personSeconds: systemIdle, systemSeconds: systemIdle, readAt: now)
        }
        // A clock corrected backwards must not hand out idleness nobody earned;
        // negative elapsed time is discarded rather than trusted.
        let elapsed = max(0, now.timeIntervalSince(previous.readAt))
        let counterWasReset = systemIdle < previous.systemSeconds
        let resetWasOurs: Bool = {
            guard counterWasReset, let nudge = lastOwnNudge else { return false }
            // When the counter was reset, in wall-clock terms.
            let resetAt = now.addingTimeInterval(-systemIdle)
            return abs(resetAt.timeIntervalSince(nudge)) <= tolerance
        }()

        let person: TimeInterval
        if counterWasReset && !resetWasOurs {
            person = systemIdle             // somebody is at the keyboard
        } else {
            person = previous.personSeconds + elapsed
        }
        return Idle(personSeconds: max(person, systemIdle),
                    systemSeconds: systemIdle, readAt: now)
    }

    // MARK: - The day

    /// Whether the day the budget is counting has turned.
    ///
    /// Against the calendar rather than multiples of 86 400 seconds, because
    /// days are not all the same length — the rule `EventWindows` already
    /// follows. A machine that has never counted rolls over, so the budget
    /// starts from a day rather than from nothing.
    public static func dayRolledOver(storedDay: Date?, now: Date,
                                     calendar: Calendar = .current) -> Bool {
        guard let storedDay else { return true }
        return calendar.startOfDay(for: storedDay) != calendar.startOfDay(for: now)
    }
}
