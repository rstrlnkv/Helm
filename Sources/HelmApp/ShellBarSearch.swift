import AppKit
import HelmUI

/// **The page bar's search zone: one plate that holds either the page's search field or a magnifier that
/// stands for it, never both.**
///
/// **What is visible is a function of two readings, the bar's last verdict and the field's editor
/// (`redisplay()`), not of a flag the zone keeps.** The field shows while the bar has not folded the search
/// or while the field holds an editor; otherwise the magnifier shows. A flag set by a press and cleared by
/// some later event is a flag that stays set when the event does not come (focus lost to another window,
/// the page replaced under an open field); a reading of the editor cannot. `redisplay()` is called from
/// `init`, `show`, `apply` and `stateMoved()`; a magnifier press, the end of editing, a field that became
/// first responder and the live action all go through `stateMoved()`.
///
/// **Only `apply` writes `isFolded`, and `show` never touches it.** The bar calls `apply` when a verdict
/// changes, not on every pass (`ShellPageBarView.layout()`), so a reset in `show` would leave the field open
/// for good while the verdict stays folded, and a zone that guessed the verdict itself would disagree with
/// the bar that decides it.
///
/// **The reading after the end of editing happens a turn later.** The notification arrives while the field
/// editor is still attached, so a reading taken inside it says "being edited" about a field that is about to
/// be idle; and a Return ends the session and starts another at once (measured by
/// `TheSearchRestsAsItsMagnifierTests.testAFieldTakesAndGivesUpItsEditorInAWindowThatWasNeverShown`).
/// `controlTextDidEndEditing` therefore
/// schedules `stateMoved()` on the main queue and the reading is taken inside the block. A field that
/// becomes first responder (a click, Tab, `makeFirstResponder`) does the same from `becomeFirstResponder`;
/// the test file reaches it by `makeFirstResponder` only. The clear button with no editor sends
/// the action alone, with no editing at either end, so the action handler calls `stateMoved()` itself when
/// the zone is live; when it is not, it writes the page's text back and returns.
///
/// **One local monitor, not one per press target.** Assumed, not measured: a press on content that cannot
/// take first responder leaves the field's editor in place and nothing in AppKit ends it. So the monitor
/// hands every left mouse-down to `pressed(at:in:)`, which ends the session when the press is in the
/// field's window and outside the bar's view; a press inside the bar does not, since it may be the
/// field's own. The monitor never consumes an event. No test sends an event through the monitor: the
/// test file calls `pressed(at:in:)`.
///
/// **The resting field answers the bar's menu.** With no editor the field's `menu(for:)` returns the menu of
/// the nearest ancestor that has one, which is the bar's own, so a right-click on the zone opens what a
/// right-click anywhere on the bar opens. While editing the field answers AppKit's own `menu(for:)`, which
/// is not the bar's menu; the text menu belongs to the field editor, not to the field.
///
/// **The plate is the bar's.** The zone never sets its frame and animates nothing: opening and folding are
/// changes of that frame made by the bar. Inside the plate the field is unbezeled with no background,
/// because an unbezeled field with `drawsBackground` off leaves the plate unpainted, and a bezeled one
/// paints its own fill even with it off
/// (`TheSearchRestsAsItsMagnifierTests.testAnUnbezeledFieldDrawsTheMagnifierAndTheClearButtonAndNoFill`
/// reads this in both appearances). That test also reads the unbezeled field's intrinsic height as 16 at
/// every control size. An unbezeled field draws its ink above the centre of a 36 pt frame, so
/// `Container.layout()` moves the field down by `inkRise`;
/// `TheSearchRestsAsItsMagnifierTests.testTheInkOfTheFilledFieldSitsAtThePlatesMiddle` reads the ink of the
/// moved field within 1 pt of the middle of a 36 pt plate, in both appearances. **Not seen on a screen:** the
/// field with its ink centred in the plate; the offset is read off that bitmap, not off the running bar.
/// Assumed, not measured: that
/// Return is the only way a non-empty string reaches the field's action (`sendsWholeSearchString` on,
/// `sendsActionOnEndEditing` off), and that `makeFirstResponder(field)` on a field just unhidden in the same
/// call gives it an editor (the test file measures this in a window that was never shown, not in a key one).
@MainActor
final class ShellBarSearch: NSObject, ShellBarZone, NSSearchFieldDelegate {

    /// Moves the zone's field down, in points, so the ink of an unbezeled field sits at the plate's middle.
    private static let inkRise: CGFloat = 4

