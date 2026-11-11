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

/// The things the module does that a person who is not looking must still be
/// told about. It rewrites text in somebody else's app, switches the keyboard
/// under their hands, pauses itself for a password, and loses its grant behind
/// their back — all invisible to VoiceOver, because nothing moved focus and
/// nothing the reader is on changed its value.
public enum LayoutAnnouncement: Equatable, Sendable {
    /// A word was rewritten and the input source switched to match.
    case converted(ConversionEvent)
    /// Secure input began: the module is deliberately deaf until it ends.
    case securePause
    /// macOS took the tap away — the module stopped fixing words entirely.
    case grantLost
}

/// The engine names what happened; the words said and the channel they reach a
/// reader by are the UI's side of this port. Separate from `SoundPort` because
/// the sound is a preference and this is an account: one is off unless asked
/// for, the other exists precisely for the person who was not asked.
public protocol AnnouncePort: Sendable {
    func announce(_ what: LayoutAnnouncement)
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
/// accessibility tree — and where the tree will refuse a write, the clipboard.
public protocol SelectionPort: Sendable {
    /// The selected text, or nil when nothing is selected or the app will not
    /// say. Nil is not "empty selection": one means do nothing, the other would
    /// mean replacing the caret's surroundings with something.
    ///
    /// Falls back to ⌘C when the tree says nothing; `fix()` does not ask this
    /// one, it asks `selectedTextWithoutClipboard()`.
    func selectedText() -> String?

    /// The selection as the accessibility tree reports it, and nothing else.
    ///
    /// `selectedText()` falls back to ⌘C when the tree says nothing, which costs
    /// up to 200 ms of polling and clobbers the clipboard on the way. That is
    /// not affordable on the modifier tap, which fires whenever the key is
    /// tapped and has to decide in that moment whether there is a selection at
    /// all, and `fix()` serves the tap and the hotkey alike. An app whose tree
    /// says nothing is simply treated as having no selection, and the tap does
    /// what it always did to the last word.
    func selectedTextWithoutClipboard() -> String?

    /// Replaces the selection. False when the app refused, so the caller can
    /// report rather than assume — a failed replace with a reported success is
    /// text somebody thinks they changed.
    func replaceSelection(with text: String) -> Bool
}

/// The general pasteboard, as `AXSelection`'s clipboard route uses it.
/// Internal: only `AXSelection` and its test use it.
protocol PasteboardPort: Sendable {
    var types: [String] { get }
    var changeCount: Int { get }
    func string() -> String?
    func clear()
    func setString(_ text: String)
}

/// The focused element's selected text, through the accessibility tree.
protocol FocusedTextPort: Sendable {
    func selectedText() -> String?
    func setSelectedText(_ text: String) -> Bool
}

/// ⌘ plus one key, posted with Helm's marker.
protocol CommandKeyPort: Sendable { func press(_ key: UInt16) }

/// Two moments the engine asks the system again: Helm itself coming to the
/// front (the person may have just granted Accessibility, or edited their
/// layouts, in System Settings) and another application coming to the front
/// (the layout bound to it).
///
/// One port for both, so the engine registers nothing process-wide itself and
/// deactivation is one call.
public protocol AppActivationPort: AnyObject, Sendable {
    /// Starts both observations and replaces any earlier ones: called twice, one
    /// registration of each is left. Both handlers run on the main thread;
    /// `frontmostChanged` gets the new bundle id, and only when it differs from
    /// the last one.
    func startObserving(helmBecameActive: @escaping @Sendable () -> Void,
                        frontmostChanged: @escaping @Sendable (String) -> Void)
    /// Removes both. Idempotent.
    func stopObserving()
}
