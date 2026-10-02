import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The release of a reshape at the edge:** an object touching the area, a lost release, a tiny area grown mid-drag, a nudge off an object. Was: an object left outside a shrunk area,
/// an arrow while a draft, a move or Esc's question stands, a held arrow at the wall, the area walked onto a
/// display's edge at 2x by ten-pixel steps, a handle that a bar covers, and Esc mid-reshape with the drag going on.
@MainActor
final class TheReleaseOfTheReshapeMeetsTheEdgeCasesTests: XCTestCase {
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
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(1000 * scale), height: Int(800 * scale), bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number), frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: scale, image: try XCTUnwrap(context.makeImage())))
        }
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        display = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: display, at: area.origin, flags: [])
        built.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: display)
        return try XCTUnwrap(built.view(for: display))
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    private let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126, esc: UInt16 = 53

    private func confirmed() throws -> (local: CGRect, layers: [Annotation]) {
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return (local, layers)
    }

    /// One rectangle (200,200)-(300,260) drawn and selected by a click on its left edge.
    private func drawAndSelect() {
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.mouseUp(on: display)
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.mouseUp(on: display)
    }

    private func pull(_ view: OverlayView, to x: CGFloat, release: Bool = true) throws {
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .right)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: x, y: at.y), flags: [])
        if release { overlay?.mouseUp(on: display) }
    }

    /// Object (200,200)-(300,260); area right edge pulled to exactly x = 200: the intersection is zero-width.
    func testAnObjectTouchingTheAreaEdgeExactlyStaysSelected() throws {
        let view = try build()
        drawAndSelect()
        try pull(view, to: 200)
        XCTAssertEqual(view.drawnHandles.count, 4, "touching is not outside: the zero-width intersection must keep the selection")
    }

    func testAnObjectWhoseFrameIsOnePointInsideStaysAndOnePointOutsideGoes() throws {
        var view = try build()
        drawAndSelect()
        try pull(view, to: 201)
        XCTAssertEqual(view.drawnHandles.count, 4)
        overlay?.close(); view = try build()
        drawAndSelect()
        try pull(view, to: 199)
        XCTAssertTrue(view.drawnHandles.isEmpty)
    }

    func testALostReleaseEndedByTheNextPressOnABarOrOnNothingLeavesNoStrandedSelection() throws {
        let view = try build()
        drawAndSelect()
        try pull(view, to: 150, release: false)
        // The release never comes; the next press lands on empty picture inside the area, away from everything.
        overlay?.mouseDown(on: display, at: CGPoint(x: 120, y: 400), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(view.drawnHandles.isEmpty, "an object wholly outside the area stayed selected after a lost release")
    }

    func testAnAreaGrownPastTheThresholdMidDragOffersItsMidpoints() throws {
        let view = try build(area: CGRect(x: 100, y: 100, width: 20, height: 20))
        XCTAssertEqual(view.drawnAreaHandles.count, 4)
        let at = try XCTUnwrap(AreaFrame.offered(on: CGRect(x: 100, y: 100, width: 20, height: 20)).first { $0.handle == .bottomRight }?.point)
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x + 20, y: at.y + 20), flags: [])
        XCTAssertEqual(view.drawnAreaHandles.count, 8, "grown to 40 mid-drag, the midpoints should be drawn")
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x, y: at.y), flags: [])
        XCTAssertEqual(view.drawnAreaHandles.count, 4, "shrunk back, they go")
        overlay?.mouseUp(on: display)
    }

    func testTheThresholdIsTwentySevenExactly() throws {
        XCTAssertTrue(AreaFrame.offersMidpoints(on: CGRect(x: 0, y: 0, width: 27, height: 100)))
        XCTAssertFalse(AreaFrame.offersMidpoints(on: CGRect(x: 0, y: 0, width: 26.9, height: 100)))
        XCTAssertTrue(AreaFrame.offersMidpoints(on: CGRect(x: 0, y: 0, width: 100, height: 27)))
        XCTAssertFalse(AreaFrame.offersMidpoints(on: CGRect(x: 0, y: 0, width: 100, height: 26.9)))
        XCTAssertEqual(AreaFrame.offered(on: CGRect(x: 0, y: 0, width: 27, height: 27)).count, 8)
        XCTAssertEqual(AreaFrame.offered(on: CGRect(x: 0, y: 0, width: 26.9, height: 27)).count, 4)
    }

    /// The owner's rule is "an area resize" lets go of an object that is wholly outside. A nudge moves the area too.
    func testAnArrowNudgeThatCarriesTheAreaOffTheSelectedObjectKeepsItSelectedBecauseTheArrowMovesTheObject() throws {
        let view = try build()
        drawAndSelect()
        overlay?.keyDown(key(right))
        // With an object selected the arrow moves the object, never the area: the area cannot leave it this way.
        let (local, _) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(view.drawnHandles.count, 4)
    }
}
