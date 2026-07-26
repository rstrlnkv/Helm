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

    public static let `default` = ConversionTriggers(onSpace: true, onReturn: true,
                                                     onPunctuation: true)

    public init(onSpace: Bool = true, onReturn: Bool = true, onPunctuation: Bool = true) {
        self.onSpace = onSpace
        self.onReturn = onReturn
        self.onPunctuation = onPunctuation
    }

    public func converts(_ event: TypingBuffer.Event) -> Bool {
        switch event {
        case .space: return onSpace
        case .newline: return onReturn
        case .punctuation: return onPunctuation
        // Ending a word by going somewhere else is not confirming it.
        case .navigation, .click, .focusChange: return false
        case .character, .backspace: return false
        }
    }
}
