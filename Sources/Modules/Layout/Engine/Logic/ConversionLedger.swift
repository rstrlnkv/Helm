import Foundation

/// What the module has put right, by day, so the figure outlives a launch.
///
/// `DailyCount` holds one day in memory, so the page's one figure went back to
/// zero at every launch — and the silent updater relaunches the app, which
/// means «words fixed today» could be zero at four in the afternoon for
/// somebody who had used it all morning.
///
/// **No word is written down, and that is a decision rather than an
/// omission.** This module sees every keystroke, including the ones beside a
/// password field: secure input and the app exclusions are good, but a web form
/// with the wrong field type is a password macOS never marked. A day, a count,
/// and how many characters those words held is everything here — and the
/// characters exist only so the time estimate can be taken from the length of
/// the words actually fixed rather than from an average.
struct ConversionLedger: Codable, Equatable, Sendable {

    /// One day. `words` is how many were put right, `characters` how many
    /// letters those words held together.
    struct Day: Codable, Equatable, Sendable {
        let day: Date
        var words: Int
        var characters: Int
    }

    /// Oldest first, one row per day. A year is 365 rows; the file is small
    /// enough that trimming it would cost more in explanation than it saves on
    /// disk — and «all time» stops being true the moment anything is dropped.
    private(set) var days: [Day] = []

    init() {}

    /// The first day this ledger has anything for, which is what «all time»
    /// means to the person reading it. Nil when nothing has been fixed yet —
    /// and nil rather than «now», because a figure with no scale is worse than
    /// no figure: 40 words is a lot in a week and nothing in three years.
    var since: Date? { days.first?.day }

    /// `words` is more than one only for a selection: a sentence put right in
    /// one gesture is several words of saved typing, and counting it as one
    /// would understate the estimate by exactly the number of switches the
    /// person did not have to make.
    mutating func add(words: Int = 1, characters: Int, on now: Date,
                      calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        if let index = days.firstIndex(where: { $0.day == start }) {
            days[index].words += words
            days[index].characters += characters
            return
        }
        days.append(Day(day: start, words: words, characters: characters))
        // Kept in order so the file reads as a history and «since» is the first
        // row rather than a scan. A day out of order is ordinary: a clock can
        // go backwards, and a Mac can wake in another timezone.
        days.sort { $0.day < $1.day }
    }

    /// How far back a figure reaches.
    ///
    /// **The windows slide; they do not follow the calendar.** «This month» on
    /// the first of the month is a figure that collapses overnight through
    /// nothing the reader did — the same complaint `DailyCount` was written for
    /// one scale down. Only `today` is a calendar day, because «today» means
    /// that and nothing else.
    enum Period: String, CaseIterable, Codable, Sendable {
        case today, week, month, year, allTime

        /// Days back from today, inclusive. Nil is «everything there is».
        var days: Int? {
            switch self {
            case .today: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .allTime: return nil
            }
        }
    }

    /// The two figures for a period: how many words, and how many characters
    /// they held. A day stamped in the future is left out rather than counted —
    /// a clock that went backwards must not make today unreachable.
    func total(over period: Period, now: Date,
               calendar: Calendar = .current) -> (words: Int, characters: Int) {
        let today = calendar.startOfDay(for: now)
        let floor: Date? = period.days.flatMap {
            calendar.date(byAdding: .day, value: -($0 - 1), to: today)
        }
        return days.reduce(into: (words: 0, characters: 0)) { sum, row in
            guard row.day <= today else { return }
            if let floor, row.day < floor { return }
            sum.words += row.words
            sum.characters += row.characters
        }
    }

    /// Every period at once, because the page lets somebody switch between them
    /// and a round trip to the engine per press would make the segment feel
    /// like a network. Five pairs of integers is nothing to carry.
    func totals(now: Date, calendar: Calendar = .current) -> ConversionTotals {
        func figures(_ period: Period) -> LedgerFigures {
            let sum = total(over: period, now: now, calendar: calendar)
            return LedgerFigures(words: sum.words, characters: sum.characters)
        }
        return ConversionTotals(today: figures(.today), week: figures(.week),
                                month: figures(.month), year: figures(.year),
                                allTime: figures(.allTime), since: since)
    }
}
