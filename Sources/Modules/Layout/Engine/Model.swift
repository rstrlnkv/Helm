import Foundation

/// One conversion, as it happened.
///
/// The words live here and in memory and nowhere else: they are never logged
/// and never written to disk. A key tap sees passwords typed into fields an app
/// forgot to mark secure, and the only safe place for that is somewhere already
/// gone.
public struct ConversionEvent: Codable, Equatable, Sendable {
    public let before: String
    public let after: String
    /// Bundle id of the app it happened in, so an undo cannot land elsewhere.
    public let app: String
    /// The character that ended the word — it was deleted and retyped with the
    /// replacement, so undoing has to do the same or it eats one character too
    /// few. Empty when the conversion came from the hotkey mid-word.
    public let trailing: String
    /// True when the gesture asked for this word by name, past the dictionary.
    /// The words in an automatic conversion were vouched for; a forced one is
    /// arbitrary typed text — possibly a field nothing recognised as secure —
    /// and the page must not offer to write it to disk («Never this word»).
    public let forced: Bool

    public init(before: String, after: String, app: String, trailing: String = "",
                forced: Bool = false) {
        self.before = before
        self.after = after
        self.app = app
        self.trailing = trailing
        self.forced = forced
    }
}

/// How far back a figure reaches.
///
/// **The windows slide; they do not follow the calendar.** «This month» on the
/// first of the month is a figure that collapses overnight through nothing the
/// reader did — the same complaint `DailyCount` was written for one scale down.
/// Only `today` is a calendar day, because «today» means that and nothing else.
///
/// One type for the engine and the page: the segment somebody presses and the
/// window the ledger sums over must not be two lists that can disagree.
public enum ConversionPeriod: String, CaseIterable, Codable, Sendable {
    case today, week, month, year, allTime

    /// Days back from today, inclusive. Nil is «everything there is».
    public var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        case .allTime: return nil
        }
    }
}

/// One period's two figures. Characters travel beside words because the time
/// estimate is taken from the length of what was actually fixed.
public struct LedgerFigures: Codable, Equatable, Sendable {
    public let words: Int
    public let characters: Int
    public init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }
}

/// Every period the hero can be switched to, answered at once.
///
/// `since` is when counting began, which is what «all time» means to the person
/// reading it — nil until the first word is put right. A figure with no scale
/// is worse than no figure: forty words is a lot in a week and nothing in three
/// years.
public struct ConversionTotals: Codable, Equatable, Sendable {
    public let today: LedgerFigures
    public let week: LedgerFigures
    public let month: LedgerFigures
    public let year: LedgerFigures
    public let allTime: LedgerFigures
    public let since: Date?

    /// The pair for a period — so the page switches with a value rather than a
    /// `switch` it has to keep in step with the enum.
    public func figures(_ period: ConversionPeriod) -> LedgerFigures {
        switch period {
        case .today: today
        case .week: week
        case .month: month
        case .year: year
        case .allTime: allTime
        }
    }

    public static let none = ConversionTotals(
        today: LedgerFigures(words: 0, characters: 0),
        week: LedgerFigures(words: 0, characters: 0),
        month: LedgerFigures(words: 0, characters: 0),
        year: LedgerFigures(words: 0, characters: 0),
        allTime: LedgerFigures(words: 0, characters: 0), since: nil)

    public init(today: LedgerFigures, week: LedgerFigures, month: LedgerFigures,
                year: LedgerFigures, allTime: LedgerFigures, since: Date?) {
        self.today = today
        self.week = week
        self.month = month
        self.year = year
        self.allTime = allTime
        self.since = since
    }
}

/// What the settings page shows.
public struct LayoutState: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let automatic: Bool
    /// True while secure input is on: the module is deliberately silent, and
    /// silence needs a visible reason.
    public let suspended: Bool
    public let lastConversion: ConversionEvent?
    /// True when `lastConversion` was taken back. The record and the right to a
    /// blind undo are different things: the undo dies with the caret's next
    /// move, but the row on the page — and its «Never this word» button — must
    /// outlive it, or the button is reachable only for changes nobody rejected.
    public let lastConversionUndone: Bool
    public let totals: ConversionTotals
    /// Installed layouts macOS has no spelling dictionary for, by source id.
    ///
    /// Empty on most Macs. When it is not, «Fix as I type» is dead for every
    /// pair that includes one of these and nothing on the page said so — the
    /// switch stayed on and the badge stayed green. The ids travel rather than
    /// the names: naming an input source is the UI's job (`InputSourceInfo`),
    /// and the engine may not import `HelmUI`.
    public let noDictionary: [String]

    public init(enabled: Bool, automatic: Bool, suspended: Bool,
                lastConversion: ConversionEvent?, lastConversionUndone: Bool,
                totals: ConversionTotals = .none, noDictionary: [String] = []) {
        self.enabled = enabled
        self.automatic = automatic
        self.suspended = suspended
        self.lastConversion = lastConversion
        self.lastConversionUndone = lastConversionUndone
        self.totals = totals
        self.noDictionary = noDictionary
    }
}