    /// A search field that reports that it became first responder, and answers the bar's menu while resting.
    private final class Field: NSSearchField {
        var didBecomeFirstResponder: (() -> Void)?

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { didBecomeFirstResponder?() }
            return became
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard currentEditor() == nil else { return super.menu(for: event) }
            var ancestor = superview
            while let view = ancestor {
                if let menu = view.menu { return menu }
                ancestor = view.superview
            }
            return super.menu(for: event)
        }
    }

    /// Holds the field and the magnifier, always both; the field is placed lower than the middle, the
    /// magnifier fills the bounds.
    private final class Container: NSView {
        let field: NSSearchField
        let magnifier: NSButton

        init(field: NSSearchField, magnifier: NSButton) {
            self.field = field
            self.magnifier = magnifier
            super.init(frame: .zero)
            addSubview(field)
            addSubview(magnifier)
        }

        required init?(coder: NSCoder) { fatalError("Container is built in code") }

        override func layout() {
            super.layout()
            field.frame = NSRect(x: 0, y: -ShellBarSearch.inkRise, width: bounds.width, height: bounds.height)
            magnifier.frame = bounds
        }
    }

    private struct Press: @unchecked Sendable {
        let window: NSWindow?
        let location: NSPoint
    }

    let plate: ShellBarPlate
    let field: NSSearchField
    let magnifier: NSButton
    var measuresMoved: (() -> Void)?

    private var search: HelmToolbarSearch?
    private var isLive = false
    private var isFolded = false
    // Read in `deinit`, which Swift 6 treats as nonisolated even on a `@MainActor` class.
    nonisolated(unsafe) private var pressMonitor: Any?

    var view: NSView? { search == nil ? nil : plate }

    var isInUse: Bool { !field.stringValue.isEmpty || field.currentEditor() != nil }

    init(titlebarIsTransparent: Bool) {
        let field = Field()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.sendsWholeSearchString = true
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = nil

        let magnifier = NSButton()
        magnifier.isBordered = false
        magnifier.imagePosition = .imageOnly
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))

        let container = Container(field: field, magnifier: magnifier)
        let plate = ShellBarPlate(appearance: .flat, isActive: true, titlebarIsTransparent: titlebarIsTransparent)
        plate.content = container
        self.field = field
        self.magnifier = magnifier
        self.plate = plate
        super.init()

        field.delegate = self
        field.target = self
        field.action = #selector(submitted(_:))
        field.didBecomeFirstResponder = { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.stateMoved() }
        }
        magnifier.target = self
        magnifier.action = #selector(pressedMagnifier(_:))
        name()
        redisplay()

        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let press = Press(window: event.window, location: event.locationInWindow)
            MainActor.assumeIsolated { self?.pressed(at: press.location, in: press.window) }
            return event
        }
    }

    deinit {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
    }

    // MARK: - ShellBarZone

    func show(_ state: ShellBarZoneState) {
        guard let new = state.content?.search else {
            endEdit()
            search = nil
            return
        }
        if !state.isLive {
            endEdit()
        } else if !state.animated, field.currentEditor() != nil, field.stringValue != new.text.wrappedValue {
            // The session belonged to another page. A re-show of the same page that is not animated and finds
            // the field's text different from the page's also ends the session: the state carries no page
            // identity to tell the two apart.
            endEdit()
        }
        search = new
        isLive = state.isLive
        plate.barAppearance = state.appearance
        plate.isActive = state.appearsActive
        field.placeholderString = new.prompt
        name()
        field.isEnabled = !state.isDimmed
        magnifier.isEnabled = !state.isDimmed
        // The field follows the page's binding when nobody types; never under the caret.
        if field.currentEditor() == nil, field.stringValue != new.text.wrappedValue {
            field.stringValue = new.text.wrappedValue
        }
        redisplay()
    }

    func measure(into measures: inout ShellPageBarView.Measures) {
        measures.hasSearch = search != nil
        measures.searchInUse = search != nil && isInUse
    }

    func apply(_ verdicts: ShellPageBarView.Verdicts) {
        isFolded = verdicts.searchFolded
        redisplay()
    }

    // MARK: - Pressing

    @objc func pressedMagnifier(_ sender: Any?) {
        guard isLive, search != nil, magnifier.isEnabled else { return }
        field.isHidden = false
        field.window?.makeFirstResponder(field)
        stateMoved()
    }

    /// The monitor's decision: a press outside the bar's view ends a session the field holds.
    func pressed(at locationInWindow: NSPoint, in window: NSWindow?) {
        guard window != nil, window === field.window, field.currentEditor() != nil else { return }
        let region = plate.superview ?? plate
        if !region.bounds.contains(region.convert(locationInWindow, from: nil)) { endEdit() }
    }

    // MARK: - Field delegate

    func controlTextDidChange(_ obj: Notification) {
        guard isLive, obj.object as? NSSearchField === field else { return }
        search?.text.wrappedValue = field.stringValue
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSSearchField === field else { return }
        DispatchQueue.main.async { [weak self] in self?.stateMoved() }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        isLive
    }

    /// Return, and the clear button: with `sendsWholeSearchString` on and `sendsActionOnEndEditing` off no
    /// keystroke and no end of editing reaches here. The clear button with no editor sends this alone.
    @objc private func submitted(_ sender: NSSearchField) {
        guard sender === field else { return }
        guard isLive else {
            // AppKit's clear button empties the string before the action arrives; the page still holds its text.
            field.stringValue = search?.text.wrappedValue ?? ""
            return
        }
        search?.text.wrappedValue = field.stringValue
        if !field.stringValue.isEmpty { search?.onSubmit?() }
        stateMoved()
    }

    // MARK: - What is visible

    private func stateMoved() {
        redisplay()
        measuresMoved?()
    }

    private func redisplay() {
        let showsField = !isFolded || field.currentEditor() != nil
        field.isHidden = !showsField
        magnifier.isHidden = showsField
    }

    private func endEdit() {
        if field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
    }

    /// The names are read from the language at hand, so `show` says them again.
    private func name() {
        field.setAccessibilityLabel(HelmA11y.searchField)
        magnifier.setAccessibilityLabel(HelmA11y.searchField)
        magnifier.toolTip = HelmA11y.searchField
    }
}
