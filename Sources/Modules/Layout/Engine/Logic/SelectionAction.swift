import Foundation

/// What a shortcut does to the selected text.
///
/// The last-word conversion and these are different mechanisms wearing the same
/// coat. The word one knows what was typed because it watched it being typed;
/// these know nothing until they ask the focused app what is selected. So they
/// can act on text Helm never saw — a paragraph pasted from somewhere, a file
/// name in the Finder, a message somebody else wrote — which is the whole point
/// and also the reason each one refuses to make an edit that changes nothing.
public enum SelectionAction: String, Codable, CaseIterable, Sendable {
    /// The same keys read through the other layout: `ghbdtn` → `привет`.
    case convert
    /// Russian spelled in Latin letters, or back: `привет` → `privet`.
    case transliterate
    /// lower → UPPER → Title → lower.
    case changeCase
}

/// The transform, applied. Separate from the action so the engine can ask
/// "what would this become" without a keyboard, a clipboard or an app.
public struct SelectionTransform: Sendable {
    /// Layout conversion needs the pair of input sources, which only the engine
    /// knows; the other two are pure.
    public let convert: @Sendable (String) -> String?

    public init(convert: @escaping @Sendable (String) -> String?) {
        self.convert = convert
    }

    /// The replacement, or nil when there is nothing to do.
    ///
    /// Nil rather than the same string back: replacing a selection with itself
    /// is still an edit. It clears the undo stack of the app it happens in, it
    /// scrolls the view, and in a few apps it drops the selection — three
    /// visible consequences for a keystroke that was supposed to do nothing.
    public func apply(_ action: SelectionAction, to text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let result: String? = switch action {
        case .convert: convert(text)
        case .transliterate: Transliteration.convert(text)
        case .changeCase: CaseCycle.apply(text)
        }
        guard let result, result != text else { return nil }
        return result
    }
}
