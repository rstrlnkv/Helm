// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// Two windows, one firing. The ring spins for a moment; the name stays long
/// enough to be read. Both are measured from an injected `now`, never the
/// machine's clock — a test that asks what time it is asks a different question
/// on every run.
final class VPNAutomationTests: XCTestCase {
    private let fired = Date(timeIntervalSince1970: 1_000_000)
    private func automation(_ kind: VPNAutomation.Kind = .connected) -> VPNAutomation {
        VPNAutomation(at: fired, name: "work", kind: kind)
    }

    func testTheSpinRunsForItsWindowAndThenStops() throws {
        XCTAssertEqual(VPNAutomation.spinPhase(automation(), now: fired), 0)
        let mid = VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(0.6))
        XCTAssertEqual(try XCTUnwrap(mid), 0.5, accuracy: 0.001)
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(1.2)),
                     "the spin outlived its window")
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(9)))
    }

    func testTheNameOutlivesTheSpin() {
        XCTAssertTrue(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(1.5)),
                      "the name should still be readable after the ring settles")
        XCTAssertFalse(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(3.1)))
    }

    /// A clock that has gone backwards (NTP, sleep) must not produce an
    /// animation that never ends.
    func testAFiringInTheFutureIsNotAnimated() {
        XCTAssertNil(VPNAutomation.spinPhase(automation(), now: fired.addingTimeInterval(-5)))
        XCTAssertFalse(VPNAutomation.showsName(automation(), now: fired.addingTimeInterval(-5)))
    }

    func testTheEndOfTheSpinIsTheEndOfTheWindow() {
        XCTAssertEqual(VPNAutomation.spinEnd(automation()), fired.addingTimeInterval(1.2))
    }
}
