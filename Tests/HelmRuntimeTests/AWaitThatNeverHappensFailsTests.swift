// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest

/// **A wait that never ends is a hung suite, and one that ends quietly is a lie.**
///
/// `waitUntil(_:within:)` stops on a wall-clock deadline and fails naming what
/// never happened. The failing half is expected here, and the test finishing at
/// all is the proof it did not hang; the control proves the same helper still
/// returns promptly for a condition that does hold.
@MainActor
final class AWaitThatNeverHappensFailsTests: XCTestCase {

    func testAConditionThatNeverHoldsFailsWithinItsDeadline() async {
        let started = ContinuousClock.now
        XCTExpectFailure("the condition never holds")
        await waitUntil("a thing that never happens", within: .milliseconds(200)) { false }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2))
    }

    func testAConditionSetFromADetachedTaskAfterAWhilePasses() async {
        let flag = Locked(false)
        Task.detached {
            try? await Task.sleep(for: .milliseconds(50))
            flag.value = true
        }
        await waitUntil("the flag", within: .seconds(5)) { flag.value }
        XCTAssertTrue(flag.value)
    }
}

/// `waitUntilReached` is the free-function twin for cases that are **not**
/// `@MainActor`; its own assertion is guarded here, not through its callers.
/// The failing half runs on the main actor because `XCTExpectFailure` does not
/// reliably match an issue recorded on another thread after an `await`.
final class AFreeWaitThatNeverHappensFailsTests: XCTestCase {
    @MainActor
    func testTheFreeFunctionFailsWhenTheConditionNeverHolds() async {
        let started = ContinuousClock.now
        XCTExpectFailure("the condition never holds")
        await waitUntilReached("a thing that never happens", within: .milliseconds(200)) { false }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2))
    }

    func testTheFreeFunctionReturnsPromptlyForAConditionThatHolds() async {
        let started = ContinuousClock.now
        await waitUntilReached("a thing that already holds", within: .seconds(5)) { true }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
    }
}
