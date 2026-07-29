import Foundation

/// The word that most recently finished, and the app it finished in.
///
/// Converting it is a blind edit: a fixed number of backspaces sent at whatever
/// the caret is in front of now. That is only correct while the caret is still
/// where the word left it — which is the same reasoning `UndoRecord` is built
/// on, and the same check it makes — which caret moves count is
/// `TypingBuffer.Event.movedTheCaret`, one list rather than a second one written
/// here, because the second one was shorter and left a bare arrow key out of it.
/// The remembered word used to carry no app at
/// all, so a word typed in one place could be edited into another: type
/// `ghbdtn` in Notes, switch to Mail, tap the key, and six backspaces and a
/// Russian word land in Mail.
public struct RememberedWord: Equatable, Sendable {
    public let word: String
    /// nil when the word ended by the caret leaving rather than by a character.
    public let ending: Character?
    public let app: String

    public init(_ completion: TypingBuffer.Completion, in app: String) {
        self.word = completion.word
        self.ending = completion.ending
        self.app = app
    }

    /// An empty id is "no idea which app", which matches nothing — the rule
    /// `UndoRecord` and `AppScope` both apply before typing at all.
    public func belongs(to bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID == app
    }
}
