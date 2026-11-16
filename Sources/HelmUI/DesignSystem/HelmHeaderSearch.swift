import AppKit
import SwiftUI

/// **The page's search in the header row: a 36 pt capsule holding an unbezeled `NSSearchField`, of one fixed width.**
///
/// The capsule is the surface: `HelmSurface.barPlate` under `.flat`, the system's interactive glass in its own
/// container under `.liquidGlass`. It does not grow on focus and does not fold to a magnifier; `SettingsWindow.minSize` is measured with
/// this width, on the Log page, in each of the eight languages. Return is the only thing that submits.
/// `sendsWholeSearchString` makes the keystrokes reach the page through the binding alone, and
/// `sendsActionOnEndEditing` off keeps ending the edit (focus moving elsewhere) from firing the action
/// as well; `recentsAutosaveName` nil keeps no history of what was typed.
struct HelmHeaderSearch: View {
    /// The Kit's Search Field (Figma 8:102), the owner's size. The Log page's French prompt, «Rechercher dans le journal», measured with 8 pt to spare in the old 200, so it reads uncut in this width; no other prompt was measured.
    nonisolated static let width: CGFloat = 283

    let search: HelmToolbarSearch
    @Environment(\.helmBarAppearance) private var appearance

    var body: some View {
        switch appearance {
        case .flat:
            HelmHeaderSearchField(search: search).background(HelmSurface.barPlate, in: Capsule())
        case .liquidGlass:
            GlassEffectContainer {
                HelmHeaderSearchField(search: search).glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }
}

private struct HelmHeaderSearchField: NSViewRepresentable {
    let search: HelmToolbarSearch

    func makeCoordinator() -> Coordinator { Coordinator(search) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = CapsuleSearchField()
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
        CGSize(width: HelmHeaderSearch.width, height: HelmHeaderActions.side)
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

/// The field of the capsule: no bezel and no background, the capsule behind it is the surface.
private final class CapsuleSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { CapsuleSearchFieldCell.self }
        set {}
    }

    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) { fatalError("CapsuleSearchField is built in code") }
}

/// The cell of that field: the glyph, the text and the clear button stand inside the capsule's round ends, and the
/// focus ring follows the capsule's outline (radius half the height) instead of the cell's rectangle.
private final class CapsuleSearchFieldCell: NSSearchFieldCell {
    private static let inset: CGFloat = 8
    /// What the text keeps clear of the glyph, on top of the glyph's own width.
    private static let glyphToText: CGFloat = 6

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        super.searchButtonRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
    }

    /// The text's rect: inside the round ends, `glyphToText` further from the glyph, and as high as one line of the
    /// field's font, centred in the capsule (an unbezeled cell draws from the top of its rect). The editor and the
    /// drawing both take their rect from here.
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
        text.origin.x += Self.glyphToText
        text.size.width = max(0, text.width - Self.glyphToText)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        if line < text.height {
            text.origin.y += ((text.height - line) / 2).rounded()
            text.size.height = line
        }
        return text
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        super.cancelButtonRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { searchTextRect(forBounds: rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                   event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        let radius = cellFrame.height / 2
        NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
    }
}
