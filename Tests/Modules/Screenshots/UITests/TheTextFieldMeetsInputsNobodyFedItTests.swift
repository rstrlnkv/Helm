import AppKit
import Carbon.HIToolbox
import CoreText
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The text field is still a field when the input is not a person typing a short line.** What the text tool's own tests
/// did not feed it: a paste of ten thousand characters, a text of exactly the bound and one more, the keys a field has
/// and the editor has too (Delete, ⌘Z, ⌘C, ⌘A, ⌘V, ⌘S), a letter of the Russian layout, every way out of the input, two
/// presses in a row, the area pulled by its handle while a text stands open, and lines the field and the layer lay out
/// by different engines (Arabic, Hebrew, Japanese, a tab, an emoji family).
///
/// In-process: the panel is built and not ordered in. What it would print if it failed totally: a field that never opened
/// fails the first `XCTUnwrap`, so nothing after it says anything.
@MainActor
final class TheTextFieldMeetsInputsNobodyFedItTests: XCTestCase {
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

    private func key(_ code: Int, _ characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }

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

    private func handed(_ action: EditorAction = .exit(.confirm)) throws -> [Annotation] {
        overlay?.perform(action)
        guard case .edited(_, _, let layers, _)? = results.last else {
            XCTFail("the overlay handed nothing over for \(action): \(results)")
            return []
        }
        return layers
    }

