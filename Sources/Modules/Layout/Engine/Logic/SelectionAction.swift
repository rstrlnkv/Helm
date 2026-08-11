import Foundation

/// What a shortcut does to the selected text.
///
/// The last-word conversion and these are different mechanisms wearing the same
/// coat. The word one knows what was typed because it watched it being typed;
/// these know nothing until they ask the focused app what is selected. So they
/// can act on text Helm never saw — a paragraph pasted from somewhere, a file
/// name in the Finder, a message somebody else wrote — which is the whole point
/// and also the reason each one refuses to make an edit that changes nothing.
/// One case, kept as an enum because the transform below is what the engine
/// asks, and a bare function would lose the name of what is being done.
///
/// It had three. Transliteration went because it is not reversible: `ь` maps to
/// nothing and `й`/`и` both map to `i`, so `соль` came back `сол` and `Русский`
/// came back `Русскии` — four of eight sample words lost characters, on a
/// transform whose own test file called both directions "reversible-ish, which
/// is the whole reason they are safe to put on a shortcut". Changing case went
/// because macOS already offers it in Edit ▸ Transformations wherever text can
/// be edited at all.
enum SelectionAction: String, Codable, CaseIterable, Sendable {
    /// The same keys read through the other layout: `ghbdtn` → `привет`.
    case convert
}

/// The transform, applied. Separate from the action so the engine can ask
/// "what would this become" without a keyboard, a clipboard or an app.
struct SelectionTransform: Sendable {
    /// Layout conversion needs the pair of input sources, which only the engine
    /// knows; the other two are pure.
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
    func apply(_ action: SelectionAction, to text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let result: String? = switch action {
        case .convert: convert(text)
        }
        guard let result, result != text else { return nil }
        return result
    }
}
