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
enum SessionRestore {

    enum Decision: Equatable {
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
    static func decide(manualOn: Bool, startDate: Date?, endDate: Date?,
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
        let bounded = startDate.map { min(left, endDate.timeIntervalSince($0)) } ?? left

        // And it cannot come back longer than this module can start one, which
        // is the question that bound cannot answer. That one is *relative* — no
        // longer than the stored duration — so it does nothing when the stored
        // duration is itself the absurd number, and there was nothing at all
        // when no `startDate` was stored beside the deadline. `<real>1e300</real>`
        // is a legal plist, and the value reached `Int(left / 60)` in
        // `restoreSession`, which traps: the app terminating at launch, before
        // anything is drawn, with no window to switch the session off from.
        //
        // Refused rather than brought down to the ceiling. Every writer here
        // stores the two dates together, so a deadline out here says the file
        // was written by something other than Helm — that is not a long
        // session, it is not a session, and keeping the Mac awake for a day on
        // the strength of a number nobody wrote is the wrong direction to fail
        // in.
        //
        // The floor is the same sentence read from the other end, and it was
        // missing while the ceiling stood: the bound is a *subtraction*, so a
        // stored start after the stored end makes it negative, and a plist can
        // put `<real>1e300</real>` in either field. `-1e300` is finite and is
        // under a day, so the ceiling passed it to the same `Int(left / 60)`
        // that traps — "less than Int.min" this time. The modest version is
        // worse for not trapping: `startedAt = endsAt + 60` restored a session
        // that ended before it began, holding the IOKit assertion behind a
        // countdown reading 0:00. Zero belongs on this side too — a session
        // with nothing left of it is over, which is what the deadline branch
        // above already says about the other date.
        guard bounded.isFinite, bounded > 0, bounded <= TimerPolicy.longestSession else { return .none }
        return .remaining(bounded)
    }
}
