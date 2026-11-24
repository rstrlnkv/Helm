import Carbon
import Foundation

/// Which keys type a letter in *some* layout this Mac has installed.
///
/// A key is only punctuation in the layout you are holding. `,` types `б` in
/// Russian, `;` types `ж`, `[` types `х`, but on a latin layout the tap sees
/// them as `.punctuation`, which confirms a word: `cgfcb,j` would be cut at the
/// comma.
///
/// The translation reads these keys the same way (`KeyRemap`); this is the
/// half that decides where a word ends. Asked of every installed layout rather
/// than of the current one, because the person typing has one of them in mind
/// and the tap cannot know which.
///
/// Nothing about a language here: it is a fact about the keyboard, so a
/// Greek, Armenian or Hebrew layout gets the same answer, and a Mac with only
/// latin layouts is unaffected, because no layout makes a comma a letter.
struct LetterKeys {

    private let codes: Set<UInt16>

    init(tables: [[UInt16: Character]]) {
        var found: Set<UInt16> = []
        for table in tables {
            for (code, character) in table where character.isLetter {
                found.insert(code)
            }
        }
        // Never the space. It is the word boundary this whole path rests
        // on, and a layout that put a letter on that keycode would otherwise
        // make a boundary part of a word and swallow the sentence.
        found.remove(UInt16(kVK_Space))
        codes = found
    }

    func contains(_ code: UInt16) -> Bool { codes.contains(code) }
}
