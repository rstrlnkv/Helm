import AppKit
import SwiftUI

/// **The page's search in the header row: a 36 pt capsule holding an unbezeled `NSSearchField`, 283 wide, or, under
/// Always Collapse Search, a 36 pt magnifier while it rests.**
///
/// The capsule is the surface: `HelmSurface.barPlate` under `.flat`, the system's interactive glass in its own
/// container under `.liquidGlass`. `SettingsWindow.minSize` is measured with the open width, on the Log page, in
/// each of the eight languages. Return is the only thing that submits.
/// `sendsWholeSearchString` makes the keystrokes reach the page through the binding alone, and
/// `sendsActionOnEndEditing` off keeps ending the edit (focus moving elsewhere) from firing the action
/// as well; `recentsAutosaveName` nil keeps no history of what was typed.
///
/// **Resting (`rests`).** The field stays mounted, so the binding and what walks the view for it keep working; when
/// it rests it is invisible, out of hit-testing and out of accessibility, and the slot is `HelmHeaderActions.side`
/// wide with a magnifier button on the same capsule, which VoiceOver names as the field is named. A press on it,
/// or ⌘F (which opens and focuses the field on every page with a search, whatever the setting), opens the slot to
/// `width` and focuses the field. It closes again when the editing ends with the field
/// empty (Escape in an empty field, a click elsewhere, focus moving away); a query keeps it open. Only the slot's
/// width moves, by `HelmMotion.interface`, which Reduce Motion cuts.
struct HelmHeaderSearch: View {
    /// The Kit's Search Field (Figma 8:102), the owner's size. The Log page's French prompt, «Rechercher dans le journal», measured with 8 pt to spare in the old 200, so it reads uncut in this width; no other prompt was measured.
    nonisolated static let width: CGFloat = 283

    /// **The one rest predicate.** The search rests as a magnifier only while the setting is on, nobody has opened it
    /// (`isOpen`: a press, ⌘F, or the editor being up) and it holds no query: a query is never hidden behind a glyph.
    nonisolated static func rests(alwaysCollapse: Bool, isOpen: Bool, hasQuery: Bool) -> Bool {
        alwaysCollapse && !isOpen && !hasQuery
    }

    let search: HelmToolbarSearch
    @Environment(\.helmBarAppearance) private var appearance
    @Environment(\.helmHeaderChoices) private var choices
    @State private var isOpen = false
    @State private var focusRequests = 0

    var body: some View {
        let rests = Self.rests(alwaysCollapse: choices.collapseSearch, isOpen: isOpen,
                               hasQuery: !search.text.wrappedValue.isEmpty)
        switch appearance {
        case .flat:
            slot(rests: rests).background(HelmSurface.barPlate, in: Capsule())
        case .liquidGlass:
            GlassEffectContainer {
                slot(rests: rests).glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }

    private func slot(rests: Bool) -> some View {
        ZStack(alignment: .leading) {
            HelmHeaderSearchField(search: search, isOpen: $isOpen, focusRequests: $focusRequests,
                                  collapses: choices.collapseSearch, rests: rests)
                .frame(width: Self.width, height: HelmHeaderActions.side)
                .opacity(rests ? 0 : 1)
                .allowsHitTesting(!rests)
                .accessibilityHidden(rests)
            if rests {
                Button {
                    isOpen = true
                    focusRequests += 1
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.large)
                        .frame(width: HelmHeaderActions.side, height: HelmHeaderActions.side)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HelmA11y.searchField)
                .help(HelmA11y.searchField)
            }
        }
        .frame(width: rests ? HelmHeaderActions.side : Self.width, height: HelmHeaderActions.side, alignment: .leading)
        // The field is wider than the slot while it opens and closes; the mask is the capsule, outset a little
        // when open so the focus ring (drawn outside the field) is not cut.
        .mask { Capsule().padding(rests ? 0 : -8) }
        .animation(HelmMotion.interface, value: rests)
    }
}

private struct HelmHeaderSearchField: NSViewRepresentable {
    let search: HelmToolbarSearch
    @Binding var isOpen: Bool
    @Binding var focusRequests: Int
    let collapses: Bool
    let rests: Bool

