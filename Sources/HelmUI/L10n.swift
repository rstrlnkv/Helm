import Foundation
import HelmRuntime

/// Supported UI languages. English is the base (source strings live at the call
/// site); the others come from per-string tables.
public enum AppLanguage: String, CaseIterable, Sendable {
    case en, zh, es, fr, de, ja, ru, pt

    /// Best match from the user's preferred languages, else English.
    ///
    /// Cached: this is read by every `L()` and every `Bytes()`, and every one of
    /// Helm's 238 string properties is computed, so a hovered list of 200 rows
    /// hit `Locale.preferredLanguages` — a CFPreferences read — a few hundred
    /// times per frame. The cache is dropped when the system's locale changes,
    /// which is the only thing that can change the answer.
    public static var current: AppLanguage { cache.value }

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

        var value: AppLanguage {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let resolved = Self.resolve()
            cached = resolved
            return resolved
        }

        private static func resolve() -> AppLanguage {
            for code in Locale.preferredLanguages {
                let base = code.prefix(2).lowercased()
                if let lang = AppLanguage(rawValue: String(base)) { return lang }
            }
            return .en
        }
    }
}

/// Localize a base (English) string, read out of `Resources/<lang>.lproj/
/// Localizable.strings` with the English itself as the key. Usage:
/// `L("Keep Awake")`.
///
/// The optional table is for the handful of call sites Swift interpolation
/// keeps out of a `.strings` file — interpolation runs before the lookup, so
/// `L("Step \(step) of \(total)")` would look for the literal key "Step 3 of
/// 10". Where a table is given, it wins outright and the `.lproj` files are
/// never consulted; where it is empty (the default, and the ordinary case),
/// the lookup goes to `Localized`.
public func L(_ english: String, _ table: [AppLanguage: String] = [:]) -> String {
    L(english, table, language: AppLanguage.current)
}

/// The same, for a language named outright.
///
/// The suite runs in this machine's language, so a test that reads
/// `AppLanguage.current` checks English eight times — `Quoted` and
/// `HelmConfirm.trash` both take the language for exactly this reason, and each
/// had to spell the lookup out again to do it.
public func L(_ english: String, _ table: [AppLanguage: String] = [:],
              language: AppLanguage) -> String {
    guard table.isEmpty else {
        return language == .en ? english : table[language] ?? english
    }
    return Localized.string(english, language: language)
}

/// The `.lproj` tables themselves: one sub-bundle per language, loaded from
/// `Bundle.module` and cached — the same reasoning `AppLanguage.current`
/// already carried one level up, one bundle per language rather than one per
/// row of a hovered list.
///
/// Not `NSLocalizedString`: that hands the language to the system's own bundle
/// resolution, which would answer `Locale.preferredLanguages` again rather than
/// `AppLanguage.current`, and has no way to ask about a language other than the
/// running one — which every localization test in this suite needs to do.
public enum Localized {
    /// English is the key, and English is also what a missing bundle or a
    /// missing key falls back to — so a table that never made it out of the
    /// migration reads as untranslated English rather than a crash.
    public static func string(_ key: String, language: AppLanguage) -> String {
        guard language != .en else { return key }
        return cache.table(for: language)[key] ?? key
    }

    /// The path to a language's `Localizable.strings`, so a test can read the
    /// shipped table as data — `Bundle.module` inside a test target resolves to
    /// the test's own bundle, not `HelmUI`'s, so this is the only way a test
    /// outside this module can see what actually ships.
    public static func stringsFile(for language: AppLanguage) -> URL? {
        Bundle.module
            .url(forResource: language.rawValue, withExtension: "lproj")?
            .appendingPathComponent("Localizable.strings")
    }

    private static let cache = TableCache()

    private final class TableCache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [AppLanguage: [String: String]] = [:]

        func table(for language: AppLanguage) -> [String: String] {
            lock.lock()
            defer { lock.unlock() }
            if let existing = tables[language] { return existing }
            let loaded = Self.load(language)
            tables[language] = loaded
            return loaded
        }

        private static func load(_ language: AppLanguage) -> [String: String] {
            guard let bundleURL = Bundle.module.url(forResource: language.rawValue,
                                                     withExtension: "lproj"),
                  let bundle = Bundle(url: bundleURL),
                  let path = bundle.path(forResource: "Localizable", ofType: "strings"),
                  let dict = NSDictionary(contentsOfFile: path) as? [String: String]
            else { return [:] }
            return dict
        }
    }
}

/// A size in the user's language: "432,95 ГБ", "1.5 GB". One formatter for
/// every screen — see `HelmBytes` for why that had to be said out loud.
public func Bytes(_ count: Int) -> String {
    HelmBytes.string(count, language: AppLanguage.current.rawValue)
}

/// A number in the user's language: "1,5" where the language writes a comma.
/// The rule summary printed `String(format: "%.1f", …)` beside sizes that
/// `Bytes` had already written with a comma, so one line read "1.5 МБ" next to
/// "1,5 ГБ".
public func Decimal(_ value: Double, decimals: Int = 1) -> String {
    HelmBytes.decimal(value, decimals: decimals, language: AppLanguage.current.rawValue)
}

