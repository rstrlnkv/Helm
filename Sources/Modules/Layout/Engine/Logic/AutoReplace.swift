import Foundation

/// Abbreviations the person defined: a short token that stands for a longer
/// piece of text they type often.
///
/// The same word boundary the layout conversion uses, and a different question
/// asked there. The order matters and is fixed: an abbreviation is an explicit
/// instruction, so it is asked first, and a word that expanded is never also
/// converted or corrected — two edits to one word is one edit the person cannot
/// take back in a single press.
public struct AutoReplace: Equatable, Sendable {

    public struct Entry: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String { from }
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    private let table: [String: String]

    public init(entries: [Entry]) {
        var table: [String: String] = [:]
        for entry in entries {
            let from = entry.from.trimmingCharacters(in: .whitespacesAndNewlines)
            // An entry that expands to itself fires forever; one that expands
            // to nothing deletes a word somebody typed. Neither is stored, so
            // the engine never has to know they were possible.
            guard !from.isEmpty, !entry.to.isEmpty, entry.to != from else { continue }
            table[from] = entry.to
        }
        self.table = table
    }

    /// Case-sensitive, unlike the exceptions list. An abbreviation is a token
    /// somebody invented, and `ООО` and `ооо` can reasonably be two of them;
    /// folding the case together makes the shorter one impossible to type.
    public func expansion(for word: String) -> String? {
        guard !word.isEmpty else { return nil }
        return table[word]
    }

    public var isEmpty: Bool { table.isEmpty }
}

/// The corrections that are about how a keyboard is held rather than about
/// which layout is on.
public enum TypingHabits {

    /// A capital held a moment too long: `ПРивет` → `Привет`.
    ///
    /// Nil for everything else, and the boundaries are the point:
    ///
    /// - `ПРИВЕТ` is a decision, not a slip. Correcting somebody who is
    ///   shouting on purpose is worse than leaving a typo.
    /// - `ПР` has nothing after it to prove the intent, and two capitals is
    ///   what an abbreviation looks like.
    /// - Anything with a digit is an identifier — `IPv6`, `MP3file` — where the
    ///   shape is the meaning.
    ///
    /// The rule changes exactly one letter. A correction that also converted
    /// the layout would be two edits to one word, which the undo shortcut
    /// cannot take back in one press.
    public static func corrected(_ word: String) -> String? {
        let letters = Array(word)
        guard letters.count >= 3 else { return nil }
        guard !letters.contains(where: \.isNumber) else { return nil }
        guard letters[0].isUppercase, letters[1].isUppercase else { return nil }
        // The third letter is what separates a slip from a decision.
        guard letters[2].isLowercase else { return nil }

        var corrected = letters
        corrected[1] = Character(String(letters[1]).lowercased())
        return String(corrected)
    }
}
