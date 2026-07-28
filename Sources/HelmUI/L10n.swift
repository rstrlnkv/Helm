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

/// Localize a base (English) string with a table of translations for the other
/// languages. Missing entries fall back to English. Usage:
/// `L("Keep Awake", [.ru: "Не давать спать", .es: "Mantener activo"])`.
public func L(_ english: String, _ table: [AppLanguage: String] = [:]) -> String {
    let lang = AppLanguage.current
    if lang == .en { return english }
    return table[lang] ?? english
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

    /// Day and minute, short: a report covering thirty days needs the day, and a
    /// morning's worth of moves needs the minute.
    public static func dayAndMinute(_ date: Date,
                                    language: String = AppLanguage.current.rawValue) -> String {
        cache.absolute(language: language).string(from: date)
    }

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var relatives: [String: RelativeDateTimeFormatter] = [:]
        private var absolutes: [String: DateFormatter] = [:]

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
public func Quoted(_ text: String) -> String {
    L("“\(text)”", [.ru: "«\(text)»", .es: "«\(text)»", .fr: "« \(text) »",
                    .de: "„\(text)“", .ja: "「\(text)」", .zh: "“\(text)”",
                    .pt: "“\(text)”"])
}
