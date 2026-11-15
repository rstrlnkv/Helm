import XCTest
@testable import Module_Homebrew_Engine

/// What a tick continues into is a blocking password dialog, so the real ticker
/// must not run it on the thread that draws.
final class TheTickerNeverTicksOnMainTests: XCTestCase {
    func testTheRealTickerRunsItsBlockOffMain() {
        let ran = expectation(description: "tick")
        let token = DispatchWaitTicker().schedule(after: 0.02) {
            XCTAssertEqual(Thread.isMainThread, false)
            ran.fulfill()
        }
        wait(for: [ran], timeout: 2)
        withExtendedLifetime(token) {}
    }
}
