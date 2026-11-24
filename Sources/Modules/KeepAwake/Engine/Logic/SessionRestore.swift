import Foundation

/// What to do with a session that outlived its process.
///
/// A Keep Awake session the person started lives in three stored fields — is it
/// on, when did it begin, when does it end — because anything that ends the
/// process would otherwise cancel it, and the routine one is Helm's own silent
/// updater, which terminates the app and starts it again.
///
/// Pure, because every branch here is a judgement rather than arithmetic: what a
/// stale deadline means, whether "until I say stop" survives a restart, and what
/// to believe when the clock has moved. `SessionRestoreTests` argues each one.
///
/// What it cannot repair, and does not pretend to: the assertion died with the
/// process, so the Mac genuinely could have slept in the gap.
enum SessionRestore {

    enum Decision: Equatable {
        /// Nothing was running, or what was running is over.
        case none
        /// A session with no deadline — `startSession(minutes: 0)`.
        case indefinite
        /// A session with this much of it left.
        case remaining(TimeInterval)
        /// The record says a session is on and its dates are not ones Helm writes.
        /// Refused, like a deadline out of range: not a session.
        case unreadable
    }

    /// One stored date, parsed once, where it enters.
    enum Stored: Equatable {
        /// No key, or exactly 0: what `rememberSession` writes for nil.
        case absent
        case at(Date)
        /// Not a date Helm writes: NaN, an infinity, a negative, a value that is no number.
        case unreadable

        init(_ raw: Any?) {
            guard let raw else { self = .absent; return }
            guard let seconds = raw as? Double else { self = .unreadable; return }
            if seconds == 0 { self = .absent; return }
            self = seconds.isFinite && seconds > 0
                ? .at(Date(timeIntervalSinceReferenceDate: seconds)) : .unreadable
        }

        var date: Date? { if case let .at(date) = self { date } else { nil } }
    }

    /// The same question asked of the stored record itself. A date that is not
    /// one Helm writes, or a start with no end, is not read as «no deadline»:
    /// that is an indefinite session, the Mac held awake on a number nobody wrote.
    /// Every writer stores the two dates together.
    static func decide(manualOn: Bool, start: Stored, end: Stored, now: Date) -> Decision {
        guard manualOn else { return .none }
        switch (start, end) {
        case (.unreadable, _), (_, .unreadable), (.at, .absent): return .unreadable
        default: return decide(manualOn: true, startDate: start.date, endDate: end.date, now: now)
        }
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
        // exceeds the whole duration, and a thirty-minute session would come
        // back as a day-long one.
        let bounded = startDate.map { min(left, endDate.timeIntervalSince($0)) } ?? left

        // And it cannot come back longer than this module can start one. The
        // bound above is *relative*, so it does nothing when the stored duration
        // is itself absurd or no `startDate` was stored. `<real>1e300</real>` is
        // a legal plist, and `Int(left / 60)` in `restoreSession` traps on it:
        // the app terminating at launch, with no window to switch the session
        // off from.
        //
        // Refused rather than brought down to the ceiling. Every writer here
        // stores the two dates together, so a deadline out here was written by
        // something other than Helm — it is not a session, and keeping the Mac
        // awake for a day on a number nobody wrote is the wrong way to fail.
        //
        // The floor is the same rule from the other end: the bound is a
        // *subtraction*, so a stored start after the stored end makes it
        // negative — `-1e300` traps the same `Int(left / 60)`, and a modest one
        // restores a session that ended before it began, holding the assertion
        // behind a countdown reading 0:00. A session with nothing left is over.
        guard bounded.isFinite, bounded > 0, bounded <= TimerPolicy.longestSession else { return .none }
        return .remaining(bounded)
    }
}
