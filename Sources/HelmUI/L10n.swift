import Foundation
import HelmRuntime

/// Supported UI languages. English is the base; every string catalog holds the
/// other seven beside it.
///
/// The catalogs' language codes are the raw values (`zh`, `pt`), not `zh-Hans`
/// or `pt-BR`, because Helm picks the language itself rather than leaving it to
/// the system's resolution.
public enum AppLanguage: String, CaseIterable, Sendable {
    case en, zh, es, fr, de, ja, ru, pt

    /// Best match from the user's preferred languages, else English.
    ///
    /// Cached, because every `L()` and `Bytes()` reads it and
    /// `Locale.preferredLanguages` is a CFPreferences read. The cache is dropped
    /// when the system's locale changes or `override` is set, the only two
    /// things that can change the answer.
    public static var current: AppLanguage { cache.value }

    /// A language chosen in Settings, overriding the system's preference; nil,
    /// the ordinary state, means whatever this Mac is set to.
    ///
    /// Helm sets it in Dev builds only, and the showcase from `--language`, so a
    /// screen can be read in every language without logging out of the Mac.
    /// Setting it drops the cache, so every `L()` from the next read answers in
    /// the new language. Views already built do not redraw by themselves; the
    /// app posts a notification for that.
    public static var override: AppLanguage? {
        get { cache.override }
        set { cache.override = newValue }
    }

    /// The language's own name for itself. A picker that lists «Japanese» in
    /// English is a picker for people who already read English — every system
    /// language chooser on this machine writes each one in itself.
    public var endonym: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        case .ru: return "Русский"
        case .pt: return "Português"
        }
    }

    /// The language as a `Locale`, for a format style or a formatter.
    ///
    /// Computed, never stored and never static: a format style holds no cache, so a language
    /// changed between two reads is spoken at the next one.
    public var locale: Locale { Locale(identifier: rawValue) }

    private static let cache = LanguageCache()

    private final class LanguageCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: AppLanguage?

        init() {
            NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.cached = nil; self.lock.unlock()
            }
        }

        private var overridden: AppLanguage?

        var override: AppLanguage? {
            get { lock.lock(); defer { lock.unlock() }; return overridden }
            set {
                lock.lock()
                overridden = newValue
                cached = nil
                lock.unlock()
            }
        }

        var value: AppLanguage {
            lock.lock()
            defer { lock.unlock() }
            if let overridden { return overridden }
            if let cached { return cached }
            let resolved = Self.resolve()
            cached = resolved
            return resolved
        }

        /// The first two letters of each preferred language, in order, name the
        /// catalog: `zh-Hant` goes to the Simplified `zh` catalog and `pt-PT` to
        /// the Brazilian `pt` one, in line with Info.plist's `zh-Hans` and `pt-BR`.
        private static func resolve() -> AppLanguage {
            for code in Locale.preferredLanguages {
                let base = code.prefix(2).lowercased()
                if let lang = AppLanguage(rawValue: String(base)) { return lang }
            }
            return .en
        }
    }
}

/// A word from a module's own catalog, in the app's language.
///
/// `String(localized:)` alone answers in the language macOS resolves for the
/// process, not the one the person picked in Helm, so the resource is asked in
/// `language`. The resource carries its own target's bundle, which is why one
/// function in the kit can read every module's catalog.
///
/// Remembered, because `String(localized:)` costs more the larger the table, on
/// every call, and a word in a view body is asked per frame. Each answer is
/// kept by key, table, bundle, arguments and language.
///
/// `remembered: false` is for a word that holds somebody's typed text: the memo
/// keeps the arguments and forgets only by count, so the text would outlive
/// whatever its owner does to forget it.
public func L(_ resource: LocalizedStringResource,
              language: AppLanguage = AppLanguage.current,
              remembered: Bool = true) -> String {
    var resource = resource
    resource.locale = language.locale
    return remembered ? ResourceAnswers.shared.string(for: resource) : String(localized: resource)
}

/// The answers `L(_:language:remembered:)` has given, bounded because a
/// resource that carries arguments is a new entry for every value.
///
/// A `LocalizedStringResource` is not `Hashable`, so the dictionary is keyed by
/// key, table and language, and each such family keeps a short list searched
/// with the resource's own `==`, which also compares bundle and arguments: the
/// same key in two catalogs stays two answers.
///
/// A family holds at most `perFamily` answers, oldest replaced, so a hit costs
/// at most that many comparisons whatever the arguments. Past `perFamily`
/// values of one template in turn every ask misses, a little dearer than no memo.
///
/// Not `LockedMemo`, which needs a `Hashable` key, never forgets, and builds
/// under its lock: here the build is `String(localized:)`, which runs outside
/// the lock so a slow word does not hold up the others.
private final class ResourceAnswers: @unchecked Sendable {
    static let shared = ResourceAnswers()

