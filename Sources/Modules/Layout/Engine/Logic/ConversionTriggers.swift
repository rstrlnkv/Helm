import Foundation

/// Which endings of a word are taken as "I meant that word", and which merely
/// end it.
///
/// Not every boundary is a confirmation. Moving the caret, clicking elsewhere
/// or leaving the window says the person went somewhere else — converting then
/// edits text they are no longer looking at. Those never convert, and are not
/// offered as a choice. The three that do are offered, because they differ by
/// habit and by app: Return sends the message in most chats, so a conversion on
/// Return lands after it was too late to matter.
public struct ConversionTriggers: Equatable, Sendable {
    public var onSpace: Bool
    public var onReturn: Bool
    public var onPunctuation: Bool

    /// Return is **off** by default, and that is not timidity. In Slack,
    /// Telegram and every other chat, Return sends the message and empties the
    /// field: the backspaces then delete nothing, the replacement is typed into
    /// an empty box, and the newline sends it — so the other person receives
    /// the mistyped word and then a second message with the correction. It
    /// belongs on only where Return means a line break, and the person turning
    /// it on knows which apps those are.
    public static let `default` = ConversionTriggers(onSpace: true, onReturn: false,
                                                     onPunctuation: true)

    public init(onSpace: Bool = true, onReturn: Bool = false, onPunctuation: Bool = true) {
        self.onSpace = onSpace
        self.onReturn = onReturn
        self.onPunctuation = onPunctuation
    }

    public func converts(_ event: TypingBuffer.Event) -> Bool {
        switch event {
        case .space: return onSpace
        case .newline: return onReturn
        case .punctuation(let character): return onPunctuation && confirms(character)
        // Ending a word by going somewhere else is not confirming it.
        case .navigation, .click, .focusChange: return false
        case .character, .backspace: return false
        }
    }

    /// Characters that end a *sentence*, as opposed to characters that merely
    /// are not letters.
    ///
    /// The tap ends a word at anything that is not a letter, which means a
    /// digit or a slash gets there too — and the guards in `LayoutVerdict`
    /// against digits, paths and addresses can then never fire, because the
    /// word was already cut before them. `ghbdtn2024` became `привет2024`, and
    /// `~/ghbdtn/x` became `~/привет/x`. Those endings finish the word and
    /// confirm nothing; only real punctuation does.
    private func confirms(_ character: Character) -> Bool {
        // The curly ones too: macOS substitutes them as you type, so a
        // sentence ending in a typed quote arrives here as “ ” ‘ ’ and used to
        // confirm nothing at all.
        ".,!?;:»)]}\"'“”‘’…«(".contains(character)
    }
}
