import Foundation

/// A count that belongs to a day and starts again when the day does.
///
/// The engine kept a plain counter and the page showed it under "today". It
/// was neither: it counted from launch, so a Mac left running for a week
/// reported the week, and a restart at noon reported the afternoon.
public struct DailyCount: Equatable, Sendable {
    private var day: Date?
    private var count = 0

    public init() {}

    public mutating func add(on now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        if day != today {
            day = today
            count = 0
        }
        count += 1
        return count
    }

    /// Reading is not counting, and it has to answer for the day being asked
    /// about: a Mac left running overnight would otherwise show yesterday's
    /// total until the next conversion.
    public func value(on now: Date, calendar: Calendar = .current) -> Int {
        day == calendar.startOfDay(for: now) ? count : 0
    }
}
