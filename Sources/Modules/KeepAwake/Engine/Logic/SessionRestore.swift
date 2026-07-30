import Foundation

/// What to do with a session that outlived its process.
///
/// A Keep Awake session the person started lives in three fields — is it on, when
/// did it begin, when does it end — and those fields used to exist only in engine
/// memory. Anything that ended the process cancelled the session, and the routine
/// one is Helm's own silent updater: it terminates the app and a detached script
/// swaps the bundle and starts it again. The IOKit assertion goes with the process
/// too, so the Mac was free to sleep with the countdown gone from the menu bar and
/// nothing anywhere saying the session had been cut short.
///
/// The module already knew how to survive a relaunch one field away —
/// `clamshellGuard` is stored when sleep is disabled and undone in `activate()`,
/// because that change outlives the process. It protected the *system* from being
/// left wrong and not the person's own request.
///
/// Pure, because every branch here is a judgement rather than arithmetic: what a
/// stale deadline means, whether "until I say stop" survives a restart, and what
/// to believe when the clock has moved. `SessionRestoreTests` argues each one.
public enum SessionRestore {

    public enum Decision: Equatable {
        /// Nothing was running, or what was running is over.
        case none
        /// A session with no deadline — `startSession(minutes: 0)`.
        case indefinite
        /// A session with this much of it left.
        case remaining(TimeInterval)
    }

    /// - Parameters:
    ///   - manualOn: whether a session was running when the process ended.
    ///   - startDate: when it began; `nil` for an indefinite one.
    ///   - endDate: when it was due to end; `nil` for an indefinite one.
    ///   - now: the clock on the way back up.
    public static func decide(manualOn: Bool, startDate: Date?, endDate: Date?,
                              now: Date) -> Decision {
        // The dates are the deadline *of* a session, not the session. A deadline
        // found with the session switched off is stale bookkeeping, and acting on
        // it would keep the Mac awake because of something the person turned off.
        guard manualOn else { return .none }
        guard let endDate else { return .indefinite }
        guard endDate > now else { return .none }

        let left = endDate.timeIntervalSince(now)
        // A session cannot come back longer than it ever was. When the system
        // clock moves backwards — an NTP correction, a timezone change, a Mac
        // whose battery died and restarted from an epoch — `endDate - now`
        // exceeds the whole duration, and a thirty-minute session restored as a
        // day-long one is this same defect wearing the opposite sign.
        guard let startDate else { return .remaining(left) }
        return .remaining(min(left, endDate.timeIntervalSince(startDate)))
    }
}
