import AppKit
import CoreText
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **While a text is being typed the keys are the field's, and every way out of it is one door.** A press with the Text
/// tool on bare picture puts a field into the overlay's panel and makes it the first responder; "a" typed into it is an
/// "a" and not the Arrow tool; Return and Esc end it, placing a non-empty text and dropping an empty one, and only the
/// press of Esc after that reaches the Esc rule; a palette action and a panel that stops being key end it first; a colour or a step
/// picked meanwhile is the field's and the placed text's. With marked text a key is handed to the input context and `onEnd` is not called.
///
/// In-process: the panel is built and not ordered in, so the events are sent to the field and the overlay by hand. The
/// IME's candidate window over `.screenSaver` and a real keyboard in the Russian layout are the owner's to try; a live
/// input method was not tried.
///
/// What it would print if it failed totally: a field that never became first responder is nil or not the panel's
/// responder (the first test); a key that went to the editor selects Arrow; a text that was dropped leaves no layer.
@MainActor
final class TheTextFieldTakesTheKeysTheEditorWouldTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let click = CGPoint(x: 200, y: 220)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func key(_ code: UInt16, _ characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private let kA: UInt16 = 0, kReturn: UInt16 = 36, kEsc: UInt16 = 53, kEnter: UInt16 = 76

    /// An overlay with the area released, the Text tool chosen and the press made: the field is open.
    private func typing(scale: CGFloat = 1) throws -> (display: DisplayID, view: OverlayView, field: OverlayTextField) {
        results = []
        overlay?.close()
        let rig = try OverlayRig.overlay(scale: scale, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        rig.overlay.perform(.tool(.text))
        rig.overlay.mouseDown(on: rig.display, at: click, flags: [])
        rig.overlay.mouseUp(on: rig.display)
        let field = try XCTUnwrap(rig.view.textField, "the press with the Text tool on bare picture made no field")
        return (rig.display, rig.view, field)
    }

    private func type(_ text: String, in field: OverlayTextField) {
        field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// What the overlay hands over for the picture as it is now; the overlay is finished by it.
    private func handed() throws -> [Annotation] {
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.last else {
            XCTFail("the overlay handed nothing over: \(results)")
            return []
        }
        return layers
    }

    func testThePressMakesTheFieldTheFirstResponderOfThePanelAtTheClick() throws {
        let (_, view, field) = try typing()
        XCTAssertTrue(overlay?.isTyping == true)
        XCTAssertTrue(view.window?.firstResponder === field, "AppKit refused the first responder to the field: \(String(describing: view.window?.firstResponder))")
        // The text starts at the click, inside the field's padding; the view is not flipped, so the top is `height - y`.
        XCTAssertEqual(field.frame.minX + OverlayTextField.padding, click.x, accuracy: 0.5)
        XCTAssertEqual(view.bounds.height - (field.frame.maxY - OverlayTextField.padding), click.y, accuracy: 0.5)
    }

    func testTheFieldDrawsInTheFontAndInkTheLayerWillAndSitsOnItsBaseline() throws {
        let (_, _, field) = try typing()
        overlay?.perform(.color(.blue))
        overlay?.perform(.thickness(.thick))
        type("Hg", in: field)
        let font = try XCTUnwrap(field.font)
        XCTAssertEqual(font.pointSize, 22, "the thick step is 22 pt")
        XCTAssertEqual(font.pointSize, CTFontGetSize(AnnotationText.font(for: .thick)))
        let ink = try XCTUnwrap(field.textColor?.usingColorSpace(.sRGB))
        XCTAssertEqual(ink.blueComponent, 0.95, accuracy: 0.01, "the field's ink is not the picked colour")
        // The glyphs' baseline from the field's top is the padding and the font's ascent, as `AnnotationText.draw` puts it.
        let manager = try XCTUnwrap(field.layoutManager)
        let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let baseline = fragment.minY + manager.location(forGlyphAt: 0).y + field.textContainerInset.height
        let wanted = OverlayTextField.padding + CTFontGetAscent(AnnotationText.font(for: .thick))
        XCTAssertEqual(baseline, wanted, accuracy: 1, "the typed line sits \(baseline - wanted) pt off the line the placed text will")
    }

    /// The key is typed into the field, and the editor does not take it: not from the field, which hands on what it has
    /// no use for, and not when the event is sent to the overlay itself.
    func testAnAIsTypedAndSelectsNoArrowAndEveryKeyIsTheFields() throws {
        let (_, view, field) = try typing()
        XCTAssertEqual(overlay?.palette.tool, .text)
        field.keyDown(with: key(kA, "a"))
        XCTAssertEqual(overlay?.palette.tool, .text, "the key reached the editor and chose the Arrow tool")
        overlay?.keyDown(key(kA, "a"))
        XCTAssertEqual(overlay?.palette.tool, .text, "a key sent to the overlay while typing chose the Arrow tool")
        XCTAssertNotNil(view.textField, "an A key ended the input")
        XCTAssertEqual(field.string, "a", "the key was not typed")
        type("b", in: field)
        XCTAssertEqual(field.string, "ab")
        XCTAssertTrue(overlay?.isTyping == true)
        XCTAssertTrue(results.isEmpty)
    }

    func testReturnPlacesTheTextInOneUndoStepAndTheEditorHasItsKeysBack() throws {
        let (_, view, field) = try typing()
        type("Привет", in: field)
        field.keyDown(with: key(kReturn))
        XCTAssertNil(view.textField, "the field outlived Return")
        XCTAssertTrue(overlay?.isTyping == false)
        XCTAssertEqual(view.drawnShapes.count, 1, "Return placed nothing on the screen")
        XCTAssertTrue(view.window?.firstResponder === view, "the keys did not go back to the editor")
        XCTAssertEqual(overlay?.palette.canUndo, true)
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnShapes.count, 0, "the text was more than one undo step")
        XCTAssertEqual(overlay?.palette.canUndo, false)
        overlay?.perform(.redo)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["Привет"])
        XCTAssertEqual(layers.first?.start, click)
    }

    func testEnterPlacesTheTextToo() throws {
        let (_, view, field) = try typing()
        type("x", in: field)
        field.keyDown(with: key(kEnter))
        XCTAssertNil(view.textField)
        XCTAssertEqual(view.drawnShapes.count, 1)
    }

    func testEscPlacesANonEmptyTextAndOnlyTheNextEscReachesTheRule() throws {
        let (_, view, field) = try typing()
        type("note", in: field)
        field.keyDown(with: key(kEsc))
        XCTAssertNil(view.textField, "Esc left the field open")
        XCTAssertEqual(view.drawnShapes.count, 1, "Esc dropped a non-empty text")
        XCTAssertTrue(results.isEmpty, "the Esc that ended the input also reached the rule: \(results)")
        XCTAssertTrue(view.visiblePlates.isEmpty, "the Esc that ended the input asked the question as well")
        // The next press is the rule's own: a layer is on the picture, so it asks.
        overlay?.keyDown(key(kEsc))
        XCTAssertTrue(results.isEmpty, "the first press of the rule closed the picture with a layer on it")
        XCTAssertFalse(view.visiblePlates.isEmpty, "the first press of the rule did not ask")
        overlay?.keyDown(key(kEsc))
        guard case .cancelled? = results.last else { return XCTFail("the second press of the rule did not close: \(results)") }
    }

    func testEscDropsAnEmptyTextAndTheNextEscClosesAtOnce() throws {
        let (_, view, field) = try typing()
        field.keyDown(with: key(kEsc))
        XCTAssertNil(view.textField)
        XCTAssertEqual(view.drawnShapes.count, 0, "an empty text left a layer")
        XCTAssertEqual(overlay?.palette.canUndo, false, "an empty text left a step")
        XCTAssertTrue(results.isEmpty, "the Esc that ended the input reached the rule")
        overlay?.keyDown(key(kEsc))
        guard case .cancelled? = results.last else { return XCTFail("with nothing on the picture the next Esc did not close: \(results)") }
    }

    func testABlankTextIsDroppedLikeAnEmptyOne() throws {
        let (_, view, field) = try typing()
        type("   ", in: field)
        field.keyDown(with: key(kReturn))
        XCTAssertEqual(view.drawnShapes.count, 0)
        XCTAssertEqual(overlay?.palette.canUndo, false)
    }

    func testARightClickEndsTheInputFirstAsEscDoes() throws {
        let (_, view, field) = try typing()
        type("a", in: field)
        overlay?.rightMouseDown()
        XCTAssertNil(view.textField)
        XCTAssertEqual(view.drawnShapes.count, 1)
        XCTAssertTrue(results.isEmpty, "the right click that ended the input also reached the rule")
    }

    func testAPaletteActionEndsTheInputFirstAndMeetsThePictureWithTheTextOnIt() throws {
        let (_, view, field) = try typing()
        type("hello", in: field)
        overlay?.perform(.tool(.arrow))
        XCTAssertNil(view.textField, "a palette action left the field open")
        XCTAssertEqual(view.drawnShapes.count, 1, "the text was not placed before the action")
        XCTAssertEqual(overlay?.palette.tool, .arrow)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["hello"])
    }

    func testTheExitOfThePaletteTakesTheTextBeingTyped() throws {
        let (_, _, field) = try typing()
        type("last words", in: field)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["last words"], "a text still in its field was lost by the exit")
    }

    func testAColourAndAStepPickedWhileTypingRestyleTheFieldAndTheTextPlacedInIt() throws {
        let (_, view, field) = try typing()
        type("x", in: field)
        overlay?.perform(.color(.blue))
        XCTAssertNotNil(view.textField, "a colour pick ended the input")
        XCTAssertTrue(overlay?.isTyping == true)
        overlay?.perform(.thickness(.thin))
        XCTAssertNotNil(view.textField, "a step pick ended the input")
        XCTAssertEqual(field.font?.pointSize, 12)
        field.keyDown(with: key(kReturn))
        let layer = try XCTUnwrap(try handed().first)
        XCTAssertEqual(layer.style.color, .blue)
        XCTAssertEqual(layer.style.thickness, .thin)
    }

    func testAPanelThatStopsBeingKeyEndsTheInput() throws {
        let (_, view, field) = try typing()
        type("moved on", in: field)
        let panel = try XCTUnwrap(view.window as? OverlayPanel)
        panel.resignKey()
        XCTAssertNil(view.textField, "losing key left the field open")
        XCTAssertEqual(view.drawnShapes.count, 1, "losing key dropped the text")
        XCTAssertTrue(results.isEmpty)
    }

    func testAPressElsewhereEndsTheInputAndTheTextToolStartsAnotherThere() throws {
        let (display, view, field) = try typing()
        type("one", in: field)
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 400), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(view.drawnShapes.count, 1, "the first text was not placed")
        let second = try XCTUnwrap(view.textField, "the second press made no field")
        XCTAssertFalse(second === field)
        XCTAssertEqual(second.frame.minX + OverlayTextField.padding, 400, accuracy: 0.5)
        type("two", in: second)
        overlay?.perform(.select)
        XCTAssertEqual(try handed().map(\.text), ["one", "two"])
    }

    func testAPressOnAPlacedTextSelectsItAndStartsNoField() throws {
        let (display, view, field) = try typing()
        type("hold me", in: field)
        field.keyDown(with: key(kReturn))
        overlay?.mouseDown(on: display, at: CGPoint(x: click.x + 10, y: click.y + 8), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertNil(view.textField, "a press on a placed text started a field")
        XCTAssertFalse(overlay?.isTyping == true)
        XCTAssertEqual(overlay?.palette.selectedTool, .text, "the press did not select the text")
        XCTAssertTrue(view.drawnHandles.isEmpty, "a text has no handles")
    }

    func testAPressOutsideTheAreaStartsNoField() throws {
        let (display, view, field) = try typing()
        field.keyDown(with: key(kEsc))
        overlay?.mouseDown(on: display, at: CGPoint(x: 20, y: 20), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertNil(view.textField)
        XCTAssertFalse(overlay?.isTyping == true)
    }

    func testTheFieldTakesNoMoreThanTheBoundAndNoBreak() throws {
        let (_, _, field) = try typing()
        type(String(repeating: "a", count: AnnotationText.maxLength), in: field)
        XCTAssertEqual(field.string.count, AnnotationText.maxLength)
        type("b", in: field)
        XCTAssertEqual(field.string.count, AnnotationText.maxLength, "a key past the bound was typed")
        type(String(repeating: "c", count: 10), in: field)
        XCTAssertFalse(field.string.contains("c"), "a paste past the bound was taken in part or whole")
    }

    func testMarkedTextIsNeverEndedByAKey() throws {
        let (_, view, field) = try typing()
        // With no input method running the system's context discards a composition when a command key reaches it, so
        // each key is sent to a composition begun anew; what a running method does with Return and Esc is the method's.
        func compose() {
            field.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(field.hasMarkedText(), "the composition did not start, so the key below says nothing")
        }
        compose()
        field.keyDown(with: key(kReturn))
        XCTAssertNotNil(view.textField, "Return ended the input in the middle of a composition")
        compose()
        field.keyDown(with: key(kEsc))
        XCTAssertNotNil(view.textField, "Esc dropped the text in the middle of a composition")
        XCTAssertTrue(overlay?.isTyping == true)
        XCTAssertEqual(view.drawnShapes.count, 0)
        field.unmarkText()
        type("本", in: field)
        field.keyDown(with: key(kReturn))
        XCTAssertNil(view.textField, "with no composition Return no longer ended the input")
    }

    func testTheEditorsKeysAreTheEditorsAgainOnceTheFieldIsGone() throws {
        let (_, view, field) = try typing()
        field.keyDown(with: key(kEsc))
        XCTAssertTrue(view.window?.firstResponder === view)
        overlay?.keyDown(key(kA, "a"))
        XCTAssertEqual(overlay?.palette.tool, .arrow, "after the input the A key is the Arrow tool again")
    }
}
