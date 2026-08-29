import Foundation

/// The same key presses read through another layout, once both key tables are
/// known. The Carbon half — building a table out of `UCKeyTranslate` — stays in
/// `UCTranslation`; what a *string* becomes is here, where it can be tested
/// without a keyboard.
///
/// **It was all-or-nothing, and that is what killed the selection path.** The
/// tables hold letters only (`character.isLetter`, `UCTranslation.buildTable`),
/// and the loop refused the whole string at the first character it could not
/// find in them. A word is letters, so the last-word path never met the case
/// and stayed healthy; a selection is a sentence, and a sentence has spaces in
/// it. Measured on a Mac with US and Russian installed: `ghbdtn` → `привет`,
/// `ghbdtn rfr` → nil. «Select a sentence and put it right» could not work
/// once, ever, and the only trace was a log line counting the characters it
/// declined.
///
/// So a character the source layout does not carry is **passed through**, and
/// the string is refused only when nothing in it converted at all.
enum KeyRemap {

    /// The text as the other layout would have typed it, or nil when this
    /// layout has nothing to say about it.
    ///
    /// **Nil, not the string back.** A "conversion" that returns its input is
    /// still an edit where it lands: `SelectionTransform` would hand it to the
    /// app, which clears that app's undo stack, scrolls the view and in some
    /// apps drops the selection — three visible consequences for a keystroke
    /// that did nothing. The caller cannot tell the two apart from a string
    /// alone, so the distinction is made here.
    ///
    /// Punctuation passes through rather than converting, and that is a
    /// decision about people rather than about keyboards. Read strictly, the
    /// comma key on US types «б» in Russian — but somebody writing Russian on a
    /// latin layout pressed that key *for a comma*, and saw a comma. Converting
    /// it would be reading the keyboard right and the person wrong.
    static func map(_ text: String, from: [UInt16: Character], to: [UInt16: Character]) -> String? {
        var out = ""
        var converted = false
        for character in text {
            // `Character(_:)` traps on a string that is not one grapheme, and
            // uppercasing is not one-to-one — "ß".uppercased() is "SS". A crash
            // inside a keyboard hook takes the whole app down, so anything this
            // cannot map is appended exactly as it came.
            guard let lower = character.lowercased().first,
                  let code = from.first(where: { $0.value == lower })?.key,
                  let mapped = to[code]
            else {
                // **A letter it cannot map refuses the whole string; anything
                // else is kept.** That line is the whole of this type's
                // judgement, and passing a letter through was measured doing
                // real damage: `дфых` came back `lasх` with a Cyrillic х on
                // the end, because х sits on the `[` key and `[` is not a
                // letter, so it is absent from the latin table. NSSpellChecker
                // accepts `lasх` as an English word — so the verdict, which
                // asks only «is the translation a word», converted somebody's
                // word into a broken one.
                //
                // A space or a comma carries no reading in another layout and
                // is kept because the person put it there. A letter carries
                // exactly the reading this whole type is about, so one it
                // cannot read means it cannot read the word.
                guard !character.isLetter else { return nil }
                out.append(character)
                continue
            }
            out.append(character.isUppercase ? mapped.uppercased() : String(mapped))
            converted = true
        }
        return converted ? out : nil
    }
}
