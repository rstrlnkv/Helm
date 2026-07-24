import Foundation

/// Supported UI languages. English is the base (source strings live at the call
/// site); the others come from per-string tables.
public enum AppLanguage: String, CaseIterable, Sendable {
    case en, zh, es, fr, de, ja, ru, pt

    /// Best match from the user's preferred languages, else English.
    public static var current: AppLanguage {
        for code in Locale.preferredLanguages {
            let base = code.prefix(2).lowercased()
            if let lang = AppLanguage(rawValue: String(base)) { return lang }
        }
        return .en
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
