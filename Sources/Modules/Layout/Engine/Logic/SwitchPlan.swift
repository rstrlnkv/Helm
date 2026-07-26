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
        return SwitchPlan(backspaces: word.count + tail.count, insert: replacement + tail)
    }
}
