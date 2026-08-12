import Foundation

/// Everything the engine needs from the system, one protocol per syscall family,
/// so the engine itself can be checked without a keyboard.
public protocol KeyTapPort: AnyObject, Sendable {
    /// Starts a listen-only tap. Returns false when Accessibility has not been
    /// granted — the caller must say so rather than appear to work.
    ///
    /// `onModifier` carries the modifier presses and releases that a bound
    /// single key is recognised from. They are a separate stream because they
    /// are not typing: a modifier that types nothing must never reach the
    /// buffer, and the tap that watches for one must still see the keys that
    /// prove it was used as a modifier.
    ///
    /// `died` is the tap saying it has stopped without being asked to.
    /// **A live tap is a fact about the system, not a flag the caller owns.**
    /// macOS revokes one when Accessibility is withdrawn mid-session, and the
    /// port stands down; without this channel the engine went on believing the
    /// tap it started was still there, refused to build another after the person
    /// restored the grant, and published a state saying it was watching. It is a
    /// parameter rather than an optional setter so that a port cannot be
    /// implemented — or faked — without an answer to «what happens when this
    /// stops on its own».
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool
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

/// Reading and replacing whatever is selected in the frontmost app.
///
/// Separate from `TypingPort` because it is a different question asked of a
/// different subsystem: typing is synthesised key events, this is the
/// accessibility tree — and where the tree will not answer, the clipboard.
public protocol SelectionPort: Sendable {
    /// The selected text, or nil when nothing is selected or the app will not
    /// say. Nil is not "empty selection": one means do nothing, the other would
    /// mean replacing the caret's surroundings with something.
    func selectedText() -> String?

    /// The selection as the accessibility tree reports it, and nothing else.
    ///
    /// `selectedText()` falls back to ⌘C when the tree says nothing, which costs
    /// up to 200 ms of polling and clobbers the clipboard on the way. That is
    /// affordable once, when somebody presses a shortcut meaning "do it". It is
    /// not affordable on the modifier tap, which fires whenever the key is
    /// tapped and has to decide in that moment whether there is a selection at
    /// all. An app whose tree says nothing is simply treated as having no
    /// selection, and the tap does what it always did to the last word.
    func selectedTextWithoutClipboard() -> String?

    /// Replaces the selection. False when the app refused, so the caller can
    /// report rather than assume — a failed replace with a reported success is
    /// text somebody thinks they changed.
    func replaceSelection(with text: String) -> Bool
}
