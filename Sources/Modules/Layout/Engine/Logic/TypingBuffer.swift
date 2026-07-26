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
        /// Arrows, home, end, tab — the caret moved, so what came before is no
        /// longer adjacent to what comes next.
        case navigation
        case click
        case focusChange
    }

    /// Longer than any word in any language Helm can judge. Past it the tap is
    /// seeing something that is not prose, and holding on to it is a leak.
    public static let maxLength = 64

    private var characters: [Character] = []
    /// True once something was typed that the buffer could not hold.
    private var overflowed = false

    public init() {}

    public var word: String { String(characters) }

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
        case .space, .newline, .punctuation, .navigation, .click, .focusChange:
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
        case .navigation, .click, .focusChange, .character, .backspace: return nil
        }
    }

    public mutating func clear() { characters.removeAll(); overflowed = false }
}
