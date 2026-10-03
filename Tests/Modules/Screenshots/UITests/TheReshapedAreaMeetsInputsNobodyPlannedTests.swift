import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The area handles and the arrows, fed what the task never named:** an object left outside a shrunk area,
/// an arrow while a draft, a move or Esc's question stands, a held arrow at the wall, the area walked onto a
/// display's edge at 2x by ten-pixel steps, a handle that the palette covers, and Esc mid-reshape with the drag going on.
@MainActor
final class TheReshapedAreaMeetsInputsNobodyPlannedTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var display = DisplayID(0)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func build(scale: CGFloat = 1, area: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)) throws -> OverlayView {
        let rig = try OverlayRig.overlay(scale: scale, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        display = rig.display
        return rig.view
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    private let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126, esc: UInt16 = 53

    private func confirmed() throws -> (local: CGRect, layers: [Annotation]) {
        // With Crop on, Return takes the crop and the next one is the exit.
        if overlay?.isCropping == true { overlay?.perform(.exit(.confirm)) }
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return (local, layers)
    }

    /// One rectangle (200,200)-(300,260) drawn and selected by a click on its left edge.
    private func drawAndSelect() { OverlayRig.drawAndSelect(in: overlay, on: display) }

    // MARK: An object left outside a shrunk area

    func testASelectedObjectLeftOutsideTheShrunkAreaIsLetGoOfAtTheReleaseAndStillHandedOn() throws {
        let view = try build()
        drawAndSelect()
        overlay?.perform(.crop) // over a marked picture the area's handles are offered with Crop on only
        XCTAssertEqual(view.drawnHandles.count, 4, "the subject: an object is selected")
        // The area's right edge pulled in to x = 150: the object (200...300) is wholly outside.
        // The press is on the area's handle, and the object's own are further than its reach.
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .right)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 150, y: at.y), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(view.drawnHandles.isEmpty, "the object's frame and handles are left in the dim though the area has none of it")
        // Nothing is selected now, so an arrow moves the area and leaves the object where it was.
        overlay?.keyDown(key(right))
        let (local, layers) = try confirmed()
        XCTAssertEqual(local.maxX, 151)
        XCTAssertEqual(layers.first?.frame.minX, 200, "the object was moved by the area's nudge")
    }

    func testAnObjectWhollyOutsideTheAreaAddsNothingToTheFile() throws {
        // The export is `CaptureSession.draw` over the cut: a layer beyond the cut must leave every byte alone.
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cut = try XCTUnwrap(context.makeImage())
        let outside = Annotation(tool: .rectangle, start: CGPoint(x: 400, y: 400), end: CGPoint(x: 500, y: 500), id: 1)
        let drawn = try XCTUnwrap(CaptureSession.draw([outside], over: cut, at: .zero, scale: 1, display: cut))
        let before = try XCTUnwrap(cut.dataProvider?.data) as Data
        let after = try XCTUnwrap(drawn.dataProvider?.data) as Data
        let nonZero = after.contains { $0 != 0 }
        XCTAssertFalse(nonZero, "the subject is a blank cut; ink appeared from a layer outside it")
        XCTAssertEqual(before.count, after.count)
        let inside = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50), id: 2)
        let marked = try XCTUnwrap(CaptureSession.draw([inside], over: cut, at: .zero, scale: 1, display: cut))
        XCTAssertTrue((try XCTUnwrap(marked.dataProvider?.data) as Data).contains { $0 != 0 }, "the control: a layer inside draws")
    }

    // MARK: An arrow while something else stands

    func testAnArrowDuringADraftChangesNothingAndTheDraftIsStillOneObject() throws {
        let view = try build()
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.keyDown(key(right, flags: [.shift]))
        overlay?.keyDown(key(down))
        overlay?.mouseUp(on: display)
        let (local, layers) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 400, height: 300), "an arrow moved the area under a draft")
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers.first?.frame, CGRect(x: 200, y: 200, width: 100, height: 60))
        XCTAssertTrue(view.drawnAreaHandles.isEmpty, "the handles of a marked picture are Crop's")
    }

    func testAnArrowDuringAMoveOfAnObjectChangesNothingAndTheMoveIsOneStep() throws {
        let view = try build()
        drawAndSelect()
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 220, y: 230), flags: [])
        overlay?.keyDown(key(right, flags: [.shift]))
        overlay?.keyDown(key(up, flags: [.shift]))
        XCTAssertEqual(view.drawnHandles.first, CGPoint(x: 220, y: 200), "an arrow moved the object that is being dragged")
        overlay?.mouseUp(on: display)
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnHandles.first, CGPoint(x: 200, y: 200), "the move and the arrows were more than one step")
        XCTAssertEqual(try confirmed().local, CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    func testAnArrowWithdrawsEscsQuestionAndTheNextEscAsksAgainInsteadOfClosing() throws {
        for withObjectSelected in [false, true] {
            results = []
            overlay?.close()
            let view = try build()
            drawAndSelect()
            overlay?.keyDown(key(esc)) // lets go of the object
            if withObjectSelected { overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: []); overlay?.mouseUp(on: display) }
            overlay?.keyDown(key(esc)) // with a selection it deselects, without it asks
            if withObjectSelected { overlay?.keyDown(key(esc)) }
            XCTAssertEqual(view.visiblePlates.count, 1, "the subject: the question stands (selected: \(withObjectSelected))")
            if withObjectSelected { overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: []); overlay?.mouseUp(on: display) }
            overlay?.keyDown(key(right))
            XCTAssertTrue(view.visiblePlates.isEmpty, "an arrow left the question up (selected: \(withObjectSelected))")
            overlay?.keyDown(key(esc))
            XCTAssertTrue(results.isEmpty, "the Esc after an arrow closed the overlay: the question was not withdrawn (selected: \(withObjectSelected))")
        }
    }

    func testACommandArrowWithdrawsTheQuestionAndMovesNothing() throws {
        let view = try build()
        drawAndSelect()
        overlay?.keyDown(key(esc))
        overlay?.keyDown(key(esc))
        XCTAssertEqual(view.visiblePlates.count, 1, "the subject: the question stands")
        overlay?.keyDown(key(right, flags: [.command]))
        XCTAssertTrue(view.visiblePlates.isEmpty)
        XCTAssertEqual(try confirmed().local, CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    // MARK: Walls

    func testAHeldArrowAtTheWallIsNoStepAndLeavesTheObjectsHistoryAlone() throws {
        let view = try build()
        drawAndSelect()
        // The object is against the area's right wall after a run, a second run there moves nothing.
        for _ in 0..<40 { overlay?.keyDown(key(right, flags: [.shift])) }
        XCTAssertEqual(view.drawnHandles.map(\.x).max(), 500, "the subject: the object is at the wall")
        overlay?.keyDown(key(left)) // another key resumes the run: still the same step
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnHandles.first?.x, 200, "the run was more than one step")
        XCTAssertEqual(view.drawnShapes.count, 1, "the undo went past the run into the drawing")
    }

    func testTheAreaWalkedOntoTheEdgeOfA2xDisplayByTenPixelStepsEndsOnTheEdgeWithItsSize() throws {
        _ = try build(scale: 2, area: CGRect(x: 102.5, y: 101, width: 400, height: 300))
        for _ in 0..<200 {
            overlay?.keyDown(key(right, flags: [.shift]))
            overlay?.keyDown(key(down, flags: [.shift]))
        }
        let (local, _) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 600, y: 500, width: 400, height: 300), "the area is not flush with the corner at its own size")
        let pixels = Selection.pixelSize(of: local, scale: 2)
        XCTAssertEqual(pixels.width, 800)
        XCTAssertEqual(pixels.height, 600)
        // And back out to the other wall with the same step, from a half-point origin.
        results = []
        overlay?.close()
        _ = try build(scale: 2, area: CGRect(x: 597.5, y: 499, width: 400, height: 300))
        for _ in 0..<200 {
            overlay?.keyDown(key(left, flags: [.shift]))
            overlay?.keyDown(key(up, flags: [.shift]))
        }
        XCTAssertEqual(try confirmed().local, CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    // MARK: A handle under the palette

    /// The palette stands 14 points from the area and a handle takes a press within 7, so on a display as tall as
    /// this one no placement puts the palette on a handle: the press order "palette first" has no input to meet.
    /// (The tool bar of the old two-bar layout did stand on handles, and this was a press on one.) This is
    /// that fact, asked over every area on a grid; a palette that comes to stand on a handle turns it red, and
    /// the press on it then needs the test it had.
    func testNoPlacementOfThePaletteStandsOnAHandleOfItsArea() throws {
        let paletteSize = try build().paletteSize
        let size = CGSize(width: 1000, height: 800)
        let edges: [CGFloat] = [0, 1, 60, 300, 640, 930, 999, 1000]
        let tops: [CGFloat] = [0, 1, 40, 390, 700, 770, 799, 800]
        var areas = 0, pressed = 0
        for x0 in edges { for x1 in edges where x1 > x0 + 8 {
            for y0 in tops { for y1 in tops where y1 > y0 + 8 {
                let area = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                let chrome = EditorChrome.place(selection: area, in: size, palette: paletteSize)
                areas += 1
                for handle in AreaFrame.handles(of: area).map(\.point) {
                    for dx in stride(from: CGFloat(-6), through: 6, by: 2) {
                        for dy in stride(from: CGFloat(-6), through: 6, by: 2) {
                            let at = CGPoint(x: handle.x + dx, y: handle.y + dy)
                            guard AreaFrame.handle(of: area, at: at) != nil else { continue }
                            pressed += 1
                            XCTAssertFalse(chrome.covers(at), "the palette \(chrome.palette) stands on a handle press \(at) of \(area)")
                        }
                    }
                }
            } }
        } }
        XCTAssertGreaterThan(areas, 300, "the sweep did not run: \(areas) areas")
        XCTAssertGreaterThan(pressed, 10_000, "the sweep asked of \(pressed) presses")
    }

    // MARK: Esc mid-reshape, the drag goes on

    func testTheDragThatGoesOnAfterEscMidReshapeDoesNothingToTheAreaOrTheLayers() throws {
        let view = try build()
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .bottomRight)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x + 50, y: at.y + 50), flags: [])
        overlay?.keyDown(key(esc))
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x + 90, y: at.y + 90), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x - 90, y: at.y - 90), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(results.isEmpty)
        let (local, layers) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 400, height: 300), "the drag after Esc went on reshaping")
        XCTAssertTrue(layers.isEmpty)
    }
}
