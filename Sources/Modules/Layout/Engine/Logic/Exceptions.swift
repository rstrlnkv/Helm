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
}
