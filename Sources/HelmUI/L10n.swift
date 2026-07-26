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
