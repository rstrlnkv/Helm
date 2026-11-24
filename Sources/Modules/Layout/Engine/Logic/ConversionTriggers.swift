import Foundation

/// Which endings of a word are taken as "I meant that word", and which merely
/// end it.
///
/// Not every boundary is a confirmation. Moving the caret or clicking elsewhere
/// says the person went somewhere else — converting then edits text they are no
/// longer looking at. A word left in another app is caught by the app checks
/// (`RememberedWord`).
///
/// None of it is a choice: the answers come from how apps behave, not from how
/// a person prefers to work, so they are a decision the app owes rather than a
/// question it asks. As switches they could be set to a combination where «Fix
/// as I type» is on and does nothing.
///
/// An enum, because there is nothing to configure: no test can plant a
/// combination production cannot reach.
enum ConversionTriggers {

    /// Return does **not** confirm, and that is not timidity. In Slack,
    /// Telegram and every other chat, Return sends the message and empties the
    /// field: the backspaces then delete nothing, the replacement is typed into
    /// an empty box, and the newline sends it — so the other person receives
    /// the mistyped word and then a second message with the correction. It
    /// would belong on only where Return means a line break, and no switch can
    /// know which app that is.
    static func converts(_ event: TypingBuffer.Event) -> Bool {
        switch event {
        case .space: return true
        case .newline: return false
        case .punctuation(let character): return confirms(character)
        // Ending a word by going somewhere else is not confirming it. Nor is a
        // chord: ⌘Space, made on noticing the wrong layout, must not budget a
        // backspace for a space that never reached the field.
        case .navigation, .chord, .click: return false
        case .character, .backspace: return false
        }
    }

    /// Characters that end a *sentence*, as opposed to characters that merely
    /// are not letters.
    ///
    /// The tap ends a word at anything that is not a letter, a digit or a slash
    /// included, so if those confirmed, the guards in `LayoutVerdict` against
    /// digits, paths and addresses could never fire (`ghbdtn2024`,
    /// `~/ghbdtn/x`). Those endings finish the word and confirm nothing; only
    /// real punctuation does.
    private static func confirms(_ character: Character) -> Bool {
        // The curly ones too: macOS substitutes them as you type, so a
        // sentence ending in a typed quote arrives here as “ ” ‘ ’.
        ".,!?;:»)]}\"'“”‘’…«(".contains(character)
    }
}
