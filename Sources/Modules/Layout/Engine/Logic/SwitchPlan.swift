import Foundation

/// How a conversion is performed, counted in keystrokes the target app will
/// receive: delete what is there, then type the replacement.
public struct SwitchPlan: Equatable, Sendable {
    public let backspaces: Int
    public let insert: String

    /// `trailing` is the character that ended the word — the space, the return,
    /// the full stop — when the app has already received it.
    ///
    /// It has to be deleted and put back, and forgetting it is not a cosmetic
    /// error: the delete count was one short, so the first letter of the word
    /// survived and `ghbdtn ` became `gпривет`. Counted in graphemes, which is
    /// what one press of delete removes — not scalars, and certainly not bytes.
    public static func make(replacing word: String,
                            with replacement: String,
                            trailing: Character? = nil) -> SwitchPlan? {
        guard !word.isEmpty, !replacement.isEmpty else { return nil }
        let tail = trailing.map(String.init) ?? ""
        // Measured together, not added up. A combining mark joins the character
        // before it into one grapheme, so "приве" + U+0301 is five presses of
        // delete and not six — and the sixth ate the space and the tail of the
        // word before it. Counting them apart was right for every ending that
        // stands on its own and wrong for every one that does not.
        return SwitchPlan(backspaces: (word + tail).count, insert: replacement + tail)
    }
}
