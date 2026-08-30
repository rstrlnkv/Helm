import Foundation

/// What a shortcut does to the selected text.
///
/// The last-word conversion and these are different mechanisms wearing the same
/// coat. The word one knows what was typed because it watched it being typed;
/// these know nothing until they ask the focused app what is selected. So they
/// can act on text Helm never saw — a paragraph pasted from somewhere, a file
/// name in the Finder, a message somebody else wrote — which is the whole point
/// and also the reason each one refuses to make an edit that changes nothing.
/// It had three actions and an enum to pick between them. Transliteration went
/// because it is not reversible: `ь` maps to nothing and `й`/`и` both map to
/// `i`, so `соль` came back `сол` and `Русский` came back `Русскии` — four of
/// eight sample words lost characters, on a transform whose own test file called
/// both directions "reversible-ish, which is the whole reason they are safe to
/// put on a shortcut". Changing case went because macOS already offers it in
/// Edit ▸ Transformations wherever text can be edited at all.
///
/// **The enum outlived them by a year.** One case, `String, Codable,
/// CaseIterable`, with a struct wrapping one closure so there was something to
/// switch it over — and every call site passed `.convert`, because there was
/// nothing else to pass. What is left is the rule that is actually worth having:
/// trim, ask, and refuse an edit that changes nothing.
struct SelectionTransform: Sendable {
    /// The same keys read through the other layout: `ghbdtn` → `привет`.
    /// Needs the pair of input sources, which only the engine knows.
    let convert: @Sendable (String) -> String?

    init(convert: @escaping @Sendable (String) -> String?) {
        self.convert = convert
    }

    /// The replacement, or nil when there is nothing to do.
    ///
    /// Nil rather than the same string back: replacing a selection with itself
    /// is still an edit. It clears the undo stack of the app it happens in, it
    /// scrolls the view, and in a few apps it drops the selection — three
    /// visible consequences for a keystroke that was supposed to do nothing.
    func apply(to text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let result = convert(text), result != text else { return nil }
        return result
    }
}
