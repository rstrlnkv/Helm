import Foundation

/// Which endings of a word are taken as "I meant that word", and which merely
/// end it.
///
/// Not every boundary is a confirmation. Moving the caret, clicking elsewhere
/// or leaving the window says the person went somewhere else — converting then
/// edits text they are no longer looking at.
///
/// **None of it is a choice any more.** Three toggles on the settings page used
/// to write these, and they could be set to a combination the page then had to
/// apologise for in orange: all three off is «Fix as I type» switched on and
/// doing nothing, over a header still saying «Active». The defaults below were
/// always argued from how apps behave, not from how a person prefers to work —
/// which makes them a decision the app owes rather than a question it asks.
/// Caramba Switcher, the other Mac tool people compare this to, ships one
/// setting in total for the same reason.
/// **An enum, because there is nothing left to configure.** It was a struct of
/// three `var`s with an initialiser, and `reloadSettings` assigned `.default`
/// over whatever it had been given, unconditionally, on every `activate()`. So
/// the only code that could ever see another combination was a test — and
/// `ConversionTriggersTests` used that freedom to plant `onReturn: true`, a
/// state production cannot reach, and prove a branch nothing runs. A fake freer
/// than the port proves nothing about the port.
public enum ConversionTriggers {

    /// Return does **not** confirm, and that is not timidity. In Slack,
    /// Telegram and every other chat, Return sends the message and empties the
    /// field: the backspaces then delete nothing, the replacement is typed into
    /// an empty box, and the newline sends it — so the other person receives
    /// the mistyped word and then a second message with the correction. It
    /// would belong on only where Return means a line break, and no switch can
    /// know which app that is.
    public static func converts(_ event: TypingBuffer.Event) -> Bool {
        switch event {
        case .space: return true
        case .newline: return false
        case .punctuation(let character): return confirms(character)
        // Ending a word by going somewhere else is not confirming it. Nor is a
        // chord: ⌘Space — the gesture someone makes on noticing the wrong
        // layout — used to arrive as a plain space and budget a backspace for a
        // character that never reached the field.
        case .navigation, .chord, .click, .focusChange: return false
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
    private static func confirms(_ character: Character) -> Bool {
        // The curly ones too: macOS substitutes them as you type, so a
        // sentence ending in a typed quote arrives here as “ ” ‘ ’ and used to
        // confirm nothing at all.
        ".,!?;:»)]}\"'“”‘’…«(".contains(character)
    }
}
