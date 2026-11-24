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

    /// At or below this length a spell checker's answer is not worth having —
    /// almost every two-letter pair lands on something a checker will accept.
    /// These are decided by `ShortWords` instead: convert only towards a word
    /// people actually type. See that file for why permission is the wrong
    /// question here and confidence is the right one.
    static let shortWordLength = 3

    /// One letter is a word: Russian has eight one-letter words (`в`, `и`, `с`,
    /// `к`, `о`, `у`, `а`, `я`), prepositions, conjunctions and a pronoun that
    /// turn up in almost every sentence.
    ///
    /// They are decided by `ShortWords.isCommon`, from an explicit list and
    /// never from a dictionary: a checker asked about one character answers
    /// noise. So there is no minimum length: one letter is a word.
    static func decide(word: String,
                       translated: String,
                       validAsTyped: Bool,
                       validTranslated: Bool,
                       exceptions: Set<String>) -> Decision {
        guard !translated.isEmpty, translated != word else { return .leave }

        if word.count <= shortWordLength {
            // Short words do not get to lean on the dictionary: it is too
            // easily satisfied at this length, and being wrong here rewrites a
            // word in the middle of a sentence.
            guard ShortWords.isCommon(translated), !ShortWords.isCommon(word)
            else { return .leave }
            // At one letter the list replaces the checker rather than joining
            // it: asked about a single character a checker answers noise in
            // both directions (it accepts `d` as readily as `в`). The list says
            // what a one-letter word is in both languages, and is stricter:
            // `d` is not on the English side, which is why converting it is safe.
            //
            // Two and three letters keep both bars: the dictionary is worth
            // something there.
            if word.count > 1 {
                guard !validAsTyped, validTranslated else { return .leave }
            }
        } else {
            // The rule that outranks the rest: what was typed is already a
            // word, so it is what they meant.
            guard !validAsTyped else { return .leave }
            guard validTranslated else { return .leave }
        }
        guard !word.contains(where: \.isNumber) else { return .leave }
        guard !looksLikeAddress(word) else { return .leave }
        guard !isAcronym(word) else { return .leave }
        // Both forms: somebody tired of "минск" appearing will type the word
        // they keep seeing, which is the translated one, not what they typed.
        guard !exceptions.contains(word.lowercased()),
              !exceptions.contains(translated.lowercased()) else { return .leave }
        guard !turnsALetterIntoAMark(word, translated) else { return .leave }
        return .convert(translated)
    }

    /// The gesture's verdict: the user asked for this word by name, so the
    /// dictionary's guards are rightly skipped — the never-list is not. The
    /// list is also the user's own word, and newer; whoever wants the
    /// conversion anyway removes the entry. Both forms, as `decide` checks
    /// them, and for the same reason.
    static func decideForced(word: String,
                             translated: String,
                             exceptions: Set<String>) -> Decision {
        guard !translated.isEmpty, translated != word else { return .leave }
        guard !exceptions.contains(word.lowercased()),
              !exceptions.contains(translated.lowercased()) else { return .leave }
        // The gesture skips the dictionary because the person asked for this
        // word by name, but the never-list is their later instruction about
        // this exact word.
        // The dictionary is skipped here, not this: they asked for a word, and
        // a bracket where a letter was is not the word they asked for.
        guard !turnsALetterIntoAMark(word, translated) else { return .leave }
        return .convert(translated)
    }

    /// The same refusals, over a selection rather than a word.
    ///
    /// One gesture, two doors: `fix()` routes to `convertLastWord` →
    /// `decideForced` when nothing is selected, and to the selection path when
    /// something is. Both refuse a word on the never-list and a letter that
    /// would become a mark.
    ///
    /// All or none. A selection half replaced is worse than one left alone:
    /// the person gets a sentence in two alphabets and no idea which half moved.
    /// The same principle `TypingPort.perform` states for its own events.
    ///
    /// Paired by position, which is what a translation produces: `KeyRemap`
    /// maps a character at a time and refuses the whole string at the first
    /// letter it cannot key, so the two sides split the same way. A pair that
    /// does not line up is refused rather than guessed at.
    static func selectionRefused(source: String,
                                 replacement: String,
                                 exceptions: Set<String>) -> Bool {
        let before = source.split(whereSeparator: \.isWhitespace).map(String.init)
        let after = replacement.split(whereSeparator: \.isWhitespace).map(String.init)
        guard before.count == after.count else { return true }
        for (word, translated) in zip(before, after) where word != translated {
            if case .leave = decideForced(word: word, translated: translated,
                                          exceptions: exceptions) { return true }
        }
        return false
    }

    /// A letter may become a letter; it may not become a mark.
    ///
    /// The key table reads `,` as `б`, so every letter has its key in the
    /// other direction too, and some of those keys type punctuation: `дфых`
    /// translates to `las[` and `срфех` to `chat[`, both of which
    /// `NSSpellChecker` accepts as English words. Without this guard the
    /// verdict would rewrite a word into one with a bracket on the end.
    ///
    /// Asymmetric on purpose. A mark becoming a letter is the repair itself —
    /// `cgfcb,j` → `спасибо`, where the comma key was pressed for `б`. A letter
    /// becoming a mark is the opposite, and somebody typing letters meant
    /// letters.
    static func turnsALetterIntoAMark(_ word: String, _ translated: String) -> Bool {
        for (typed, became) in zip(word, translated) where typed.isLetter && !became.isLetter {
            return true
        }
        return false
    }

    /// Paths, URLs and addresses are not prose, and each is correct as typed
    /// even when no dictionary agrees.
    private static func looksLikeAddress(_ word: String) -> Bool {
        word.contains("/") || word.contains("@") || word.contains("\\")
            || word.contains("~") || word.contains(":")
    }

    /// All caps is an acronym often enough that the dictionary's opinion of it
    /// is worth less than the risk.
    /// Two letters at least, because one capital is not an abbreviation: it is
    /// a word at the start of a sentence (`I`, `Я`, `В`). `GDP` and `ООО` are
    /// what it is for.
    private static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }
}
