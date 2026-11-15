import Foundation
import XCTest
@testable import HelmRuntime

/// The token is the cancel: a block whose token is released before the
/// deadline never runs, and a held one runs on the queue it was given.
final class DelayedWorkTests: XCTestCase {

    func testAReleasedTokenNeverRuns() {
        let queue = DispatchQueue(label: "DelayedWorkTests.released")
        let ran = expectation(description: "released block ran")
        ran.isInverted = true
        var token: AnyObject? = DelayedWork.schedule(on: queue, after: 0.05) { ran.fulfill() }
        XCTAssertNotNil(token)
        token = nil
        wait(for: [ran], timeout: 0.3)
    }

    func testAHeldTokenRunsOnTheGivenQueue() {
        let key = DispatchSpecificKey<Bool>()
        let queue = DispatchQueue(label: "DelayedWorkTests.held")
        queue.setSpecific(key: key, value: true)
        let ran = expectation(description: "held block ran")
        let token = DelayedWork.schedule(on: queue, after: 0.02) {
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), true)
            ran.fulfill()
        }
        wait(for: [ran], timeout: 2)
        withExtendedLifetime(token) {}
    }
}
