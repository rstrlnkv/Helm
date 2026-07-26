import Foundation

/// Everything the engine needs from the system, one protocol per syscall family,
/// so the engine itself can be checked without a keyboard.
public protocol KeyTapPort: AnyObject, Sendable {
    /// Starts a listen-only tap. Returns false when Accessibility has not been
    /// granted — the caller must say so rather than appear to work.
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool
    func stop()
}

public protocol TypingPort: Sendable {
    /// Sends `plan.backspaces` deletes then types `plan.insert`. False when the
    /// target refused the events; a partial retype is worse than none.
    func perform(_ plan: SwitchPlan) -> Bool
}

public protocol LayoutSourcePort: Sendable {
    /// Input source ids of every installed keyboard layout.
    func installed() -> [String]
    func current() -> String?
    func select(_ sourceID: String)
}

public protocol TranslationPort: Sendable {
    /// The same key presses, read through another layout. Nil when the pair
    /// cannot be translated, rather than an approximation of it.
    func translate(_ word: String, from: String, to: String) -> String?
}

public protocol SpellPort: Sendable {
    /// Whether the word is a word in the language of that input source. Nil
    /// means no dictionary is available, which is not the same as "not a word"
    /// and must never be read as one.
    func isWord(_ word: String, sourceID: String) -> Bool?
}

public protocol SoundPort: Sendable {
    /// Played when a conversion lands, if the user asked for it. A correction
    /// happens where the eyes already are, so the sound is for the times they
    /// are not — and it is off unless asked for.
    func playSwitch()
}

public protocol SecureContextPort: Sendable {
    /// The cheap half — one syscall, no accessibility round-trip — so it can be
    /// asked on every keystroke rather than once per word.
    func isSecureInput() -> Bool
    /// True while the system has secure input on, or the focused element is a
    /// password field. Reaches the accessibility server, so never on every key.
    func isSecure() -> Bool
    /// Bundle id of the frontmost app; empty when there is none.
    func frontmostBundleID() -> String
}
