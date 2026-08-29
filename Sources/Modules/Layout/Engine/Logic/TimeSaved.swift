import Foundation

/// What the module probably saved, and the word «probably» is load-bearing.
///
/// **This is an estimate, and it is the only figure in the app that is.** Every
/// other number Helm draws is measured — bytes on disk, words fixed, seconds a
/// tunnel has been up. This one is arithmetic over an assumption about how
/// long a person takes to notice a word came out wrong and put it right, and
/// the screen has to say so: «≈» before the figure, and a line naming the
/// assumption under it. Without that it is a marketing counter — «Helm saved
/// you four hours» — which nobody can check and nobody can argue with.
///
/// The assumption is deliberately conservative. It was arrived at by writing
/// down what actually happens, not by picking a round number that flatters the
/// app, and it is stated here so it can be argued with in one place:
///
/// - **noticing** — the eye reaches the end of the word and something is wrong
/// - **clearing it** — a held backspace, roughly a character at a time
/// - **switching** the input source, one keystroke and the pause around it
/// - **typing it again**, at an ordinary rate
///
/// The two constants below are what those four come to. They are not measured
/// — they are a stated position, which is why they carry their own names and
/// their own test rather than sitting inline in a multiplication.
enum TimeSaved {

    /// Noticing, reaching for the keyboard, and the layout switch itself. Paid
    /// once per word however long the word is.
    static let secondsPerWord = 1.4

    /// Clearing one character and typing it again. Paid per character, so a
    /// long word is worth more than a short one — which is the whole reason the
    /// ledger keeps a character count beside the word count.
    static let secondsPerCharacter = 0.2

    /// The estimate, in seconds, for a period's two figures.
    ///
    /// Zero words is zero seconds and not «about zero»: nothing happened, and
    /// an estimate of nothing is a figure with no subject.
    static func seconds(words: Int, characters: Int) -> TimeInterval {
        guard words > 0 else { return 0 }
        return Double(words) * secondsPerWord + Double(characters) * secondsPerCharacter
    }
}
