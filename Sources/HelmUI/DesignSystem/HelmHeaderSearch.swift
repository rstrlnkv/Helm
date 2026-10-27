import AppKit
import SwiftUI

/// **The page's search in the header row: an `NSSearchField` of one fixed width.**
///
/// It does not grow on focus and does not fold to a magnifier; `SettingsWindow.minSize` is measured with
/// this width, on the Log page, in each of the eight languages. Return is the only thing that submits.
/// `sendsWholeSearchString` makes the keystrokes reach the page through the binding alone, and
/// `sendsActionOnEndEditing` off keeps ending the edit (focus moving elsewhere) from firing the action
/// as well; `recentsAutosaveName` nil keeps no history of what was typed.
struct HelmHeaderSearch: NSViewRepresentable {
    /// Wide enough for the longest prompt in any language to read uncut: French's «Rechercher dans le
    /// journal» on the Log page (the spare is stated once, in `SettingsWindow.minSize`'s comment).
    static let width: CGFloat = 200

    let search: HelmToolbarSearch

    func makeCoordinator() -> Coordinator { Coordinator(search) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.sendsWholeSearchString = true
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = nil
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted(_:))
        field.setAccessibilityLabel(HelmA11y.searchField)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        // The newest declaration each time: the closures a page hands up are cut from the page's state of this body.
        context.coordinator.search = search
        field.placeholderString = search.prompt
        field.setAccessibilityLabel(HelmA11y.searchField)
        // Not while it is being typed in: the field editor holds what the person has written, and the
        // binding catches up a keystroke later.
        if field.currentEditor() == nil, field.stringValue != search.text.wrappedValue {
            field.stringValue = search.text.wrappedValue
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var search: HelmToolbarSearch
        init(_ search: HelmToolbarSearch) { self.search = search }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            search.text.wrappedValue = field.stringValue
        }

        /// The field's action: a Return, or the clear button pressed with no editor (VoiceOver's press reaches
        /// it as a click). Empty text submits nothing.
        @objc func submitted(_ sender: NSSearchField) {
            search.text.wrappedValue = sender.stringValue
            guard !sender.stringValue.isEmpty else { return }
            search.onSubmit?()
        }
    }
}
