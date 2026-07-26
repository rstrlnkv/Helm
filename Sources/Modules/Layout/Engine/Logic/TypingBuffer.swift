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

    public init() {}

    public var word: String { String(characters) }

    /// Feeds one event. Returns the completed word when this event ended one,
    /// and nil otherwise.
    @discardableResult
    public mutating func accept(_ event: Event) -> String? {
        switch event {
        case .character(let character):
            guard characters.count < Self.maxLength else { return nil }
            characters.append(character)
            return nil
        case .backspace:
            if !characters.isEmpty { characters.removeLast() }
            return nil
        case .space, .newline, .punctuation, .navigation, .click, .focusChange:
            guard !characters.isEmpty else { return nil }
            let finished = String(characters)
            characters.removeAll()
            return finished
        }
    }

    public mutating func clear() { characters.removeAll() }
}
