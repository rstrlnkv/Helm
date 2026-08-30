import Foundation

/// The one typing habit Helm is sure enough about to correct on its own.
///
/// It shared a file with the abbreviation table until that feature was cut,
/// which is the only reason the two were ever near each other: they arrived at
/// `replaceWord` by the same door and have nothing else in common. macOS ships
/// abbreviations in Text Replacement and syncs them; it does not ship this.
enum TypingHabits {

    /// A capital held a moment too long: `ПРивет` → `Привет`.
    ///
    /// Nil for everything else, and the boundaries are the point:
    ///
    /// - `ПРИВЕТ` is a decision, not a slip. Correcting somebody who is
    ///   shouting on purpose is worse than leaving a typo.
    /// - `ПР` has nothing after it to prove the intent, and two capitals is
    ///   what an abbreviation looks like.
    /// - `CDs` is the same thing one letter longer, and it was corrected to
    ///   `Cds` — with `IDs`, `PCs`, `TVs` and `OKs` — for as long as the
    ///   threshold was three. A two-letter abbreviation with a lowercase suffix
    ///   is the commonest shape this rule cannot tell from a slipped Shift, and
    ///   the fourth letter is what separates them: a slip has a word behind it.
    /// - Anything with a digit is an identifier — `IPv6`, `MP3file` — where the
    ///   shape is the meaning.
    ///
    /// **What it still cannot tell**, recorded rather than claimed away:
    /// `OSes`, `ТВшник` and `IPhone` read as slips to this rule and always did.
    /// There is no test of the letters that separates those from `ПРивет` —
    /// which is why the switch ships off, and why its note names the boundary
    /// this has instead of promising one it does not.
    ///
    /// The rule changes exactly one letter. A correction that also converted
    /// the layout would be two edits to one word, which the undo shortcut
    /// cannot take back in one press.
    static func corrected(_ word: String) -> String? {
        let letters = Array(word)
        guard letters.count >= 4 else { return nil }
        guard !letters.contains(where: \.isNumber) else { return nil }
        guard letters[0].isUppercase, letters[1].isUppercase else { return nil }
        // The third letter is what separates a slip from a decision.
        guard letters[2].isLowercase else { return nil }

        var corrected = letters
        corrected[1] = Character(String(letters[1]).lowercased())
        return String(corrected)
    }
}
