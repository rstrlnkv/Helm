import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A folder opens at the middle of the window, and the pointer that held a tile on its folder is somewhere else. Closing a card
/// because the pointer is outside it would shut it the moment it opened and open it again: the pointer must have been inside
/// first, and then it must stay out for the delay.
@MainActor final class AFolderThatOpenedUnderALiftIsNotClosedByThePointerNotBeingInItTests: XCTestCase {
    func testTheCardStaysOpenWhileThePointerHasNotBeenInItAndClosesAfterItHasBeenAndLeft() {
        let id = UUID()
        let r = LiftRig(self, apps: ["a", "b", "c", "d"], layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: id, name: "F", apps: ["b", "c"])), .app("d")]))
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        r.state.tick(at: 1.71)
        XCTAssertEqual(r.state.openFolder, id, "the control: it did open")
        for step in 1...20 {
            r.state.pointerMoved(r.core(1), time: 2 + Double(step) * 0.25)
            r.state.tick(at: 2 + Double(step) * 0.25 + 0.2)
        }
        XCTAssertEqual(r.state.openFolder, id, "five seconds with the pointer where it was: still open")
        let card = LaunchpadSurface.Card(geometry: r.g, count: 3)
        r.state.pointerMoved(card.center(ofSlot: 1), time: 10)
        r.state.pointerMoved(r.core(1), time: 11)
        r.state.tick(at: 11.2)
        XCTAssertEqual(r.state.openFolder, id, "inside, then out: not yet")
        r.state.tick(at: 11.26)
        XCTAssertNil(r.state.openFolder, "out for the delay: closed")
    }
}
