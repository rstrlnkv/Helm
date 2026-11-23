import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Pass 3's page froze the run loop: tile frames measured by the views fed a hover state, the hover moved the tiles, and every
/// move of the pointer set the layout going again. The lift of this window is fed by the pointer's own events and may publish
/// only when the gap or the target changes: a hundred moves inside one cell publish **nothing**, and a lift ends in one of a
/// release or a cancel, Esc being a cancel and never the window's close.
@MainActor final class ALiftEndsInOneOutcomeAndTheGapDoesNotFlickerTests: XCTestCase {
    private func rig() -> LiftRig { LiftRig(self, apps: ["a", "b", "c", "d", "e", "f"]) }

    func testAHundredMovesInsideOneCellPublishNothingAndTheGapMovingPublishes() {
        let r = rig()
        r.lift(0)
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "b", "c", "d", "e", "f"], "the lift happened: the tile left a gap")
        r.countChanges()
        for i in 0..<100 {
            r.state.pointerMoved(CGPoint(x: r.core(0).x + CGFloat(i % 7), y: r.core(0).y + CGFloat(i % 5)), time: 1 + Double(i) * 0.01)
        }
        XCTAssertEqual(r.changes, 0, "over the gap itself nothing changes, and the pointer's place is not the state's")
        r.state.pointerMoved(r.margin(3), time: 3)
        r.state.tick(at: 3.2)
        XCTAssertEqual(r.ids(), ["b", "c", "d", LaunchpadEntry.gapID, "e", "f"], "the control: the same path does publish when the gap moves")
        XCTAssertGreaterThan(r.changes, 0)
    }

    func testTheMachineSaysNothingWhateverTheTimeWhileThePointerIsOverTheGapItself() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
        let surface = LaunchpadSurface(geometry: g, page: 0, pageCounts: [10], gap: 3)
        var m = LaunchpadLift()
        var plain = surface
        plain.gap = nil
        _ = m.feed(.down, at: g.center(ofSlot: 3), surface: plain)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: g.center(ofSlot: 3).x + 8, y: g.center(ofSlot: 3).y), surface: plain, time: 0.01),
                       .lift(address: 3), "the lift happened")
        let c = g.center(ofSlot: 3)
        for i in 0..<100 {
            let at = i % 2 == 0 ? c : CGPoint(x: c.x + g.cellWidth * 0.42, y: c.y)
            XCTAssertEqual(m.feed(.moved, at: at, surface: surface, time: 1 + Double(i) * 0.03), .none, "move \(i)")
        }
        XCTAssertNil(m.wake, "nothing to wait for")
        XCTAssertEqual(m.feed(.moved, at: g.center(ofSlot: 6), surface: surface, time: 5), .none, "the control: another tile is waited on")
        XCTAssertNotNil(m.wake)
    }

    func testTheGapDoesNotMoveBackAndForthWhenThePointerSitsWhereItsTileMovedFrom() {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.tick(at: 1.2)
        r.countChanges()
        for i in 0..<50 { r.state.pointerMoved(r.margin(3), time: 2 + Double(i) * 0.01); r.state.tick(at: 2 + Double(i) * 0.01) }
        XCTAssertEqual(r.changes, 0)
        XCTAssertEqual(r.ids(), ["b", "c", "d", LaunchpadEntry.gapID, "e", "f"])
    }

    func testEscDuringALiftEndsItAndDoesNotCloseTheWindow() {
        let r = rig()
        r.lift(1)
        XCTAssertNotNil(r.state.lift)
        r.state.escape()
        XCTAssertEqual(r.closes, 0, "Esc ended the lift, not the window")
        XCTAssertNil(r.state.lift)
        XCTAssertEqual(r.ids(), ["a", "b", "c", "d", "e", "f"], "the tile is back")
        XCTAssertTrue(r.placed.isEmpty)
        r.state.pointerUp(r.core(1), time: 5)
        XCTAssertTrue(r.placed.isEmpty, "the let-go after the cancel is nothing")
        r.state.escape()
        XCTAssertEqual(r.closes, 1, "and the next Esc is the window's")
    }

    func testALiftThatIsLetGoWritesOneEditAndASecondLetGoWritesNone() async {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.tick(at: 1.2)
        r.state.pointerUp(r.margin(3), time: 1.3)
        r.state.pointerUp(r.margin(3), time: 1.31)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        await waitUntil("the page took the answer") { r.ids() == ["b", "c", "d", "a", "e", "f"] }
        XCTAssertEqual(r.placed, [.place("a", relativeTo: "d", after: true)])
        XCTAssertNil(r.state.lift)
    }
}
