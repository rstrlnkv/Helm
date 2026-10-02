import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The Esc plate at the pointer, where the pointer is not ordinary.** At a screen edge
/// the plate stays inside the view as the other plates do; with no pointer it falls back
/// to the selection's corner and is still drawn; a pointer move leaves the question up.
@MainActor
final class TheEscPlateAtTheScreensEdgesTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func build() throws -> DisplayID {
        let frames = try OverlayRig.frames()
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: [])) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        return try XCTUnwrap(frames.first).id
    }

    private func key(_ code: UInt16, _ characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private func armedEditor() throws -> (DisplayID, OverlayView) {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        overlay?.mouseUp(on: id)
        overlay?.keyDown(key(0, "ф"))
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: 300, y: 250), flags: [])
        overlay?.mouseUp(on: id)
        return (id, view)
    }

    func testThePlateStaysInsideTheViewAtEveryCornerOfTheScreen() throws {
        let (id, view) = try armedEditor()
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 999, y: 0), CGPoint(x: 0, y: 799), CGPoint(x: 999, y: 799)]
        for corner in corners {
            overlay?.mouseMoved(on: id, at: corner)
            overlay?.keyDown(key(53))
            let plates = view.visiblePlates
            XCTAssertEqual(plates.count, 1, "no plate at \(corner)")
            let frame = try XCTUnwrap(plates.first).frame
            XCTAssertTrue(view.bounds.insetBy(dx: 3.5, dy: 3.5).contains(frame), "plate \(frame) left \(view.bounds) at \(corner)")
            overlay?.keyDown(key(0, "ф")) // withdraw, ready for the next corner
            XCTAssertTrue(view.visiblePlates.isEmpty)
        }
        XCTAssertTrue(results.isEmpty)
    }

    /// A scene with an edited selection, a plate and no pointer: the plate is drawn at the
    /// selection's corner, not dropped and not at the origin.
    func testWithNoPointerTheQuestionIsStillDrawnAtTheSelection() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        var scene = OverlayScene()
        scene.selection = CGRect(x: 100, y: 100, width: 400, height: 300)
        scene.editing = true
        scene.plate = "Close?"
        scene.plateAt = nil
        view.apply(scene)
        let plate = try XCTUnwrap(view.visiblePlates.first, "the question was not drawn without a pointer").frame
        XCTAssertTrue(view.bounds.contains(plate))
        // The selection's bottom-right corner is (500, 400) from the top: the plate is near it.
        XCTAssertEqual(plate.minX, 514, accuracy: 1)
        XCTAssertEqual(view.bounds.height - plate.maxY, 400, accuracy: 30, "the plate is not by the selection's foot")
    }

    /// The owner said "any other input withdraws"; a pointer move is the one input the code
    /// does not count, because the plate follows the pointer. Pinned so a change is deliberate.
    func testAPointerMoveIsNotInputThatWithdrawsTheQuestion() throws {
        let (id, view) = try armedEditor()
        overlay?.keyDown(key(53))
        for x in stride(from: 10.0, to: 900.0, by: 100.0) { overlay?.mouseMoved(on: id, at: CGPoint(x: x, y: 300)) }
        XCTAssertEqual(view.visiblePlates.count, 1)
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }
}