    private struct Family: Hashable {
        let key: String
        let table: String?
        let language: String
    }

    /// Answers kept per family.
    private static let perFamily = 16

    /// Past this many answers in all, everything is dropped and rebuilt on
    /// demand, the way `AppLanguage`'s cache drops its answer: simpler than
    /// ordering them.
    private static let ceiling = 4096

    private let lock = NSLock()
    private var answers: [Family: [(resource: LocalizedStringResource, text: String)]] = [:]
    private var count = 0

    func string(for resource: LocalizedStringResource) -> String {
        let family = Family(key: resource.key, table: resource.table,
                            language: resource.locale.identifier)
        lock.lock()
        let kept = answers[family]?.first { $0.resource == resource }?.text
        lock.unlock()
        if let kept { return kept }
        let text = String(localized: resource)
        lock.lock()
        defer { lock.unlock() }
        if count >= Self.ceiling { answers.removeAll(); count = 0 }
        var list = answers.removeValue(forKey: family) ?? []
        if !list.contains(where: { $0.resource == resource }) {
            if list.count >= Self.perFamily { list.removeFirst(); count -= 1 }
            list.append((resource, text))
            count += 1
        }
        answers[family] = list
        return text
    }
}

/// A size in the user's language: "432,95 ГБ", "1.5 GB". One formatter for
/// every screen (`HelmBytes`).
public func Bytes(_ count: Int) -> String {
    HelmBytes.string(count, language: AppLanguage.current.rawValue)
}

/// A number in the user's language: "1,5" where the language writes a comma,
/// so a figure beside a `Bytes` size uses the same mark. Not named `Decimal`:
/// `Decimal(anInt)` would bind to Foundation's initialiser, not to this one.
public func Fractional(_ value: Double, decimals: Int = 1) -> String {
    HelmBytes.decimal(value, decimals: decimals, language: AppLanguage.current.rawValue)
}

/// A count in the user's language: "1 499 308", "1.499.308", grouped as macOS
/// groups digits.
///
/// Not `Fractional`, which turns grouping off on purpose: that one writes the
/// mantissa of a size, where a separator would be a second decimal mark.
public func Count(_ value: Int, language: AppLanguage = AppLanguage.current) -> String {
    HelmBytes.grouped(value, language: language.rawValue)
}

/// Dates in the app's language, not the system's.
///
/// A formatter with no locale answers in the system's language, which on a Mac
/// outside Helm's eight sits inside an English UI, and one built once keeps the
/// language the app started in. So every formatter here is keyed by language.
public enum HelmDates {

    /// How long an age is spelled, as two cases rather than the system's three.
    ///
    /// `.abbreviated` prints a signed delta in Russian and French («-1 мин»),
    /// which is not an age, and under the VPN speed tile a leading minus reads
    /// as a third reading. So that case is not offered. The enum stops a caller
    /// picking it; nothing checks the mapping below.
    public enum AgeStyle {
        /// «1 минуту назад» — for a line that has the width for it.
        case full
        /// «1 мин. назад» — macOS's own short form, for a column that has not.
        case short

        var system: RelativeDateTimeFormatter.UnitsStyle {
            switch self {
            case .full: .full
            case .short: .short
            }
        }
    }

    /// "2 hours ago", «2 часа назад»: an age, or nil for a stamp that has none.
    ///
    /// Every caller draws how old something is, and the system formatter writes
    /// a time still to come in two cases: a stamp ahead of the clock (a file
    /// from a Mac whose clock runs fast, a row an NTP step stepped over), and a
    /// stamp less than a second old, which `RelativeDateTimeFormatter` rounds to
    /// zero and writes in the future voice («через 0 секунд», "in 0 seconds") in
    /// all eight languages.
    ///
    /// `nil`, never a clamp: «just now» for a file dated next March is wrong in a
    /// way nothing on screen can show, because a fresh reading says the same.
    /// The absence is the only answer a reader can tell apart.
    ///
    /// `style` is `.full` for a row with the width; the VPN speed tile asks for
    /// `.short`.
    public static func age(_ date: Date, to now: Date = Date(),
                           style: AgeStyle = .full,
                           language: String = AppLanguage.current.rawValue) -> String? {
        guard now.timeIntervalSince(date) >= youngestAgeWrittenAsPast else { return nil }
        return cache.relative(language: language, style: style)
            .localizedString(for: date, relativeTo: now)
    }

