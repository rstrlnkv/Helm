import AppKit
import SwiftUI

/// The system search field. SwiftUI's `.searchable` needs a toolbar this
/// window doesn't have, and a hand-rolled TextField never matches the real
/// control — the rounded well, the magnifier, the clear button, Escape to
/// cancel and the focus ring all come from `NSSearchField` itself.
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
