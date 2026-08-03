import Foundation

public extension Notification.Name {
    /// Posted by Keep Awake each time it moves the pointer itself.
    ///
    /// Declared here rather than in that module because the listener is
    /// `ScanCoordinator` in `HelmApp`, and neither target can see the other's:
    /// a name shared by two strangers belongs to the runtime they both import.
    static let helmPointerNudged = Notification.Name("helmPointerNudged")
}

/// Whether a background scan may run right now.
///
/// Pure, and a function of its arguments alone: a day-long interval is then
/// tested in microseconds, and every condition below is a sentence somebody can
/// disagree with rather than a number buried in a timer.
///
/// The caller gathers the facts. That split is deliberate — reading the idle
/// counter and the power source are two different kinds of unreliable, and
/// neither belongs in the middle of a decision.
public enum ScanSchedule {

    /// Everything the decision needs, gathered by the caller.
    public struct Conditions: Equatable, Sendable {
        public let now: Date
        /// Nil on a machine that has never run this scan.
        public let lastRun: Date?
        /// Seconds since the person last touched keyboard, mouse or trackpad.
        public let idleSeconds: TimeInterval
        public let onMains: Bool
        /// How many times this scan already ran today.
        public let runsToday: Int
        /// The switch in Settings.
        public let isEnabled: Bool
        /// This session owns the console.
        public let onConsole: Bool
        public let screenLocked: Bool

        public init(now: Date, lastRun: Date?, idleSeconds: TimeInterval,
                    onMains: Bool, runsToday: Int, isEnabled: Bool,
                    onConsole: Bool = true, screenLocked: Bool = false) {
            self.now = now
            self.lastRun = lastRun
            self.idleSeconds = idleSeconds
            self.onMains = onMains
            self.runsToday = runsToday
            self.isEnabled = isEnabled
            self.onConsole = onConsole
            self.screenLocked = screenLocked
        }
    }

    /// Why, not only whether — the Settings row says what it is waiting for, and
    /// "waiting for mains" is a different sentence from "not due yet".
    public enum Verdict: Equatable, Sendable {
        case run
        case off
        case busy
        case onBattery
        case notDue
        case spent
        /// The stored `lastRun` is in the future: a restored backup, or a clock
        /// set forward and corrected.
        case clockSkew
        /// Somebody else is at the console, or the screen is locked.
        case notAtTheConsole
    }

    /// Five minutes. Two minutes of stillness is a person reading; five is a
    /// person who left.
    public static let idleThreshold: TimeInterval = 300
    /// Once a day, with a second run allowed for the case where the first was
    /// cut short — and no more, so a wrong clock cannot spend the afternoon
    /// reading the volume.
    public static let runsPerDay = 2
    public static let interval: TimeInterval = 24 * 3600

    /// The order is the decision. Each guard below is above the next because
    /// getting it wrong tells the person something untrue about their own Mac.
    public static func verdict(_ c: Conditions) -> Verdict {
        // The person's answer outranks the machine's state. Reporting "your Mac
        // is busy" for a scan they switched off would be a lie in the one place
        // that exists to explain the delay.
        guard c.isEnabled else { return .off }
        guard c.runsToday < runsPerDay else { return .spent }
        // A `lastRun` in the future reads as **never due**, not as due forever:
        // `timeIntervalSince` is negative and negative is less than a day, so
        // the plain rule below would refuse the scan every minute for thirty
        // days while the Settings row said «не пора».
        if let lastRun = c.lastRun, lastRun > c.now { return .clockSkew }
        if let lastRun = c.lastRun, c.now.timeIntervalSince(lastRun) < interval { return .notDue }
        // Somebody else's session, or a locked screen: this session stops
        // receiving events, `idleSeconds` grows without bound, and the verdict
        // would be `.run` — reading one person's whole home folder while
        // another is at the keyboard.
        guard c.onConsole, !c.screenLocked else { return .notAtTheConsole }
        guard c.onMains else { return .onBattery }
        guard c.idleSeconds >= idleThreshold else { return .busy }
        return .run
    }
}
