import Foundation

/// Convert, or leave alone.
///
/// Written as a list of reasons to decline, with exactly one way through. A
/// false positive here does not show a wrong number — it rewrites a sentence
/// somebody was in the middle of, in an app Helm does not own.
public enum LayoutVerdict {
    public enum Decision: Equatable {
        case leave
        case convert(String)
    }

    /// Below this there is not enough evidence for a dictionary to mean
    /// anything: "gj" is as likely a typo as a mislayout.
    public static let minimumLength = 3

    public static func decide(word: String,
                              translated: String,
                              validAsTyped: Bool,
                              validTranslated: Bool,
                              exceptions: Set<String>) -> Decision {
        // The rule that outranks the rest: what was typed is already a word, so
        // it is what they meant.
        guard !validAsTyped else { return .leave }
        guard validTranslated else { return .leave }
        guard !translated.isEmpty, translated != word else { return .leave }
        guard word.count >= minimumLength else { return .leave }
        guard !word.contains(where: \.isNumber) else { return .leave }
        guard !looksLikeAddress(word) else { return .leave }
        guard !isAcronym(word) else { return .leave }
        // Both forms: somebody tired of "минск" appearing will type the word
        // they keep seeing, which is the translated one, not what they typed.
        guard !exceptions.contains(word.lowercased()),
              !exceptions.contains(translated.lowercased()) else { return .leave }
        return .convert(translated)
    }

    /// Paths, URLs and addresses are not prose, and each is correct as typed
    /// even when no dictionary agrees.
    private static func looksLikeAddress(_ word: String) -> Bool {
        word.contains("/") || word.contains("@") || word.contains("\\")
            || word.contains("~") || word.contains(":")
    }

    /// All caps is an acronym often enough that the dictionary's opinion of it
    /// is worth less than the risk.
    private static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
    }
}
