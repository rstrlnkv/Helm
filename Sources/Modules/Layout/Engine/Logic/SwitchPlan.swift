import Foundation

/// How a conversion is performed, counted in keystrokes the target app will
/// receive: delete what is there, then type the replacement.
public struct SwitchPlan: Equatable, Sendable {
    public let backspaces: Int
    public let insert: String

    /// `trailing` is the character that ended the word — the space, the return,
    /// the full stop — when the app has already received it.
    ///
    /// It has to be deleted and put back, or the delete count is one short and
    /// `ghbdtn ` becomes `gпривет`. Counted in graphemes, which is what one
    /// press of delete removes, not scalars or bytes.
    public static func make(replacing word: String,
                            with replacement: String,
                            trailing: Character? = nil) -> SwitchPlan? {
        guard !word.isEmpty, !replacement.isEmpty else { return nil }
        let tail = trailing.map(String.init) ?? ""
        // Measured together, not added up: a combining mark joins the
        // character before it into one grapheme, so "приве" + U+0301 is five
        // presses of delete, and a sixth would eat the word before it.
        return SwitchPlan(backspaces: (word + tail).count, insert: replacement + tail)
    }
}
