import Foundation

/// Words the user has told Helm to leave alone.
///
/// Case-insensitive because case is the user's business, not the dictionary's,
/// and trimmed because a trailing space in a settings field is not a decision.
public struct Exceptions: Equatable, Sendable {
    public let words: Set<String>

    public init(words: [String]) {
        self.words = Set(words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    public func contains(_ word: String) -> Bool {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        return words.contains(key)
    }

    /// The stored list with one more word in it, or `nil` when it is already
    /// there.
    ///
    /// **Three buttons say «Never this word»** — the settings page's field, the
    /// lists window's field, and the panel tile's button beside the last
    /// change — and each wrote the array in its own words. Two kept the word as
    /// typed and sorted; the tile lowercased it and appended. So the same word
    /// set aside from the panel arrived in a spelling nobody had typed, at the
    /// bottom of a list that is otherwise alphabetical.
    ///
    /// Kept **as typed**, because that is what two of the three did and because
    /// a person searching this list is searching for what they wrote. The
    /// comparison is still case-insensitive: `contains` lowercases, so a list
    /// holding `Ghbdtn` beside `ghbdtn` would be two rows the module reads as
    /// one.
    ///
    /// `nil` rather than the unchanged array, so a caller can tell «added» from
    /// «already there» — the engine is told to re-read on the first and left
    /// alone on the second.
    public static func adding(_ word: String, to stored: [String]) -> [String]? {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !Exceptions(words: stored).contains(cleaned) else { return nil }
        return (stored + [cleaned]).sorted()
    }
}
