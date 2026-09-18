import AppKit
import SwiftUI

/// The system search field. SwiftUI's `.searchable` needs a toolbar this
/// window doesn't have, and a hand-rolled TextField never matches the real
/// control — the rounded well, the magnifier, the clear button, Escape to
/// cancel and the focus ring all come from `NSSearchField` itself.
///
/// **What it does not come with is a name.** The control carried
/// `placeholderString` and nothing else, and a placeholder is not a name: it
/// disappears the moment there is a value, so the field was anonymous to
/// VoiceOver exactly while somebody was typing in it. Measured on a bare
/// `NSSearchField` (2026-09-16), `accessibilityLabel()` is nil with the field
/// empty and still nil with a word in it — AppKit promotes neither the
/// placeholder nor anything else. `HelmA11y.searchField` is what it says now,
/// and it is set here rather than at the two call sites because the defect
/// belongs to the control: Homebrew's search and the Uninstaller's app filter
/// were the same omission twice, and the third one would have been too.
///
/// `NamedControlsTests` cannot see this and is not the guard for it — it scans
/// for a `Picker` or a `TextField` whose first argument is an empty string
/// literal, and for a `Button` or `Toggle` whose whole label is an image, and an
/// `NSViewRepresentable` is none of those. **The literal is deliberately not
/// written out here**: that scan reads source lines without blanking comments, so
/// prose quoting the shape it forbids is reported as an offence — which is what
/// this paragraph did on its first draft.
/// `ASearchFieldSaysWhatItIsTests` reads the label back off the mounted control
/// instead.
public struct HelmSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Called on Return — searches that hit the network run on submit, not on
    /// every keystroke.
    var onSubmit: (() -> Void)?

    public init(text: Binding<String>, placeholder: String, onSubmit: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.setAccessibilityLabel(HelmA11y.searchField)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.focusRingType = .default
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    public func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        // Re-read alongside the placeholder, and for the placeholder's reason:
        // the app's language changes while it runs, and a name set once in
        // `makeNSView` would keep answering in whichever language the window was
        // first built in.
        field.setAccessibilityLabel(HelmA11y.searchField)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    public final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>
        private let onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self.text = text
            self.onSubmit = onSubmit
        }

        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
            onSubmit?()
        }
    }
}
