import AppKit
import CoreGraphics
import Foundation
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A held arrow key stops when a nudge lets go of the object, and the area stays where it is.** A nudge
/// that carries the selected object wholly outside the area lets go of it (`nudgeSelected`,
/// `releaseIfOutside`). The key is still down, and each repeat the system sends is one more arrow
/// press; with nothing selected any more, a press moves the *area* (`CaptureOverlay.perform`), so
/// the held key went on, past the release, dragging the whole selection across the screen. The repeat
/// is seen only by the overlay (`NSEvent.isARepeat`), so this goes in the way the keys do. A new press
/// of the key, not a repeat, is a new input and moves the area as it always did.
@MainActor
final class AHeldArrowStopsAtTheReleaseTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var display = DisplayID(0)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let left: UInt16 = 123

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: repeating, keyCode: code)!
    }

    private func confirmedArea() throws -> CGRect {
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, let local, _, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return local
    }

    /// An object (200,200)-(300,260) selected, then the area's left edge pulled to x = 250, which cuts the object
    /// in two and leaves it selected: ten pixels to the left at a time carries it wholly out in a handful of presses.
    private func straddlingObject() throws -> OverlayView {
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        display = rig.display
        OverlayRig.drawAndSelect(in: rig.overlay, on: rig.display)
        rig.overlay.perform(.crop) // over a marked picture the area's handles are offered with Crop on only
        let handle = try XCTUnwrap(rig.view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .left)!])
        rig.overlay.mouseDown(on: rig.display, at: handle, flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: handle.x + 150, y: handle.y), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        rig.overlay.perform(.exit(.confirm)) // Return takes the crop, and the arrows are the editor's again
        XCTAssertEqual(rig.view.drawnHandles.count, 4, "the subject: the object straddles the wall and is still selected")
        return rig.view
    }

    func testTheRepeatsOfAHeldArrowAfterTheReleaseMoveNothing() throws {
        let view = try straddlingObject()
        overlay?.keyDown(key(left, flags: [.shift]))
        var presses = 1
        while !view.drawnHandles.isEmpty, presses < 40 {
            overlay?.keyDown(key(left, flags: [.shift], repeating: true))
            presses += 1
        }
        XCTAssertTrue(view.drawnHandles.isEmpty, "the subject: the nudge let go of the object after \(presses) presses")
        for _ in 0..<30 { overlay?.keyDown(key(left, flags: [.shift], repeating: true)) }
        XCTAssertEqual(try confirmedArea(), CGRect(x: 250, y: 100, width: 250, height: 300),
                       "the held key went on after the release and moved the area")
    }

    func testAFreshPressAfterTheReleaseIsANewInputAndMovesTheArea() throws {
        let view = try straddlingObject()
        overlay?.keyDown(key(left, flags: [.shift]))
        for _ in 0..<40 where !view.drawnHandles.isEmpty { overlay?.keyDown(key(left, flags: [.shift], repeating: true)) }
        XCTAssertTrue(view.drawnHandles.isEmpty, "the subject: the nudge let go of the object")
        overlay?.keyDown(key(left, flags: [.shift], repeating: true)) // a repeat past the release: nothing
        overlay?.keyDown(key(left, flags: [.shift]))                  // a new press: the area, by ten
        XCTAssertEqual(try confirmedArea(), CGRect(x: 240, y: 100, width: 250, height: 300),
                       "the key pressed again after the release did not move the area by one step")
    }

    /// The press after the release is held in its turn: its repeats are the new run and move the area, which a flag
    /// that only a press's own step ignored, and never cleared, would turn dead on the second repeat.
    func testTheRepeatsOfAKeyPressedAgainAfterTheReleaseMoveTheArea() throws {
        let view = try straddlingObject()
        overlay?.keyDown(key(left, flags: [.shift]))
        for _ in 0..<40 where !view.drawnHandles.isEmpty { overlay?.keyDown(key(left, flags: [.shift], repeating: true)) }
        XCTAssertTrue(view.drawnHandles.isEmpty, "the subject: the nudge let go of the object")
        overlay?.keyDown(key(left, flags: [.shift]))                  // a new press: the area, by ten
        for _ in 0..<3 { overlay?.keyDown(key(left, flags: [.shift], repeating: true)) } // held: three more
        XCTAssertEqual(try confirmedArea(), CGRect(x: 210, y: 100, width: 250, height: 300),
                       "the repeats of a key pressed again after the release were swallowed by the old release")
    }
}
