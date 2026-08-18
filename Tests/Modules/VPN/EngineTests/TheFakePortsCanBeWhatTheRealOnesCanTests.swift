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

    /// The two answers this port still gives fail separately: a Mac with no
    /// default route at all, and an interface the kernel has no counters for.
    func testTheInterfacePortCanBeMissingEitherAnswerSeparately() {
        let port = FakeInterfaces()
        port.primary = "en0"                        // the Mac is on Wi-Fi
        port.counters = [:]                         // and nothing has counters
        XCTAssertEqual(port.primaryInterface(), "en0")
        XCTAssertNil(port.bytes(on: "utun4"))

        port.primary = nil                          // and now it is offline
        port.counters = ["utun4": (in: 10, out: 20)]
        XCTAssertNil(port.primaryInterface())
        XCTAssertEqual(port.bytes(on: "utun4")?.in, 10)
    }

    /// **What a tunnel's interface is cannot be planted here at all any more**,
    /// and that is the repair: the pair this fake used to accept — a `--nc list`
    /// id and an interface — is one the dynamic store cannot produce for a
    /// NetworkExtension tunnel, so the suite was green while the strip was
    /// absent on every Mac. The question is the tool's now, and the fake that
    /// answers it is `FakeRunner.statusOutput`, keyed by the name the tool takes
    /// and able to be in the state where the connection is known and no
    /// interface is named.
    func testTheInterfaceIsAskedOfTheToolByName() {
        let runner = FakeRunner()
        runner.statusOutput = ["incy": """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun8
          }
        }
        """]
        XCTAssertEqual(VPNStatusParser.reading(in: runner.run(["--nc", "status", "incy"]).output)?
            .interface, "utun8")
        XCTAssertNil(VPNStatusParser.reading(in: runner.run(["--nc", "status", "other"]).output),
                     "a name the tool has no answer for must be able to name no interface")
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
