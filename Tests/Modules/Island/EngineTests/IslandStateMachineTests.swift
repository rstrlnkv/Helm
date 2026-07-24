import XCTest
@testable import Module_Island_Engine

final class IslandStateMachineTests: XCTestCase {
    func testHoverExpandsAndGraceCollapses() {
        var m = IslandStateMachine()
        XCTAssertEqual(m.state, .hidden)
        m.apply(.hoverEntered);            XCTAssertEqual(m.state, .expanded)
        m.apply(.hoverExited);             XCTAssertEqual(m.state, .expanded)   // grace window
        m.apply(.graceElapsed);            XCTAssertEqual(m.state, .hidden)
        m.apply(.hoverEntered); m.apply(.hoverExited); m.apply(.hoverEntered)
        m.apply(.graceElapsed);            XCTAssertEqual(m.state, .expanded)   // re-enter cancels grace
    }

    func testDragRevealsAndDropPins() {
        var m = IslandStateMachine()
        m.apply(.dragEntered);             XCTAssertEqual(m.state, .expanded)
        m.apply(.dragExited); m.apply(.graceElapsed)
        XCTAssertEqual(m.state, .hidden)
        m.apply(.dragEntered); m.apply(.dropped)
        m.apply(.dragExited); m.apply(.graceElapsed)
        XCTAssertEqual(m.state, .expanded)   // pinned for review until dismissed
        m.apply(.dismiss);                 XCTAssertEqual(m.state, .hidden)
    }

    func testTransientEventPeeksAndTTLHides() {
        var m = IslandStateMachine()
        m.apply(.event(id: "battery"));    XCTAssertEqual(m.state, .peek)
        m.apply(.eventExpired(id: "battery")); XCTAssertEqual(m.state, .hidden)
    }

    func testExpandedBeatsPeekAndFallsBackToIt() {
        var m = IslandStateMachine()
        m.apply(.hoverEntered)
        m.apply(.event(id: "battery"))
        XCTAssertEqual(m.state, .expanded)
        m.apply(.hoverExited); m.apply(.graceElapsed)
        XCTAssertEqual(m.state, .peek)     // event still alive
        m.apply(.eventExpired(id: "battery"))
        XCTAssertEqual(m.state, .hidden)
    }

    func testDismissClearsEventsToo() {
        var m = IslandStateMachine()
        m.apply(.event(id: "a")); m.apply(.event(id: "b"))
        m.apply(.dismiss)
        XCTAssertEqual(m.state, .hidden)
        m.apply(.eventExpired(id: "a"))    // late expiry of a cleared event: no-op
        XCTAssertEqual(m.state, .hidden)
    }

    /// Stale grace must not collapse a state re-opened after the timer was armed.
    func testGraceIsIgnoredWhileHoveringOrDragging() {
        var m = IslandStateMachine()
        m.apply(.hoverEntered)
        m.apply(.graceElapsed)             // spurious
        XCTAssertEqual(m.state, .expanded)
    }
}
