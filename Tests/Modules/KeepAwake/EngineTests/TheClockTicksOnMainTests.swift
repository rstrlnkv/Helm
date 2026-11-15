import XCTest
@testable import Module_KeepAwake_Engine

/// Keep Awake's clock drives state the page draws from, so the real clock ticks on main.
final class TheClockTicksOnMainTests: XCTestCase {
    func testTheRealClockRunsItsBlockOnMain() {
        let ran = expectation(description: "tick")
        let token = DispatchClock().schedule(after: 0.02) {
            XCTAssertEqual(Thread.isMainThread, true)
            ran.fulfill()
        }
        wait(for: [ran], timeout: 2)
        withExtendedLifetime(token) {}
    }
}
