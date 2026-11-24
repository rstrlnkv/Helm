import Foundation

/// **The one rule every filterable list on this page answers to.**
///
/// One needle, one substring match. Not `localizedCaseInsensitiveContains`:
/// that is not diacritic-insensitive, and it reads `Locale.current`, not the
/// app's own language.
enum ListFilter {
    /// Trimmed, and nil means "show everything" — never "matches nothing".
    static func needle(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether `needle` is a substring of any of `fields`, case- and
    /// diacritic-insensitively. A description not loaded yet is a nil field.
    static func matches(_ needle: String, _ fields: [String?]) -> Bool {
        fields.contains { field in
            guard let field else { return false }
            return field.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