    func makeCoordinator() -> Coordinator { Coordinator(search, isOpen: $isOpen, focusRequests: $focusRequests) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = CapsuleSearchField()
        field.sendsWholeSearchString = true
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = nil
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitted(_:))
        field.setAccessibilityLabel(HelmA11y.searchField)
        context.coordinator.watch(field)
        return field
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        coordinator.unwatch()
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let coordinator = context.coordinator
        // The newest declaration each time: the closures a page hands up are cut from the page's state of this body.
        coordinator.search = search
        coordinator.collapses = collapses
        field.placeholderString = search.prompt
        field.setAccessibilityLabel(HelmA11y.searchField)
        // A resting field is not a stop on the key loop.
        field.refusesFirstResponder = rests
        // Not while it is being typed in: the field editor holds what the person has written, and the
        // binding catches up a keystroke later.
        if field.currentEditor() == nil, field.stringValue != search.text.wrappedValue {
            field.stringValue = search.text.wrappedValue
        }
        if focusRequests != coordinator.servedFocusRequests {
            coordinator.servedFocusRequests = focusRequests
            // Next turn: the slot has opened by then, and a view may not take the focus in the middle of its own update.
            DispatchQueue.main.async { [weak field] in
                guard let field else { return }
                field.refusesFirstResponder = false
                // The open state follows what happened: a field that did not take the focus has no editor to end
                // its editing and fold back, so it must not be left held open.
                if field.window?.makeFirstResponder(field) != true { isOpen = false }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: HelmHeaderSearch.width, height: HelmHeaderActions.side)
    }

    /// The two local-monitor tokens, in a class of their own whose `deinit` removes them: a main-actor class's
    /// `deinit` is nonisolated, and the monitor is read there.
    private final class Monitor {
        var token: Any?
        deinit { if let token { NSEvent.removeMonitor(token) } }
    }

    /// One event across the line between a monitor's `@Sendable` handler and the main actor it already runs on.
    private struct Press: @unchecked Sendable {
        let event: NSEvent
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var search: HelmToolbarSearch
        var collapses = false
        var servedFocusRequests = 0
        /// The F key by position (kVK_ANSI_F): ⌘F is where the key is, not what a Cyrillic layout prints on it.
        private static let fKey: UInt16 = 3
        private let isOpen: Binding<Bool>
        private let focusRequests: Binding<Int>
        private let monitor = Monitor()
        private weak var field: NSSearchField?

        init(_ search: HelmToolbarSearch, isOpen: Binding<Bool>, focusRequests: Binding<Int>) {
            self.search = search
            self.isOpen = isOpen
            self.focusRequests = focusRequests
        }

        /// **⌘F opens and focuses the field, whatever the setting, whenever its window is key.** Caps Lock does not
        /// matter, and a field already being edited keeps its editor and only has its text selected. No other ⌘F
        /// handler exists in the app, so the key is consumed on every page with a search. **Under Always Collapse
        /// Search a press outside it ends its editing**, so a field left empty folds back and the press goes on to
        /// whatever was clicked; with the setting off the press is left alone. One local monitor, installed with the
        /// field and removed with it (`unwatch`, and the `Monitor`'s `deinit`); it sees only this field's window.
        func watch(_ field: NSSearchField) {
            self.field = field
            unwatch()
            monitor.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                let press = Press(event: event)
                return MainActor.assumeIsolated { self?.take(press.event) ?? false } ? nil : event
            }
        }

        func unwatch() {
            if let token = monitor.token { NSEvent.removeMonitor(token) }
            monitor.token = nil
        }

        private func take(_ event: NSEvent) -> Bool {
            guard let field, let window = field.window, event.window === window else { return false }
            switch event.type {
            case .keyDown:
                // Only the modifiers a person holds for a shortcut: Caps Lock (and Fn, numeric pad) do not count.
                guard window.isKeyWindow,
                      event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                      event.keyCode == Self.fKey else { return false }
                isOpen.wrappedValue = true
                if let editor = field.currentEditor() {
                    // Already being typed in: a new focus request would end the editing and restart it.
                    editor.selectAll(nil)
                } else {
                    focusRequests.wrappedValue += 1
                }
                return true
            case .leftMouseDown:
                if collapses, field.currentEditor() != nil,
                   !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                    window.makeFirstResponder(nil)
                }
                return false
            default:
                return false
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            search.text.wrappedValue = field.stringValue
        }

        /// The first change of an editing session: the slot is held open, even when the person deletes the query and
        /// the text is empty again. A field opened by a press or ⌘F is already held open before this.
        func controlTextDidBeginEditing(_ obj: Notification) {
            isOpen.wrappedValue = true
        }

        /// An editing session ended, but not always for good: a click inside the open field, or a focus request while
        /// its editor is up, ends one session and starts the next, and no begin notice follows until a keystroke. So
        /// the slot is let go only if, on the next turn, the field has no editor (a query still holds it open).
        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.field, field.currentEditor() == nil else { return }
                self.isOpen.wrappedValue = false
            }
        }

        /// Escape in an empty field gives up the focus, so the editing ends and the field folds back; with a query in
        /// it the field's own Escape (clearing it) runs.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard collapses, commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  textView.string.isEmpty else { return false }
            control.window?.makeFirstResponder(nil)
            return true
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
