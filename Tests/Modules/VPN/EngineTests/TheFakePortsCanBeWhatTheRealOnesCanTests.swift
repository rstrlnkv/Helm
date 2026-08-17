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
    /// **What is asserted is that the call was entered and has not returned.**
    /// The entry is the control: an assertion about an absence — «it has not
    /// answered» — also holds when the caller was never scheduled at all, and
    /// then it is measuring nothing (CLAUDE.md § a test asserting an absence
    /// passes when the subject never happened). It used to end on
    /// `XCTAssertFalse(task.isCancelled)`, which the comment above it already
    /// said asserts nothing: `isCancelled` is false for a finished task too.
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
        XCTAssertEqual(port.asks, 1, "the request was never made, so «it has not answered» is "
            + "true of a call nobody placed")
        XCTAssertEqual(answered.value, 0, "the fake answered; «while it is measuring» is a state "
            + "no test of the caller could observe")
        task.cancel()
    }

    func testTheSpeedPortCanRefuse() {
        let port = FakeSpeed()
        port.answer = nil
        XCTAssertNil(port.measure(onInterface: "utun4"))
    }

    /// **And it can be slow, which is the whole of what the real one is.**
    /// `networkQuality` holds its thread for about fifteen seconds; a fake that
    /// returns at once means «the tile says Measuring…» and «a Connect pressed
    /// during a run is still answered» are states no test can observe, however
    /// carefully anybody writes one. The gate is a semaphore rather than a
    /// sleep, so a test waits on the state instead of on the clock.
    func testTheSpeedPortCanBeInTheMiddleOfARun() async {
        let port = FakeSpeed()
        port.answer = VPNSpeedReading(down: 1, up: 1, rpm: 1, at: Date())
        port.blocksUntilReleased = true
        let started = expectation(description: "the run has entered the tool")
        let finished = expectation(description: "the run returned once released")
        port.onStart = { started.fulfill() }
        let returned = ProgressBox()
        DispatchQueue.global().async {
            _ = port.measure(onInterface: nil)
            returned.record(1)
            finished.fulfill()
        }

        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(returned.value, 0,
                       "the run was over before the test could look at it")

        port.release()
        await fulfillment(of: [finished], timeout: 5)
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
