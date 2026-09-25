import Foundation

/// **The one rule every filterable list on this page answers to.**
///
/// One needle, one substring match — multi-word matching is out of scope, and
/// left for the owner to ask for if a single word turns out not to be enough.
/// Not `localizedCaseInsensitiveContains`, which the Uninstaller's own filter
/// uses (`UninstallerSettingsPage.swift`): that is not diacritic-insensitive,
/// and it reads `Locale.current`, which is not the language this app draws in
/// — the app's language changes while it runs, and a filter that answered
/// differently depending on the system's own locale would be a second,
/// invisible language setting.
enum ListFilter {
    /// Trimmed, and nil means "show everything" — never "matches nothing".
    /// An empty needle would filter every row out rather than none, which is
    /// the opposite of what an empty search field means.
    static func needle(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether `needle` is a substring of any of `fields`, case- and
    /// diacritic-insensitively. `fields` takes optionals directly — a
    /// description that has not loaded yet is nil rather than something a
    /// caller filters out first, so every call site reads the same way.
    static func matches(_ needle: String, _ fields: [String?]) -> Bool {
        fields.contains { field in
            guard let field else { return false }
            return field.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                               range: nil, locale: nil) != nil
        }
    }
}