    /// The seam, measured rather than assumed: below a full second every one of
    /// the eight writes the rounded zero as a forecast, and at one second every
    /// one of them says «ago».
    private static let youngestAgeWrittenAsPast: TimeInterval = 1

    /// A span in the person's language: «1 ч 14 мин», "1h 14m".
    ///
    /// Here rather than in a module, because how a language writes a length of
    /// time is `HelmUI`'s business, as sizes and dates are. Two unit sets,
    /// because one cannot serve both ends: hours and minutes above the hour,
    /// minutes and seconds below it, where only they move.
    public static func span(_ seconds: TimeInterval,
                            language: String = AppLanguage.current.rawValue) -> String {
        let seconds = max(0, seconds)
        return cache.span(language: language, hours: seconds >= 3600)
            .string(from: seconds) ?? ""
    }

    /// A log line's clock, to the second, in the app's own language-independent
    /// form: the file writes `HH:mm:ss.SSS` and the live view must agree with it
    /// digit for digit, or the same event reads as two.
    public static func logTime(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// The fraction, `.123`, as its own string so a row can draw it quieter
    /// than the seconds: many lines share their second with a neighbour.
    public static func logMillis(_ date: Date) -> String {
        millis.string(from: date)
    }

    /// Built once, because it is asked per visible row and for every line of a
    /// copied log tail. Nothing to key it by: the format is POSIX.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let millis: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = ".SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// A time of day the way this language writes one: «15:42», "3:42 PM".
    /// Keyed by the app's language, like everything here, or a Mac set to
    /// another language would draw its own clock, maybe a 12-hour one, on a
    /// page in Helm's.
    public static func timeOfDay(_ date: Date,
                                 language: String = AppLanguage.current.rawValue) -> String {
        cache.clock(language: language).string(from: date)
    }

    /// Day and minute, short: a report covering thirty days needs the day, and a
    /// morning's worth of moves needs the minute.
    public static func dayAndMinute(_ date: Date,
                                    language: String = AppLanguage.current.rawValue) -> String {
        cache.absolute(language: language).string(from: date)
    }

    /// A calendar day stored as "2026-07-28" (the changelog's entries), in the
    /// language's long form: "28 июля 2026 г.", "28. Juli 2026".
    ///
    /// The stored form sorts and keys the entries. Anything that is not a day
    /// comes back untouched, because the changelog is written by hand and a
    /// blank line under a version reads as a broken sheet, not a typo. Parsed
    /// and written in the same zone, or half the world would see the 27th.
    public static func day(_ stored: String,
                           language: String = AppLanguage.current.rawValue) -> String {
        guard let date = cache.storage.date(from: stored) else { return stored }
        return cache.day(language: language, zone: cache.storage.timeZone).string(from: date)
    }

    /// The same long day, for a date the app already holds, where the minute
    /// is noise. `dayAndMinute` is for a report of today's activity.
    ///
    /// Written in the zone the process is in at each call, `NSTimeZone.default`,
    /// which `Calendar.current` follows, not `TimeZone.current`, a snapshot a
    /// zone change does not move. Otherwise the label names a different day than
    /// the clock beside it after the Mac changes zone under a running app.
    public static func day(_ date: Date,
                           language: String = AppLanguage.current.rawValue) -> String {
        cache.day(language: language, zone: NSTimeZone.default).string(from: date)
    }

    /// The days a folded row stands for, written by the system's interval
    /// formatter rather than two days joined with a dash: the sign and spacing
    /// are the language's, and a shared month or year is written once. The long
    /// style matches `day`'s headings, except in Chinese and Japanese, where it
    /// answers in numerals, so those two ask by a template.
    ///
    /// Kept per language and zone: the language changes while the app runs, and
    /// a formatter built per call is the cost a page of a thousand rows avoids.
    public static func daySpan(from first: Date, to last: Date, language: String,
                               zone: TimeZone) -> String {
        let spelled = cache.daySpan(language: language, zone: zone).string(from: first, to: last)
        // A formatter that answers nothing leaves the two days as `day` writes
        // them rather than an empty heading over a row.
        return spelled.isEmpty ? day(first, language: language) + " – "
            + day(last, language: language) : spelled
    }

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let relatives = LockedMemo<String, RelativeDateTimeFormatter>()
        private let absolutes = LockedMemo<String, DateFormatter>()
        private let days = LockedMemo<String, DateFormatter>()
        private let clocks = LockedMemo<String, DateFormatter>()
        private let daySpans = LockedMemo<String, DateIntervalFormatter>()
        private let spans = LockedMemo<String, DateComponentsFormatter>()

        /// Reads the stored form and nothing else: fixed format, fixed locale.
        /// `en_US_POSIX` because a fixed-format formatter on any other locale
        /// answers to the reader's calendar — a Japanese one parses this as an
        /// era year and returns nil.
        let storage: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        /// Keyed by the language *and* the zone: a formatter's zone is not safe
        /// to change under a reader, so a new zone is a new formatter and the old
        /// one stays for whoever still holds it. The stored-day reading passes the
        /// zone `storage` parsed in, so its day cannot shift.
        func day(language: String, zone: TimeZone) -> DateFormatter {
            let key = "\(language)|\(zone.identifier)"
            return days.value(for: key) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: language)
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                formatter.timeZone = zone
                return formatter
            }
        }

        func daySpan(language: String, zone: TimeZone) -> DateIntervalFormatter {
            let key = "\(language)|\(zone.identifier)"
            return daySpans.value(for: key) {
                let formatter = DateIntervalFormatter()
                formatter.locale = Locale(identifier: language)
                formatter.timeZone = zone
                // The long style answers numerals in Chinese and Japanese, beside
                // headings spelled `2026年9月22日`; the template spells the day
                // as they do. «MMMM» would be `九月` in Chinese, so «MMM».
                if language.hasPrefix("zh") || language.hasPrefix("ja") {
                    formatter.dateTemplate = "yMMMd"
                } else {
                    formatter.dateStyle = .long
                    formatter.timeStyle = .none
                }
                return formatter
            }
        }

        func clock(language: String) -> DateFormatter {
            return clocks.value(for: language) {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: language)
                return formatter
            }
        }

        /// Keyed by the language *and* the unit set: two formatters per
        /// language, built once each, since a `DateComponentsFormatter` is not
        /// safe to reconfigure under a reader.
        func span(language: String, hours: Bool) -> DateComponentsFormatter {
            let key = "\(language)|\(hours)"
            return spans.value(for: key) {
                let formatter = DateComponentsFormatter()
                // The locale rides on the calendar: `DateComponentsFormatter` has
                // no locale of its own, and one with no calendar answers in the
                // system's language.
                var calendar = Calendar(identifier: .gregorian)
                calendar.locale = Locale(identifier: language)
                formatter.calendar = calendar
                formatter.unitsStyle = .abbreviated
                formatter.allowedUnits = hours ? [.hour, .minute] : [.minute, .second]
                // `dropLeading`, never `dropAll`: a tunnel up for four seconds has
                // no minutes to show and must still say «4 с» rather than nothing
                // at all, which is what dropping every zero leaves.
                formatter.zeroFormattingBehavior = .dropLeading
                return formatter
            }
        }

        /// Keyed by the language and the style, for the reason `span` is keyed
        /// by its unit set: keyed by language alone, the first style asked for
        /// would be the one that language answers in for the life of the process.
        func relative(language: String,
                      style: HelmDates.AgeStyle) -> RelativeDateTimeFormatter {
            let key = "\(language)|\(style)"
            return relatives.value(for: key) {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = style.system
                formatter.locale = Locale(identifier: language)
                return formatter
            }
        }

        func absolute(language: String) -> DateFormatter {
            return absolutes.value(for: language) {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: language)
                return formatter
            }
        }
    }
}

/// Quotation marks belong to the language too: anything that quotes a value
/// the user typed goes through here instead of hard-coding English's pair.
///
/// The marks are the ones macOS uses around a substituted name in its own
/// `Localizable.loctable` files, looked up rather than remembered. French takes
/// no-break spaces inside its guillemets, because an ordinary space can break a
/// name onto the next line from its opening mark. Spanish and Japanese take
/// curly quotes around a name, as macOS does; 「」 does other work in Japanese,
/// and this helper only ever wraps a name.
public func Quoted(_ text: String, language: AppLanguage = AppLanguage.current) -> String {
    let nbsp = "\u{00A0}"
    switch language {
    case .ru: return "«\(text)»"
    case .fr: return "«\(nbsp)\(text)\(nbsp)»"
    case .de: return "„\(text)“"
    case .en, .es, .ja, .zh, .pt: return "“\(text)”"
    }
}
