import Foundation

/// What the module has put right, by day, so the figure outlives a launch.
///
/// The day counter this replaced held one day in memory, so the page's one
/// figure went back to
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
    ///
    /// **A calendar day, not an instant, and that distinction cost a day's
    /// count.** `day` was `startOfDay(for:)` — midnight in whichever zone was
    /// active when the row was written — and every reader matched it with `==`
    /// or a dictionary keyed on it. A Mac that corrects its own time zone at
    /// lunchtime then writes 30 August twice, nine hours apart: «words fixed
    /// today» goes backwards, and the morning's word matches no bar in the
    /// fortnight the tile draws, so it is not drawn short — it is not drawn.
    /// `add`'s own comment already said «a Mac can wake in another timezone»
    /// and answered it by re-sorting; sorting fixes the order, not the identity.
    ///
    /// `stamp` is `yyyymmdd` in the zone the person was in when they typed,
    /// which is the only sense in which the word happened on a day.
    struct Day: Codable, Equatable, Sendable {
        let stamp: Int
        var words: Int
        var characters: Int

        init(stamp: Int, words: Int, characters: Int) {
            self.stamp = stamp
            self.words = words
            self.characters = characters
        }

        private enum CodingKeys: String, CodingKey { case stamp, day, words, characters }

        /// **Hand-written, because a stored default does not decode an older
        /// payload.** Swift's synthesised `Decodable` requires every coding key
        /// whatever a property's initial value is, and `JSONDecoder` gives up on
        /// the whole document rather than filling one field in — so a ledger
        /// written before this change would have thrown, `LedgerStore` would
        /// have read nil, and somebody's whole count would have been replaced
        /// by an empty file without a word. `PanelLayout.Tab` and
        /// `KeepAwakeEngine.StatePayload` are the same repair for the same
        /// reason (CLAUDE.md § A reading that is not the whole truth).
        ///
        /// The old instant is converted in the current zone. A row written far
        /// from here may land a day out — once, on the rows that already exist,
        /// which is the price of not discarding them.
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            words = try box.decode(Int.self, forKey: .words)
            characters = try box.decode(Int.self, forKey: .characters)
            if let stamp = try box.decodeIfPresent(Int.self, forKey: .stamp) {
                self.stamp = stamp
            } else {
                let old = try box.decode(Date.self, forKey: .day)
                self.stamp = ConversionLedger.stamp(of: old, calendar: .current)
            }
        }

        func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(stamp, forKey: .stamp)
            try box.encode(words, forKey: .words)
            try box.encode(characters, forKey: .characters)
        }
    }

    /// The calendar day a moment falls on, as `yyyymmdd` — comparable and
    /// orderable as an integer, which is what makes «the same day» a fact
    /// rather than a coincidence of two clocks.
    static func stamp(of moment: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
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
    ///
    /// Guarded like every other reader: a row written by a clock that was
    /// running fast is in the future, and «since a date that has not happened»
    /// is not a scale.
    /// Takes the calendar for the reason every other reader does: a stamp is a
    /// calendar day, and turning one back into a date is a question about a
    /// zone. `.current` is the default because that is what the app runs in;
    /// a test that fixes the zone gets the day it wrote.
    func since(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let today = Self.stamp(of: now, calendar: calendar)
        guard let first = days.first(where: { $0.stamp <= today }) else { return nil }
        return Self.date(of: first.stamp, calendar: calendar)
    }

    /// Back from a stamp, for the one reader that hands a date outward.
    static func date(of stamp: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = stamp / 10_000
        parts.month = (stamp / 100) % 100
        parts.day = stamp % 100
        return calendar.date(from: parts)
    }

    /// `words` is more than one only for a selection: a sentence put right in
    /// one gesture is several words of saved typing, and counting it as one
    /// would understate the estimate by exactly the number of switches the
    /// person did not have to make.
    mutating func add(words: Int = 1, characters: Int, on now: Date,
                      calendar: Calendar = .current) {
        let start = Self.stamp(of: now, calendar: calendar)
        if let index = days.firstIndex(where: { $0.stamp == start }) {
            days[index].words += words
            days[index].characters += characters
            return
        }
        days.append(Day(stamp: start, words: words, characters: characters))
        // Kept in order so the file reads as a history and «since» is the first
        // row rather than a scan. A day out of order is ordinary: a clock can
        // go backwards.
        days.sort { $0.stamp < $1.stamp }
    }

    /// The two figures for a period: how many words, and how many characters
    /// they held. A day stamped in the future is left out rather than counted —
    /// a clock that went backwards must not make today unreachable.
    func total(over period: ConversionPeriod, now: Date,
               calendar: Calendar = .current) -> (words: Int, characters: Int) {
        let today = Self.stamp(of: now, calendar: calendar)
        let floor: Int? = period.days.flatMap { span in
            calendar.date(byAdding: .day, value: -(span - 1), to: calendar.startOfDay(for: now))
                .map { Self.stamp(of: $0, calendar: calendar) }
        }
        return days.reduce(into: (words: 0, characters: 0)) { sum, row in
            guard row.stamp <= today else { return }
            if let floor, row.stamp < floor { return }
            sum.words += row.words
            sum.characters += row.characters
        }
    }

    /// The last `days` days, oldest first, one number per day.
    ///
    /// **Zero-filled, and that is the whole point.** `days` holds only the days
    /// something happened on, so a drawing made straight from it spaces five
    /// bars evenly across a fortnight and a quiet week looks exactly like a busy
    /// one. This is what the 2×N tile draws to answer «why is it that many» —
    /// a question a single figure cannot answer, however large the digits.
    func recent(days count: Int, now: Date,
                calendar: Calendar = .current) -> [Int] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: now)
        let today = Self.stamp(of: now, calendar: calendar)
        var byDay: [Int: Int] = [:]
        for row in days where row.stamp <= today { byDay[row.stamp, default: 0] += row.words }
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: start)
                .map { byDay[Self.stamp(of: $0, calendar: calendar)] ?? 0 }
        }
    }

    /// Every period at once, because the page lets somebody switch between them
    /// and a round trip to the engine per press would make the segment feel
    /// like a network. Five pairs of integers is nothing to carry.
    func totals(now: Date, calendar: Calendar = .current) -> ConversionTotals {
        func figures(_ period: ConversionPeriod) -> LedgerFigures {
            let sum = total(over: period, now: now, calendar: calendar)
            return LedgerFigures(words: sum.words, characters: sum.characters)
        }
        return ConversionTotals(today: figures(.today), week: figures(.week),
                                month: figures(.month), year: figures(.year),
                                allTime: figures(.allTime), since: since(now: now, calendar: calendar),
                                recent: recent(days: 14, now: now, calendar: calendar))
    }
}
