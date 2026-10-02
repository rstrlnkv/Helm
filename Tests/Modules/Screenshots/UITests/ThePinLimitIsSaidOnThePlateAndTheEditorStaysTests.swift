import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **At the limit of open pins the editor does not exit; its plate says why.** The toast lies below the overlay and
/// cannot be seen, so the sentence goes on the plate the Esc question uses. Pin gets no key, so nothing else
/// reaches it; and its cell and its words are one of each in every language.
///
/// Total failure of the subject prints: an editor that closes on a ninth pin and loses the picture (a result
/// arrives), a refusal nobody sees (the plate is empty), a plate that never goes away (it is still there after
/// the next action), a limit that stays after the room is back, and a cell or a sentence that is missing,
/// empty, numeric, or the same as another control's in some language.
///
/// Assumed (the plan's): `CaptureOverlay.init(freeze:mode:preselection:store:pinRoom:onFinish:)` with
/// `pinRoom: () -> Bool = { true }`, `EditorExit.pin`, `ScStr.pinLimit`; mine: `ScStr.pin` for the cell and
/// `ScStr.pinnedScreenshot` for the accessibility label.
@MainActor
final class ThePinLimitIsSaidOnThePlateAndTheEditorStaysTests: XCTestCase {

    private var results: [OverlayResult] = []
    private var room = false
    private var rigged: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)?

    override func tearDown() {
        rigged?.overlay.close()
        rigged = nil
        super.tearDown()
    }

    private func build() throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let built = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300),
                                           pinRoom: { [weak self] in self?.room ?? false }) { [weak self] in self?.results.append($0) }
        rigged = built
        return built
    }

    func testAtTheLimitThePinExitDoesNotLeaveAndThePlateSaysSo() throws {
        let (overlay, _, view) = try build()
        XCTAssertTrue(view.visiblePlates.isEmpty, "the control: no plate before the press")
        overlay.perform(.exit(.pin))
        XCTAssertTrue(results.isEmpty, "the editor closed with no room for the pin: the picture is lost")
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "the limit was not said on the plate")
    }

    /// The next action withdraws the sentence, and a press with room goes through as a pin.
    func testTheNextActionWithdrawsThePlateAndRoomLetsThePinThrough() throws {
        let (overlay, display, view) = try build()
        overlay.perform(.exit(.pin))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "the control: the refusal came first")
        overlay.perform(.tool(.rectangle))
        XCTAssertTrue(view.visiblePlates.isEmpty, "the limit sentence stayed after the next action")
        overlay.perform(.exit(.pin))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit])
        // A trackpad click nearly always carries a micro-move: the refusal survives a pointer move, as the Esc
        // question's plate does, and goes with the next action.
        overlay.mouseMoved(on: display, at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "the limit sentence was withdrawn by a pointer move")
        overlay.perform(.tool(.rectangle))
        XCTAssertTrue(view.visiblePlates.isEmpty, "the limit sentence stayed after the next action")
        overlay.perform(.exit(.pin))
        room = true
        overlay.perform(.exit(.pin))
        guard case .edited(_, _, _, let exit)? = results.first, results.count == 1 else { return XCTFail("\(results)") }
        XCTAssertEqual(exit, .pin)
    }

    /// D2: one point of pointer travel after the refusal does not take the sentence away.
    func testAOnePointMoveOfThePointerDoesNotWithdrawTheRefusal() throws {
        let (overlay, display, view) = try build()
        overlay.mouseMoved(on: display, at: CGPoint(x: 300, y: 300))
        overlay.perform(.exit(.pin))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "the control: the refusal came first")
        overlay.mouseMoved(on: display, at: CGPoint(x: 301, y: 300))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "a one-point move withdrew the refusal")
        overlay.mouseMoved(on: display, at: CGPoint(x: 301, y: 301))
        XCTAssertEqual(view.visiblePlates.compactMap(\.string), [ScStr.pinLimit], "a second one-point move withdrew the refusal")
    }

    /// D1: the pointer is on the Pin cell when the refusal comes, and the plate must not lie under the glass
    /// palette it was pressed on: its frame misses the palette's frame and stays inside the display.
    func testTheRefusalPlateDoesNotLieUnderThePalette() throws {
        let (overlay, display, view) = try build()
        let palette = try XCTUnwrap(overlay.chrome(on: display)?.palette, "the control: no palette")
        let flipped = CGRect(x: palette.minX, y: view.bounds.height - palette.maxY, width: palette.width, height: palette.height)
        for fraction: CGFloat in [0.25, 0.5, 0.75, 0.9] {
            overlay.perform(.tool(.rectangle))
            overlay.perform(.tool(.rectangle))
            overlay.mouseMoved(on: display, at: CGPoint(x: palette.minX + palette.width * fraction, y: palette.midY))
            overlay.perform(.exit(.pin))
            let plate = try XCTUnwrap(view.visiblePlates.first { $0.string == ScStr.pinLimit }, "the control: the refusal was not shown at \(fraction)")
            XCTAssertFalse(plate.frame.intersects(flipped), "pointer at \(fraction) of the palette: the plate \(plate.frame) lies on the palette \(flipped)")
            XCTAssertTrue(view.bounds.contains(plate.frame), "the plate \(plate.frame) left the display \(view.bounds)")
        }
    }

    /// Only the pin exit asks for room: copy and save leave at the limit as ever.
    func testTheOtherExitsDoNotAskForRoom() throws {
        for exit in [EditorExit.copy, .save, .confirm] {
            results = []
            let (overlay, _, _) = try build()
            overlay.perform(.exit(exit))
            guard case .edited(_, _, _, let how)? = results.first, results.count == 1 else { return XCTFail("\(exit): \(results)") }
            XCTAssertEqual(how, exit)
        }
    }

    // MARK: Words and the cell

    func testTheCellAndTheSentenceExistInEveryLanguageAndAreNeitherEmptyNorNumeric() {
        AppLanguage.each { language in
            let words = [ScStr.pin, ScStr.pinLimit, ScStr.pinnedScreenshot]
            XCTAssertFalse(words.contains(where: \.isEmpty), "\(language): \(words)")
            XCTAssertFalse(ScStr.pinLimit.contains(where: \.isNumber), "\(language): the limit sentence carries a number")
            let others = [ScStr.undo, ScStr.redo, ScStr.done, ScStr.closeEditor, HelmA11y.moreActions, ScStr.confirmClose]
            XCTAssertFalse(others.contains(ScStr.pin), "\(language): the Pin cell shares a name with another control on the palette")
            XCTAssertNotEqual(ScStr.pinLimit, ScStr.confirmClose, "\(language)")
        }
    }

    /// The palette builds its pin entry only behind a switch; **every** way the palette could say or send Pin (the exit, the
    /// word, the pin symbol) lies inside the braces of an `if PinEntry.isOffered`. Not "the switch is named
    /// somewhere in the file": a Pin cell outside the braces beside an unrelated mention of the switch is
    /// the defect, and a mention anywhere would have passed it.
    func testThePaletteSendsThePinExitOnlyBehindTheSwitch() throws {
        let code = Array(SwiftSource.uncommented(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift")))
        let text = String(code)
        // The braces of every `if PinEntry.isOffered {`, as offset ranges.
        var guarded: [Range<Int>] = []
        var search = text.startIndex..<text.endIndex
        while let found = text.range(of: "if PinEntry.isOffered", range: search) {
            let start = text.distance(from: text.startIndex, to: found.upperBound)
            if let open = code[start...].firstIndex(of: "{") {
                var depth = 0, close = open
                for i in open..<code.count {
                    if code[i] == "{" { depth += 1 } else if code[i] == "}" { depth -= 1; if depth == 0 { close = i; break } }
                }
                guarded.append(open..<close)
            }
            search = found.upperBound..<text.endIndex
        }
        var seen = 0
        for needle in [".exit(.pin)", "ScStr.pin", "\"pin\""] {
            var from = text.startIndex..<text.endIndex
            while let hit = text.range(of: needle, range: from) {
                seen += 1
                let at = text.distance(from: text.startIndex, to: hit.lowerBound)
                XCTAssertTrue(guarded.contains { $0.contains(at) }, "the palette says Pin with \(needle) outside an `if PinEntry.isOffered`")
                from = hit.upperBound..<text.endIndex
            }
        }
        // The Pin cell must exist, and every needle of it is inside the braces.
        XCTAssertGreaterThan(seen, 0, "the palette has no Pin cell: `true` would bring nothing back")
        XCTAssertFalse(guarded.isEmpty, "the palette says Pin \(seen) time(s) and has no switch at all")
        XCTAssertGreaterThan(code.count, 1000, "the scan read an empty palette source")
    }

    /// Pin has no key (a pin is a cell only): no key of the table produces it.
    func testNoKeyMeansPin() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorKeys.swift"))
        XCTAssertTrue(source.contains("case pin"), "EditorExit has no pin case")
        XCTAssertFalse(source.contains(".exit(.pin)"), "a key is mapped to the pin exit")
    }
}