/// A count in the user's language: "1 499 308", "1.499.308". Beside `Bytes` and
/// `Decimal` because it is the same mistake one class of number over — a scan
/// of `/` reported "1499308 files", where macOS itself groups the digits.
///
/// Not `Decimal`, which turns grouping off on purpose: that one writes the
/// mantissa of a size, where a separator would be a second decimal mark.
public func Count(_ value: Int) -> String {
    HelmBytes.grouped(value, language: AppLanguage.current.rawValue)
}

/// Dates in the app's language, not the system's.
///
/// `RelativeDateTimeFormatter()` with no locale answers in the system language,
/// so an Italian or Polish Mac — outside Helm's eight, therefore shown an
/// English UI — read "Checked 2 ore fa". The formatters were also built once and
/// held, which meant they kept the language the app started in after the user
/// picked another one in Settings. Keyed by language, so both go away.
public enum HelmDates {
    /// "2 hours ago", «2 часа назад» — for a timestamp whose distance is the
    /// point, not its calendar position.
    public static func relative(_ date: Date, to now: Date = Date(),
                                language: String = AppLanguage.current.rawValue) -> String {
        cache.relative(language: language).localizedString(for: date, relativeTo: now)
    }

    /// A log line's clock, to the second, in the app's own language-independent
    /// form: the file writes `HH:mm:ss.SSS` and the live view must agree with it
    /// digit for digit, or the same event reads as two.
    public static func logTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// Day and minute, short: a report covering thirty days needs the day, and a
    /// morning's worth of moves needs the minute.
    public static func dayAndMinute(_ date: Date,
                                    language: String = AppLanguage.current.rawValue) -> String {
        cache.absolute(language: language).string(from: date)
    }

    /// A calendar day written down as "2026-07-28" — the changelog's entries —
    /// in the language's own long form: "28 июля 2026 г.", "28. Juli 2026".
    ///
    /// The stored form stays as it is: it sorts, it is what the entries are
    /// keyed by, and it is not a date anybody reads. Anything that is not a day
    /// comes back untouched, because the changelog is written by hand and a
    /// blank line under a version number reads as a broken sheet rather than as
    /// a typo in the data.
    ///
    /// Parsed and written in the same time zone. Parsed in UTC and written in
    /// the reader's, half the world would see the 27th.
    public static func day(_ stored: String,
                           language: String = AppLanguage.current.rawValue) -> String {
        guard let date = cache.storage.date(from: stored) else { return stored }
        return cache.day(language: language).string(from: date)
    }

    /// The same long day, for a date the app already holds.
    ///
    /// A file's modification time is a moment, but "not modified since
    /// 09.03.2024, 19:00" answers a question nobody asked — the advice it
    /// explains is measured in months. `dayAndMinute` is for a report of
    /// today's activity; this is for a date far enough back that the minute is
    /// noise.
    public static func day(_ date: Date,
                           language: String = AppLanguage.current.rawValue) -> String {
        cache.day(language: language).string(from: date)
    }

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var relatives: [String: RelativeDateTimeFormatter] = [:]
        private var absolutes: [String: DateFormatter] = [:]
        private var days: [String: DateFormatter] = [:]

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

        func day(language: String) -> DateFormatter {
            lock.lock(); defer { lock.unlock() }
            if let existing = days[language] { return existing }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            // The zone the stored day was parsed in, so the day cannot shift.
            formatter.timeZone = storage.timeZone
            days[language] = formatter
            return formatter
        }

        func relative(language: String) -> RelativeDateTimeFormatter {
            lock.lock(); defer { lock.unlock() }
            if let existing = relatives[language] { return existing }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.locale = Locale(identifier: language)
            relatives[language] = formatter
            return formatter
        }

        func absolute(language: String) -> DateFormatter {
            lock.lock(); defer { lock.unlock() }
            if let existing = absolutes[language] { return existing }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: language)
            absolutes[language] = formatter
            return formatter
        }
    }
}

/// Quotation marks belong to the language too. VPN and the settings window
/// already spelled them out per language; anything that quotes a value the user
/// typed goes through here instead of hard-coding English's pair.
///
/// Which marks a language uses is looked up, not remembered — the same rule the
/// units and the pane names follow. Counted over the 1176 `Localizable.loctable`
/// files macOS ships, for this exact shape (a substituted name between a pair):
///
///     fr   «\u{00A0}%@\u{00A0}»  3206     « %@ » with plain spaces   12
///     de   „%@“                  3674
///     ru   «%@»                   483
///     es   “%@”                  2768     «%@»                        0
///     ja   “%@”                  3099     「%@」                       1
///     zh   “%@”                  3399
///     pt   “%@”                   378
///
/// Three of the eight had been translated rather than read. French put ordinary
/// spaces inside its guillemets, which is not only the wrong character but a
/// line-breaking one: a name can end up on the next line from the mark that
/// opens it. Spanish was given guillemets and Japanese corner brackets; macOS
/// uses curly quotes for both when what it quotes is a name — 「」 does other
/// work in Japanese, and this helper only ever wraps a name.
public func Quoted(_ text: String, language: AppLanguage = AppLanguage.current) -> String {
    let nbsp = "\u{00A0}"
    switch language {
    case .ru: return "«\(text)»"
    case .fr: return "«\(nbsp)\(text)\(nbsp)»"
    case .de: return "„\(text)“"
    case .en, .es, .ja, .zh, .pt: return "“\(text)”"
    }
}
