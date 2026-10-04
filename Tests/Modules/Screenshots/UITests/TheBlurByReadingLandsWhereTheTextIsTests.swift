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

/// **Blur Emails and Phone Numbers puts each box where the text is, in the editor on an area of the screen and in the editor on a
/// picture.** The overlay is handed a reading (lines and the `Source` the reader's picture came from) and has to put the boxes
/// `RecognizedBoxes.place` gives for that source into the layers, in the display's own points. Before this check nothing
/// asked where a box landed, only that one did, so a box shifted by a few points on the Edit path alone (the picture stands
/// at an offset on its display, the area editor's area at another) passed every test.
///
/// Total failure of the subject prints: no layer at all (the control, which fails first), or a layer whose frame is not the
/// engine's placement of the find.
///
/// Synchronous on purpose: the answer arrives on a task of the overlay's, awaited by spinning the run loop to a deadline, so every
/// assertion runs in one frame of the test and none after a suspension.
@MainActor
final class TheBlurByReadingLandsWhereTheTextIsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppLanguage.override = .en
    }

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// One email, in the upper middle of whatever was read.
    private let line: RecognizedLine = {
        let box = CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.08)
        return RecognizedLine(string: "me@example.com", box: box, matches: [PrivateMatch(kind: .emailAddress, box: box)])
    }()

    /// What the session answers for a read of `rect` on a frame at 1×: the lines and where that picture lies in the frame's pixels.
    private func tools(source seen: @escaping (RecognizedBoxes.Source) -> Void = { _ in }) -> EditorTextTools {
        let line = self.line
        return EditorTextTools(read: { _, rect in
            let source = RecognizedBoxes.Source(pixels: rect, scale: 1)
            seen(source)
            return .read([line], source)
        }, copy: { _ in .copied })
    }

    private func awaitLayers(_ overlay: CaptureOverlay) {
        let deadline = Date().addingTimeInterval(10)
        while overlay.editedLayers.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func expected(in source: RecognizedBoxes.Source) throws -> CGRect {
        try XCTUnwrap(RecognizedBoxes.place(line.matches[0].box, in: source), "the engine placed nothing").rect
    }

    func testTheBoxLandsWhereTheEngineSaysOnAnAreaOfTheScreen() throws {
        var source: RecognizedBoxes.Source?
        let rig = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300), textTools: tools { source = $0 }) { _ in }
        defer { rig.overlay.close() }
        rig.overlay.perform(.blurPersonalText)
        awaitLayers(rig.overlay)
        let layers = rig.overlay.editedLayers
        XCTAssertEqual(layers.count, 1, "the control: the reading made one blur")
        let seen = try XCTUnwrap(source, "the reader was never asked")
        XCTAssertEqual(layers.first?.frame.minX ?? .nan, try expected(in: seen).minX, accuracy: 0.5, "the box is not where the engine placed it")
        XCTAssertEqual(layers.first?.frame.minY ?? .nan, try expected(in: seen).minY, accuracy: 0.5)
        XCTAssertEqual(layers.first?.frame.width ?? .nan, try expected(in: seen).width, accuracy: 0.5)
        XCTAssertEqual(layers.first?.frame.height ?? .nan, try expected(in: seen).height, accuracy: 0.5)
    }

    func testTheBoxLandsWhereTheEngineSaysOnThePictureBeingEdited() throws {
        let frames = try OverlayRig.frames(scale: 1)
        let shown = try XCTUnwrap(PictureOnScreen.place(try ShotToastRig.picture(width: 400, height: 300),
                                                        over: Freeze(displays: frames.map { .image($0) }, windows: []),
                                                        on: try XCTUnwrap(frames.first).id))
        XCTAssertNotEqual(shown.rect.origin, .zero, "the control: the picture stands at an offset on its display, or this proves nothing")
        var source: RecognizedBoxes.Source?
        let overlay = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil,
                                     textTools: tools { source = $0 }) { _ in }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }
        overlay.perform(.blurPersonalText)
        awaitLayers(overlay)
        let layers = overlay.editedLayers
        XCTAssertEqual(layers.count, 1, "the control: the reading made one blur")
        let seen = try XCTUnwrap(source, "the reader was never asked")
        XCTAssertEqual(seen.pixels, shown.rect, "the control: the reading is of the picture's own rectangle")
        let want = try expected(in: seen)
        XCTAssertTrue(shown.rect.contains(want), "the control: the engine's own box \(want) is inside the picture \(shown.rect)")
        XCTAssertEqual(layers.first?.frame.minX ?? .nan, want.minX, accuracy: 0.5, "the box is not where the engine placed it")
        XCTAssertEqual(layers.first?.frame.minY ?? .nan, want.minY, accuracy: 0.5)
        XCTAssertEqual(layers.first?.frame.width ?? .nan, want.width, accuracy: 0.5)
        XCTAssertEqual(layers.first?.frame.height ?? .nan, want.height, accuracy: 0.5)
    }
}
