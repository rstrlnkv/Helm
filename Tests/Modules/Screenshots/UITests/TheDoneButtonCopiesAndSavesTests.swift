import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Done and Return are one meaning: `EditorExit.confirm`, "what the settings say".** The palette has no
/// Copy and no Save of its own any more (⌘C and ⌘S remain as keys), so the checkmark is the way out for
/// a person with a mouse, and a Done that sent `.save` would quietly stop copying.
///
/// Three halves, because no one of them proves it alone. A press is sent through the palette's own
/// hosting view across its whole width and the actions that came out are collected: the checkmark must be
/// among them, give `.confirm`, and nothing the palette sends may be `.copy`, `.save` or `.pin`. The overlay
/// is then asked what `.confirm` from the palette's door and Return from the keyboard come to: the same
/// result. The declaration is read last, for the one thing a press cannot say: which cell is called Done.
///
/// What total failure prints: a press that never reaches SwiftUI collects nothing, and the test fails on
/// "no press reached the palette" rather than passing on an empty set.
@MainActor
final class TheDoneButtonCopiesAndSavesTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        AppLanguage.override = nil
        super.tearDown()
    }

    /// While `PinEntry.isOffered` is false: with it true the menu's Pin item would send `.exit(.pin)`, which the palette's own presses do not reach.
    func testAPressOnTheCheckmarkSendsConfirmAndNoPressOnThePaletteSendsCopySaveOrPin() throws {
        for language in AppLanguage.allCases {
            let sent = try actionsAcrossThePalette(language: language)
            XCTAssertFalse(sent.isEmpty, "\(language): no press reached the palette, so «no Save» means nothing")
            let confirms = sent.filter { $0.action == .exit(.confirm) }
            XCTAssertFalse(confirms.isEmpty, "\(language): no press on the palette gave Done's confirm; it sent \(Set(sent.map { "\($0.action)" }))")
            for (x, action) in sent {
                if case .exit(let exit) = action {
                    XCTAssertEqual(exit, .confirm, "\(language): a press at x=\(x) sent the exit \(exit) from the palette")
                }
            }
            // Done is left of ✕ and right of the tools: the sweep reached both ends.
            let pencil = try XCTUnwrap(sent.first { $0.action == .tool(.pencil) }, "\(language): the pencil sent nothing")
            let close = try XCTUnwrap(sent.first { $0.action == .close }, "\(language): ✕ sent nothing")
            XCTAssertGreaterThan(try XCTUnwrap(confirms.first).x, pencil.x, "\(language): Done is left of the pencil")
            XCTAssertLessThan(try XCTUnwrap(confirms.last).x, close.x, "\(language): Done is right of ✕")
        }
    }

    /// A dimmed Undo or Redo is dimmed in its glyph only, so it is the cell's `.disabled` and not its look that
    /// keeps the press from sending: with nothing to undo the sweep meets no `.undo` and no `.redo`, and with
    /// something to undo it meets both, so the empty answer is not a sweep that missed them.
    func testADimmedUndoAndRedoSendNothingAndLitOnesSendTheirAction() throws {
        for language in AppLanguage.allCases {
            let dim = try actionsAcrossThePalette(language: language).map(\.action)
            XCTAssertFalse(dim.isEmpty, "\(language): no press reached the palette")
            XCTAssertFalse(dim.contains(.undo), "\(language): a dimmed Undo sent .undo")
            XCTAssertFalse(dim.contains(.redo), "\(language): a dimmed Redo sent .redo")
            let lit = try actionsAcrossThePalette(language: language, canUndoAndRedo: true).map(\.action)
            XCTAssertTrue(lit.contains(.undo), "\(language): a lit Undo sent nothing")
            XCTAssertTrue(lit.contains(.redo), "\(language): a lit Redo sent nothing")
        }
    }

    private func build() throws -> CaptureOverlay {
        let rig = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300)) { [weak self] in
            self?.results.append($0)
        }
        overlay = rig.overlay
        return rig.overlay
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testTheCheckmarksActionAndReturnComeToTheSameResultThroughTheOverlay() throws {
        // The palette's own door: the closure the overlay hands the model.
        try build().bars.perform(.exit(.confirm))
        let byCheckmark = try XCTUnwrap(results.last, "the checkmark's action ended nothing")
        results = []
        overlay?.close()
        try build().keyDown(key(36))
        let byReturn = try XCTUnwrap(results.last, "Return ended nothing")
        guard case .edited(let d1, let r1, let l1, let e1) = byCheckmark, case .edited(let d2, let r2, let l2, let e2) = byReturn else {
            return XCTFail("not edited areas: \(byCheckmark) / \(byReturn)")
        }
        XCTAssertEqual(e1, .confirm)
        XCTAssertEqual(e2, .confirm)
        XCTAssertEqual(d1, d2)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(l1, l2)
        // The keypad's Enter is Return.
        XCTAssertEqual(EditorKeys.action(keyCode: 36, flags: []), .exit(.confirm))
        XCTAssertEqual(EditorKeys.action(keyCode: 76, flags: []), .exit(.confirm))
    }

    /// The declaration: the cell named `ScStr.done` sends `.exit(.confirm)` and the palette sends no Copy or Save exit; the Pin exit it may send only behind the switch, which `ThePinLimitIsSaidOnThePlateAndTheEditorStaysTests` holds.
    func testTheCellNamedDoneIsDeclaredToSendConfirmAndNoCopyOrSaveIsDeclaredOnThePalette() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        let done = try XCTUnwrap(source.range(of: "ScStr.done"), "no cell is named Done")
        let line = String(source[done.lowerBound...].prefix { $0 != "\n" })
        XCTAssertTrue(line.contains("model.perform(.exit(.confirm))"), "the Done cell does not send confirm: \(line)")
        for other in [".exit(.copy)", ".exit(.save)"] {
            XCTAssertFalse(source.contains(other), "the palette sends \(other)")
        }
    }
}
