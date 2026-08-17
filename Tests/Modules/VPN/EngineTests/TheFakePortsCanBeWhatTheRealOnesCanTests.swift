// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// A fake simpler than the port it stands for makes a whole family of tests
/// impossible to write, however carefully somebody tries (CLAUDE.md § A fake
/// simpler than the thing it stands for). These are the states the three network
/// ports can really be in, asserted of the fakes that stand for them.
final class TheFakePortsCanBeWhatTheRealOnesCanTests: XCTestCase {

    func testTheInterfacePortCanBeMissingEitherAnswerSeparately() {
        let port = FakeInterfaces()
        port.interfaces = [:]                       // the service is down
        port.primary = "en0"                        // and the Mac is on Wi-Fi
        XCTAssertNil(port.interface(forServiceID: "svc"))
        XCTAssertEqual(port.primaryInterface(), "en0")

        port.interfaces = ["svc": "utun4"]
        port.primary = nil                          // and now it is offline
        XCTAssertEqual(port.interface(forServiceID: "svc"), "utun4")
        XCTAssertNil(port.primaryInterface())
    }

    /// The service that never answers. A fake that answers instantly makes every
    /// test of «measuring…» vacuous: the state is over before the assertion.
    ///
    /// **What is asserted is that the call has not returned**, not that the task
    /// was never cancelled: `isCancelled` is false for a task that has already
    /// finished too, so with `hangs` deleted from the fake this test still
    /// passed — measured, which is why the box is here (CLAUDE.md § A check that
    /// cannot fail is not a check).
    func testTheExitPortCanTakeForeverWithoutAnswering() async {
        let port = FakeExit()
        port.answer = nil
        port.hangs = true
        let answered = ProgressBox()
        let task = Task {
            _ = await port.regionCode()
            answered.record(1)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(answered.value, 0, "the fake answered; «while it is measuring» is a state "
            + "no test of the caller could observe")
        XCTAssertFalse(task.isCancelled)
        task.cancel()
    }

    func testTheSpeedPortCanRefuse() {
        let port = FakeSpeed()
        port.answer = nil
        XCTAssertNil(port.measure(onInterface: "utun4"))
    }

    /// And it records what it was asked to measure, so «the run was bound to the
    /// tunnel» is a fact a test can assert rather than a hope.
    func testTheSpeedPortRemembersWhichInterfaceItWasBoundTo() {
        let port = FakeSpeed()
        port.answer = VPNSpeedReading(down: 1, up: 1, rpm: 1, at: Date())
        _ = port.measure(onInterface: "utun7")
        XCTAssertEqual(port.askedFor as? [String], ["utun7"])
    }
}
