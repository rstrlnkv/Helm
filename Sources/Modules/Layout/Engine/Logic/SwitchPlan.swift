import Foundation

/// How a conversion is performed, counted in keystrokes the target app will
/// receive: delete what is there, then type the replacement.
public struct SwitchPlan: Equatable, Sendable {
    public let backspaces: Int
    public let insert: String

    /// Counted in graphemes, which is what one press of delete removes — not
    /// scalars, and certainly not bytes.
    public static func make(replacing word: String, with replacement: String) -> SwitchPlan? {
        guard !word.isEmpty, !replacement.isEmpty else { return nil }
        return SwitchPlan(backspaces: word.count, insert: replacement)
    }
}
