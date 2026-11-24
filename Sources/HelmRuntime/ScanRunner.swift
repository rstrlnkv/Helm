import Foundation

/// The arithmetic a background scan runs on.
///
/// **Here rather than in `ScanCoordinator`**, so a test per verdict holds it,
/// ordering included. What stays in the coordinator is the clock, the observer
/// and the call into the engine: the parts that need a running app.
/// Architecture/BackgroundScans.md § Background scans.
public enum ScanRunner {

    /// Which modules have a background scan.
    ///
    /// A literal list, deliberately: a module gaining a scan costs a walk of the
    /// volume, and should take an edit rather than follow from a protocol
    /// somebody conformed to. Beside the schedule, so a test can hold it against
    /// the registry.
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
        var systemSeconds: TimeInterval
        var readAt: Date

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
    /// nothing while the person has not moved. Its default interval is
    /// `ScanSchedule.idleThreshold`, so trusting the counter would mean no scan
    /// ever runs with that switch on.
    ///
    /// No formula over one reading answers this: two readings of a counter
    /// reset by a known event do. So the estimate accumulates across ticks, and
    /// a reset clears it only when it was somebody's hand rather than ours.
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