    func testAPasteOfTenThousandCharactersIsRefusedWholeAndTheFieldIsLeftUsable() throws {
        let (_, view, field) = try typing()
        type("ab", in: field)
        let pasteboard = NSPasteboard.general
        let kept = pasteboard.string(forType: .string)
        defer { pasteboard.clearContents(); if let kept { pasteboard.setString(kept, forType: .string) } }
        for big in [String(repeating: "x", count: 10_000), String(repeating: "я", count: 257), "y" + String(repeating: "z", count: 255)] {
            pasteboard.clearContents()
            pasteboard.setString(big, forType: .string)
            field.setSelectedRange(NSRange(location: 2, length: 0))
            field.paste(nil)
            XCTAssertEqual(field.string, "ab", "a paste of \(big.count) characters changed the field to \(field.string.count) characters")
        }
        field.insertText(String(repeating: "x", count: 10_000), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(field.string, "ab", "typed text of 10 000 characters passed the bound")
        type("c", in: field)
        XCTAssertEqual(field.string, "abc", "the field was not usable after a refused paste")
        XCTAssertNotNil(view.textField)
        XCTAssertTrue(overlay?.isTyping == true)
        // The paste of exactly what is left of the bound goes in whole.
        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "q", count: AnnotationText.maxLength - 3), forType: .string)
        field.setSelectedRange(NSRange(location: 3, length: 0))
        field.paste(nil)
        XCTAssertEqual(field.string.count, AnnotationText.maxLength, "a paste that fits the bound exactly was refused")
    }

    func testATextOfExactlyTheBoundIsPlacedWholeAndOneMoreIsNotTyped() throws {
        let (_, _, field) = try typing()
        for _ in 0..<AnnotationText.maxLength { type("x", in: field) }
        XCTAssertEqual(field.string.count, AnnotationText.maxLength)
        type("y", in: field)
        XCTAssertEqual(field.string.count, AnnotationText.maxLength, "the 257th letter was typed")
        // a mark joins the last letter: still 256 graphemes, so it is taken, and what is placed is what the field shows
        type("\u{301}", in: field)
        let shown = field.string
        let layers = try handed()
        XCTAssertEqual(layers.first?.text, shown, "the layer and the field hold different texts")
    }

    func testTheFieldAndTheLayerLayAStringOutAlike() throws {
        let strings = ["Hello, Helm", "Привет, мир", "日本語のテキスト", "مرحبا بالعالم", "שלום עולם", "Hello שלום 123 مرحبا",
                       "👨‍👩‍👧‍👦🇷🇺 ok", "e\u{301}\u{302} é", "a\tb", "word\tword\tword"]
        for text in strings {
            for step in [AnnotationThickness.thin, .thick] {
                let (_, _, field) = try typing()
                overlay?.perform(.thickness(step))
                type(text, in: field)
                let line = field.frame.width - 2 * OverlayTextField.padding - 2
                let height = field.frame.height - 2 * OverlayTextField.padding
                let layer = try XCTUnwrap(try handed().first, text)
                if line > 22 {  // below it the field keeps a minimum width a short line does not need
                    XCTAssertEqual(layer.frame.width, line, accuracy: 2, "\(text.debugDescription) \(step): the field is \(line) wide, the placed text \(layer.frame.width)")
                }
                XCTAssertEqual(layer.frame.height, height, accuracy: 2, "\(text.debugDescription) \(step): the field is \(height) high, the placed text \(layer.frame.height)")
            }
        }
    }

    func testTheFieldsBaselineIsTheLayersForGlyphsOfAFallbackFont() throws {
        for text in ["日本語のテキスト", "Hello 日本 مرحبا", "👨‍👩‍👧‍👦 ok"] {
            let (_, _, field) = try typing()
            overlay?.perform(.thickness(.thick))
            type(text, in: field)
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: AnnotationText.font(for: .thick)]))
            var ascent: CGFloat = 0
            CTLineGetTypographicBounds(ctLine, &ascent, nil, nil)
            let manager = try XCTUnwrap(field.layoutManager)
            let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let baseline = fragment.minY + manager.location(forGlyphAt: 0).y + field.textContainerInset.height
            XCTAssertEqual(baseline, OverlayTextField.padding + ascent, accuracy: 1.5,
                           "\(text): the typed line's baseline is \(baseline - OverlayTextField.padding - ascent) pt off the placed text's")
            XCTAssertLessThanOrEqual(fragment.height + 2 * OverlayTextField.padding, field.frame.height + 0.5,
                                     "\(text): the line (\(fragment.height)) does not fit the field (\(field.frame.height))")
            overlay?.perform(.exit(.confirm))
        }
    }

    func testDeleteInTheOpenFieldDeletesALetterAndNeverALayer() throws {
        let (display, view, field) = try typing()
        type("keep", in: field)
        field.keyDown(with: key(kVK_Return))
        XCTAssertEqual(view.drawnShapes.count, 1)
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 400), flags: [])
        overlay?.mouseUp(on: display)
        let second = try XCTUnwrap(view.textField)
        type("abc", in: second)
        second.keyDown(with: key(kVK_Delete, "\u{7F}"))
        XCTAssertEqual(second.string, "ab", "Delete did not delete a letter of the field")
        second.keyDown(with: key(kVK_ForwardDelete, "\u{F728}"))
        overlay?.keyDown(key(kVK_Delete, "\u{7F}"))
        XCTAssertEqual(view.drawnShapes.count, 1, "a Delete while typing removed a layer")
        XCTAssertTrue(overlay?.isTyping == true)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["keep", "ab"])
    }

    func testCommandKeysInTheOpenFieldNeverChangeTheEditorsHistory() throws {
        let (display, view, field) = try typing()
        type("first", in: field)
        field.keyDown(with: key(kVK_Return))
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 400), flags: [])
        overlay?.mouseUp(on: display)
        let second = try XCTUnwrap(view.textField)
        type("zz", in: second)
        let window = try XCTUnwrap(view.window)
        let commands: [(String, Int, String, NSEvent.ModifierFlags)] = [
            ("⌘Z", kVK_ANSI_Z, "z", .command), ("⇧⌘Z", kVK_ANSI_Z, "z", [.command, .shift]), ("⌘A", kVK_ANSI_A, "a", .command),
            ("⌘C", kVK_ANSI_C, "c", .command), ("⌘V", kVK_ANSI_V, "v", .command), ("⌘S", kVK_ANSI_S, "s", .command),
            ("⌘X", kVK_ANSI_X, "x", .command),
        ]
        let pasteboard = NSPasteboard.general
        let kept = pasteboard.string(forType: .string)
        defer { pasteboard.clearContents(); if let kept { pasteboard.setString(kept, forType: .string) } }
        for (name, code, letter, flags) in commands {
            let event = key(code, letter, flags: flags)
            let handledByWindow = window.performKeyEquivalent(with: event)
            second.keyDown(with: event)
            XCTAssertTrue(results.isEmpty, "\(name) while typing ended the overlay: \(results)")
            XCTAssertEqual(view.drawnShapes.count, 1, "\(name) while typing changed the editor's layers")
            XCTAssertEqual(overlay?.palette.canUndo, true, "\(name) while typing changed the editor's history")
            XCTAssertEqual(overlay?.isTyping, true, "\(name) ended the input")
        }
        let layers = try handed()
        XCTAssertEqual(layers.first?.text, "first")
    }

    func testALetterOfTheRussianLayoutIsTypedAndNeverATool() throws {
        let (_, view, field) = try typing()
        // The physical A key in the Russian layout says «ф»; the T key says «е».
        field.keyDown(with: key(kVK_ANSI_A, "ф"))
        field.keyDown(with: key(kVK_ANSI_T, "е"))
        overlay?.keyDown(key(kVK_ANSI_R, "к"))
        XCTAssertEqual(field.string, "фе")
        XCTAssertEqual(overlay?.palette.tool, .text)
        XCTAssertNotNil(view.textField)
    }

    func testEveryWayOutOfTheInputKeepsTheTypedText() throws {
        let exits: [(String, EditorAction)] = [("Done", .exit(.confirm)), ("Copy", .exit(.copy)), ("Save", .exit(.save))]
        for (name, action) in exits {
            let (_, _, field) = try typing()
            type("typed", in: field)
            let layers = try handed(action)
            XCTAssertEqual(layers.map(\.text), ["typed"], "\(name) with the field open lost the typed text")
        }
        // The ✕: Esc's own rule, which asks first when there are layers; the text is a layer by then and is not lost silently.
        let (_, view, field) = try typing()
        type("typed", in: field)
        overlay?.perform(.close)
        XCTAssertNil(view.textField)
        XCTAssertEqual(view.drawnShapes.count, 1, "the typed text is a layer after the ✕")
    }

    func testTwoPressesInARowPlaceTheFirstTextAndOpenTheSecondField() throws {
        let (display, view, field) = try typing()
        type("one", in: field)
        overlay?.mouseDown(on: display, at: CGPoint(x: 300, y: 300), flags: [])
        overlay?.mouseDown(on: display, at: CGPoint(x: 400, y: 400), flags: [])
        overlay?.mouseUp(on: display)
        overlay?.mouseUp(on: display)
        let second = try XCTUnwrap(view.textField, "the second press left no field")
        XCTAssertFalse(second === field)
        type("two", in: second)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["one", "two"])
        XCTAssertEqual(layers.last?.start, CGPoint(x: 400, y: 400))
        XCTAssertEqual(view.subviews.compactMap { $0 as? OverlayTextField }.count, 0, "a field outlived the overlay's end")
    }

    func testTheAreaPulledByItsHandleWhileATextIsOpenPlacesTheTextAndMovesTheArea() throws {
        let (display, view, field) = try typing()
        type("stay", in: field)
        overlay?.mouseDown(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: area.maxX - 300, y: area.maxY - 250), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertNil(view.textField)
        XCTAssertEqual(overlay?.isTyping, false)
        let layers = try handed()
        XCTAssertEqual(layers.map(\.text), ["stay"], "the text typed before the area was pulled is not in the file")
    }

    func testABlankFieldAndAFieldOfInvisibleCharactersLeaveNoLayerOnTheScreenOrInTheFile() throws {
        for text in ["", "   ", "\u{200B}", "\u{0}"] {
            let (_, view, field) = try typing()
            type(text, in: field)
            field.keyDown(with: key(kVK_Return))
            XCTAssertEqual(view.drawnShapes.count, 0, "\(text.debugDescription) left a layer on the screen")
            let layers = try handed()
            XCTAssertTrue(layers.isEmpty, "\(text.debugDescription) is in the file as \(layers.count) layer(s)")
        }
    }

    func testAPasteOfAGraphemeOfTwentyThousandMarksDoesNotFreezeTheField() throws {
        let (_, _, field) = try typing()
        let started = Date()
        type("e" + String(repeating: "\u{301}", count: 20_000), in: field)
        let spent = Date().timeIntervalSince(started)
        XCTAssertLessThan(spent, 3, "one grapheme of 20 000 marks took \(spent) s in the field")
        XCTAssertLessThanOrEqual(field.string.unicodeScalars.count, 1024, "the field took \(field.string.unicodeScalars.count) scalars under a bound of 256 letters")
    }
}
