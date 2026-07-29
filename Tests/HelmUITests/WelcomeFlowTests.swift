import XCTest
@testable import HelmUI

/// The tour's position and what the buttons may do there. Deliberately knows
/// nothing about windows: a flow that could close itself could not be asked
/// what it would do without one.
final class WelcomeFlowTests: XCTestCase {
    func testItStartsAtTheBeginningAndCannotGoBack() {
        let flow = WelcomeFlow(stepCount: 10)
        XCTAssertEqual(flow.step, 0)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertFalse(flow.isLastStep)
    }

    func testNextAdvancesAndBackReturns() {
        var flow = WelcomeFlow(stepCount: 3)
        flow.next()
        XCTAssertEqual(flow.step, 1)
        XCTAssertTrue(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.step, 0)
        XCTAssertFalse(flow.canGoBack)
    }

    func testTheLastStepSaysSoAndNextGoesNoFurther() {
        var flow = WelcomeFlow(stepCount: 2)
        flow.next()
        XCTAssertTrue(flow.isLastStep)
        flow.next()
        XCTAssertEqual(flow.step, 1, "next() past the end must not run off the list")
    }

    func testBackAtTheStartDoesNothing() {
        var flow = WelcomeFlow(stepCount: 3)
        flow.back()
        XCTAssertEqual(flow.step, 0)
    }

    /// A tour of nothing is a window with no content and no way out but Skip.
    /// It cannot happen with the real registry, and the type answers for it
    /// anyway rather than trapping on an empty array.
    func testAnEmptyTourIsItsOwnLastStep() {
        let flow = WelcomeFlow(stepCount: 0)
        XCTAssertTrue(flow.isLastStep)
        XCTAssertFalse(flow.canGoBack)
    }
}
