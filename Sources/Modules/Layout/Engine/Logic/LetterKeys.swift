import Carbon
import Foundation

/// Which keys type a letter in *some* layout this Mac has installed.
///
/// **A key is only punctuation in the layout you are holding**, and the tap was
/// asking the wrong one. `,` types `б` in Russian, `;` types `ж`, `[` types `х`
/// — but the tap classifies by what the key produces right now, so on a latin
/// layout those arrive as `.punctuation`, and punctuation confirms a word. The
/// word is cut at the letter: `cgfcb,j` confirms `cgfcb`, converts it, and
/// starts again at `j`.
///
/// The translation already knows better (`96afdc45`); this is the half that
/// decides where a word ends. Asked of every installed layout rather than of
/// the current one, because the person typing has one of them in mind and the
/// tap cannot know which.
///
/// **Nothing about a language here.** It is a fact about the keyboard, so a
/// Greek, Armenian or Hebrew layout gets the same answer for the same reason —
/// and a Mac with only latin layouts gets today's behaviour exactly, because no
/// layout makes a comma a letter.
struct LetterKeys {

    private let codes: Set<UInt16>

    init(tables: [[UInt16: Character]]) {
        var found: Set<UInt16> = []
        for table in tables {
            for (code, character) in table where character.isLetter {
                found.insert(code)
            }
        }
        // **Never the space.** It is the word boundary this whole path rests
        // on, and a layout that put a letter on that keycode would otherwise
        // make a boundary part of a word and swallow the sentence.
        found.remove(UInt16(kVK_Space))
        codes = found
    }

    func contains(_ code: UInt16) -> Bool { codes.contains(code) }
}
