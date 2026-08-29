import Foundation

/// Convert, or leave alone.
///
/// Written as a list of reasons to decline, with exactly one way through. A
/// false positive here does not show a wrong number — it rewrites a sentence
/// somebody was in the middle of, in an app Helm does not own.
enum LayoutVerdict {
    enum Decision: Equatable {
        case leave
        case convert(String)
    }

    /// Below this there is no evidence at all: one character is a keystroke,
    /// not a word.
    static let minimumLength = 2

    /// At or below this length a spell checker's answer is not worth having —
    /// almost every two-letter pair lands on something a checker will accept.
    /// These are decided by `ShortWords` instead: convert only towards a word
    /// people actually type. See that file for why permission is the wrong
    /// question here and confidence is the right one.
    static let shortWordLength = 3

    static func decide(word: String,
                       translated: String,
                       validAsTyped: Bool,
                       validTranslated: Bool,
                       exceptions: Set<String>,
                       /// What the person taught the module by putting this
                       /// word back — twice, so a mis-press is not a rule.
                       ///
                       /// **It refuses and never permits.** There is no value
                       /// it can take that turns a `.leave` into a conversion:
                       /// a vocabulary the module wrote for itself, able to
                       /// overrule the dictionary, would let one repeated typo
                       /// become a standing instruction inside somebody else's
                       /// app.
                       learned: Bool = false) -> Decision {
        // The rule that outranks the rest: what was typed is already a word, so
        // it is what they meant.
        guard !validAsTyped else { return .leave }
        guard validTranslated else { return .leave }
        guard !translated.isEmpty, translated != word else { return .leave }
        guard word.count >= minimumLength else { return .leave }
        // Short words do not get to lean on the dictionary: it is too easily
        // satisfied at this length, and being wrong here rewrites a word in
        // the middle of a sentence.
        if word.count <= shortWordLength {
            guard ShortWords.isCommon(translated), !ShortWords.isCommon(word)
            else { return .leave }
        }
        guard !word.contains(where: \.isNumber) else { return .leave }
        guard !looksLikeAddress(word) else { return .leave }
        guard !isAcronym(word) else { return .leave }
        // Both forms: somebody tired of "минск" appearing will type the word
        // they keep seeing, which is the translated one, not what they typed.
        guard !exceptions.contains(word.lowercased()),
              !exceptions.contains(translated.lowercased()) else { return .leave }
        guard !learned else { return .leave }
        return .convert(translated)
    }

    /// The gesture's verdict: the user asked for this word by name, so the
    /// dictionary's guards are rightly skipped — the never-list is not. The
    /// list is also the user's own word, and newer; whoever wants the
    /// conversion anyway removes the entry. Both forms, as `decide` checks
    /// them, and for the same reason.
    static func decideForced(word: String,
                             translated: String,
                             exceptions: Set<String>,
                             learned: Bool = false) -> Decision {
        guard !translated.isEmpty, translated != word else { return .leave }
        guard !exceptions.contains(word.lowercased()),
              !exceptions.contains(translated.lowercased()) else { return .leave }
        // The gesture skips the dictionary because the person asked for this
        // word by name — but they also said, twice, that this exact word is to
        // be left alone, and that is the later instruction. Same reasoning as
        // the never-list one line above.
        guard !learned else { return .leave }
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
