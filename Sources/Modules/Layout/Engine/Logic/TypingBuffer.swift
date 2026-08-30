import Foundation

/// The current word, as a state machine over key events.
///
/// It holds what has been typed since the last boundary and nothing else: no
/// history, no file, nothing that outlives the word. That is not tidiness — a
/// tap sees passwords typed into fields an app forgot to mark secure, and the
/// only safe place for them is a buffer that is already gone.
public struct TypingBuffer {
    public enum Event: Equatable {
        case character(Character)
        case backspace
        case space
        case newline
        case punctuation(Character)
        /// Arrows, home, end, tab, escape, pressed on their own — the caret
        /// moved, so what came before is no longer adjacent to what comes next.
        case navigation
        /// A key held with command, control or option, carrying its keycode.
        ///
        /// Ends the word exactly as navigation does and confirms nothing, and is
        /// a separate case for one reason: the convert/undo shortcut is itself a
        /// chord and the head-inserted tap sees its keys before Carbon
        /// dispatches the action, so a chord cannot be treated as proof the
        /// caret moved without the shortcut killing its own precondition.
        ///
        /// **The keycode is here because that reason covers exactly one chord
        /// and the case stood for all of them.** ⌘V inserts text at the caret
        /// and ⌥V types `√`, and both were kept as «not proof the caret moved»
        /// — so the word before them stayed remembered while the field changed
        /// underneath it. Measured: type `ghbdtn`, ⌘V a link, tap the key, and
        /// `ghbdtnhttps://helm.app` became `ghbdtnhttps://heпривет`. With the
        /// code, the engine can compare a chord against the shortcut actually
        /// bound and forgive that one alone.
        case chord(UInt16)
        case click
        case focusChange

        /// Whether this event is proof the caret went somewhere else.
        ///
        /// The module keeps two things that may only be spent at a caret that
        /// has not moved: the record of what to undo and the word that most
        /// recently ended. Both are blind edits of a fixed length, both are
        /// measured against text that was in front of the caret when they were
        /// taken, and both used to answer this question for themselves — which
        /// is how `.navigation` came to invalidate one and be stored across the
        /// other. A chord is the single exception and it is spelled out above:
        /// the gesture's own keys reach the tap before Carbon dispatches the
        /// action, so a chord treated as a caret move has the gesture destroy
        /// its own input.
        public var movedTheCaret: Bool {
            switch self {
            case .navigation, .click, .focusChange: return true
            // `.chord` answers false here because this property cannot know
            // which chord: the shortcut's own keys look like everybody else's
            // until somebody compares them against the binding, and the binding
            // is the engine's. `LayoutEngine.handle` makes that comparison and
            // treats every other chord as a caret move.
            case .character, .backspace, .space, .newline, .punctuation, .chord: return false
            }
        }
    }

    /// Longer than any word in any language Helm can judge. Past it the tap is
    /// seeing something that is not prose, and holding on to it is a leak.
    public static let maxLength = 64

    private var characters: [Character] = []
    /// True once something was typed that the buffer could not hold.
    private var overflowed = false

    public init() {}

    public var word: String { String(characters) }

    /// The word being typed, and only when the buffer holds all of it.
    ///
    /// `finish()` already refuses to report a completion it could not hold in
    /// full, because a plan built from a prefix deletes fewer characters than
    /// were typed and leaves the head of the word standing with a translation
    /// after it. The gesture is the second door into the same arithmetic and it
    /// went through `word`, which hands over the 64-character prefix without
    /// saying it is one — so a 70-letter token was converted 64 characters
    /// deep. Nothing is the right answer here: the module cannot fix a word it
    /// never saw the start of.
    public var wholeWord: String? {
        guard !overflowed, !characters.isEmpty else { return nil }
        return String(characters)
    }

    /// A finished word, and the character that finished it.
    ///
    /// The ending matters as much as the word: a space or a full stop is
    /// already in the text field by then, so a replacement that ignores it
    /// deletes one character too few.
    public struct Completion: Equatable {
        public let word: String
        /// nil when the word ended by the caret leaving rather than by a
        /// character being typed.
        public let ending: Character?
    }

    /// Feeds one event. Returns the completed word when this event ended one,
    /// and nil otherwise.
    @discardableResult
    public mutating func accept(_ event: Event) -> Completion? {
        switch event {
        case .character(let character):
            guard characters.count < Self.maxLength else {
                // Past the limit the buffer no longer describes the field, and
                // a plan built from a prefix deletes fewer characters than were
                // typed — leaving the head of the word in front of the
                // replacement. Poisoned until the next boundary.
                overflowed = true
                return nil
            }
            characters.append(character)
            return nil
        case .backspace:
            if !characters.isEmpty { characters.removeLast() }
            return nil
        case .space, .newline, .punctuation, .navigation, .chord, .click, .focusChange:
            defer { characters.removeAll(); overflowed = false }
            guard !characters.isEmpty, !overflowed else { return nil }
            return Completion(word: String(characters), ending: Self.ending(of: event))
        }
    }

    /// What the app already received. Navigation and clicks type nothing.
    private static func ending(of event: Event) -> Character? {
        switch event {
        case .space: return " "
        case .newline: return "\n"
        case .punctuation(let character): return character
        case .navigation, .chord, .click, .focusChange, .character, .backspace: return nil
        }
    }

    public mutating func clear() { characters.removeAll(); overflowed = false }
}
