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

    /// **One character used to be «a keystroke, not a word», and that was an
    /// English sentence about a Russian problem.** English has two one-letter
    /// words; Russian has eight, and they are `в`, `и`, `с`, `к`, `о`, `у`, `а`
    /// and `я` — prepositions, conjunctions and a pronoun that turn up in
    /// almost every sentence somebody types. Type `d ` on a latin layout and it
    /// stayed `d` for ever.
    ///
    /// They are decided by `ShortWords.isCommon`, from an explicit list and
    /// never from a dictionary: a checker asked about one character answers
    /// noise. Nothing below one, because there is nothing below one.
    static let minimumLength = 1

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
                       exceptions: Set<String>) -> Decision {
        guard !translated.isEmpty, translated != word else { return .leave }
        guard word.count >= minimumLength else { return .leave }

        if word.count <= shortWordLength {
            // Short words do not get to lean on the dictionary: it is too
            // easily satisfied at this length, and being wrong here rewrites a
            // word in the middle of a sentence.
            guard ShortWords.isCommon(translated), !ShortWords.isCommon(word)
            else { return .leave }
            // **At one letter the list replaces the checker rather than joining
            // it.** Asked about a single character a checker answers noise in
            // both directions — it accepts `d` as readily as it accepts `в` —
            // so requiring its yes would refuse every Russian preposition and
            // its no would let nothing through. The list already says what a
            // one-letter word is, in both languages, and it is the stricter
            // answer: `d` is not on the English side, which is the whole
            // reason converting it is safe.
            //
            // Two and three letters keep both bars. The dictionary is worth
            // something there and nothing about that was failing.
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
        // word by name — but they also said, twice, that this exact word is to
        // be left alone, and that is the later instruction. Same reasoning as
        // the never-list one line above.
        // The dictionary is skipped here, not this: they asked for a word, and
        // a bracket where a letter was is not the word they asked for.
        guard !turnsALetterIntoAMark(word, translated) else { return .leave }
        return .convert(translated)
    }

    /// The same refusals, over a selection rather than a word.
    ///
    /// **One gesture, two doors, and only one of them had these.** `fix()`
    /// routes to `convertLastWord` → `decideForced` when nothing is selected,
    /// and to the selection path when something is — and that path wrote
    /// whatever the translation handed back. Put `ghbdtn` on «Never change
    /// these words» *because* Helm kept rewriting it, then select the word —
    /// which is exactly what somebody does when the module has been refusing to
    /// touch it — and it was converted. `дфых` went to `las[` there too, the
    /// case measured in this file's own doc comment.
    ///
    /// **All or none.** A selection half replaced is worse than one left alone:
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

    /// **A letter may become a letter; it may not become a mark.**
    ///
    /// Opening the key table so `,` reads as `б` gave every letter its key in
    /// the other direction too, and some of those keys type punctuation:
    /// measured on this Mac, `дфых` translates to `las[` and `срфех` to
    /// `chat[`, both of which `NSSpellChecker` accepts as English words — a
    /// trailing mark does not trouble it. Without this guard the verdict, which
    /// asks only «is the translation a word», rewrites a word into one with a
    /// bracket on the end.
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
    /// **Two letters at least, because one capital is not an abbreviation.**
    /// It is a word at the start of a sentence — `I`, `Я`, `В` — and this rule
    /// refused every one of them the moment one-letter words became reachable.
    /// `GDP` and `ООО` are what it is for, and they are all longer than this.
    private static func isAcronym(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }
}
