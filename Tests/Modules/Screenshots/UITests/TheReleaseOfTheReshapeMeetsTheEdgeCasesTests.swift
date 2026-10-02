import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The release of a reshape at the edge:** an object touching the area, a lost release, a tiny area grown mid-drag, the arrow with an object selected. And two
/// ends of a stranded selection: an arrow that carries an object wholly outside, and a lost release met by a press on
/// the palette; and an area too small for a dot reporting none drawn.
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
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return (local, layers)
    }

    /// One rectangle (200,200)-(300,260) drawn and selected by a click on its left edge.
    private func drawAndSelect() { OverlayRig.drawAndSelect(in: overlay, on: display) }

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

    func testALostReleaseEndedByTheNextPressOnNothingLeavesNoStrandedSelection() throws {
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

    /// The owner's rule is "an area resize" lets go of an object that is wholly outside. With an object selected the arrow moves the object, never the area.
    func testWithAnObjectSelectedTheArrowMovesTheObjectAndNeverTheArea() throws {
        let view = try build()
        drawAndSelect()
        overlay?.keyDown(key(right))
        // With an object selected the arrow moves the object, never the area: the area cannot leave it this way.
        let (local, _) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(view.drawnHandles.count, 4)
    }

    /// (a) Through the key path: pulled to x = 201 the object straddles the wall; one Shift+Right (10 px at 1x) carries it
    /// wholly outside. Total failure of the subject (the arrow never judges) prints the handle count and the frame, still at 210.
    func testAnArrowNudgeThatCarriesTheObjectWhollyOutsideTheAreaLetsGoOfIt() throws {
        let view = try build()
        drawAndSelect()
        try pull(view, to: 201)
        XCTAssertEqual(view.drawnHandles.count, 4, "the subject: it straddles the wall and is still selected")
        overlay?.keyDown(key(right, flags: [.shift]))
        let (_, layers) = try confirmed()
        XCTAssertEqual(layers.first?.frame.minX ?? 0, 210, accuracy: 0.001, "the subject: the arrow moved the object outward")
        XCTAssertTrue(view.drawnHandles.isEmpty, "a nudge left the object wholly outside the area and it stayed selected: \(view.drawnHandles.count) handles, frame \(String(describing: layers.first?.frame))")
    }

    /// (b) A lost release, then a press on the palette. The palette is found by scanning the display for a point it covers.
    func testALostReleaseEndedByTheNextPressOnThePaletteLeavesNoStrandedSelection() throws {
        let view = try build()
        drawAndSelect()
        try pull(view, to: 150, release: false)
        // Mid-reshape the overlay hides the palette; the press ends the reshape, so place it for the area as pulled (100...150).
        let paletteSize = view.paletteSize
        let chrome = EditorChrome.place(selection: CGRect(x: 100, y: 100, width: 50, height: 300), in: CGSize(width: 1000, height: 800),
                                        palette: paletteSize)
        var found: CGPoint?
        for x in stride(from: CGFloat(0), to: 1000, by: 5) {
            for y in stride(from: CGFloat(0), to: 800, by: 5) where found == nil && chrome.covers(CGPoint(x: x, y: y)) { found = CGPoint(x: x, y: y) }
        }
        let onPalette = try XCTUnwrap(found, "no point of the display is under the palette")
        overlay?.mouseDown(on: display, at: onPalette, flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(view.drawnHandles.isEmpty, "an object wholly outside the area stayed selected after a lost release and a press on the palette")
    }

    /// (c) An area two points short is drawn with no dot, so none may be reported as drawn.
    func testAnAreaTooSmallForADotReportsNoDrawnHandle() throws {
        let view = try build(area: CGRect(x: 100, y: 100, width: 40, height: 2))
        XCTAssertEqual(AreaFrame.reach(on: CGRect(x: 100, y: 100, width: 40, height: 2)) < 1, true, "the subject: the dot would be under a point")
        XCTAssertTrue(view.drawnAreaHandles.isEmpty, "nothing is drawn, yet \(view.drawnAreaHandles.count) handles are reported as drawn")
    }
}
