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
struct RememberedWord: Equatable, Sendable {
    let word: String
    /// nil when the word ended by the caret leaving rather than by a character.
    let ending: Character?
    let app: String

    init(_ completion: TypingBuffer.Completion, in app: String) {
        self.word = completion.word
        self.ending = completion.ending
        self.app = app
    }

    /// The word still being typed. Nothing has ended it, so it has no ending —
    /// and it needs the app for the same reason the finished one does. The
    /// gesture reaches the live buffer first and the buffer carries no app, so
    /// that door made the blind edit with no check at all: an app change that
    /// is neither a keystroke nor a left click — a Space swipe, an alert, any
    /// program calling `activate()` — is invisible to the tap, and the
    /// half-typed word went wherever the keyboard had gone.
    init(inProgress word: String, in app: String) {
        self.word = word
        self.ending = nil
        self.app = app
    }

    /// An empty id is "no idea which app", which matches nothing — the rule
    /// `UndoRecord` and `AppScope` both apply before typing at all.
    func belongs(to bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID == app
    }
}
