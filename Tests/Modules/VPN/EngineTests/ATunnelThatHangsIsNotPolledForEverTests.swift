// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// The bound between a tunnel that hangs and `scutil` being run for ever.
///
/// A connect schedules `pollUntilSettled`, which re-reads the list until the
/// tunnel has settled into what was asked for and stops at `maxPollAttempts`.
/// `FakeRunner.listScript` lets the tool's answer change read by read, as the
/// real tool's does while a tunnel comes up.
final class ATunnelThatHangsIsNotPolledForEverTests: XCTestCase {

    /// `.inline`: the poll's body runs straight through instead of after 0.7 s,
    /// so the whole poll happens inside `connect` and its length can be read.
    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(),
                  runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    /// A server that never answers: the list says `Connecting` for ever.
    ///
    /// Asserted as a bound rather than its exact value, from **both** sides: a
    /// poll that gives up at once leaves the spinner stuck, and a poll with no
    /// ceiling runs a subprocess until the app quits.
    func testAConnectingTunnelIsPolledAndThenGivenUpOn() {
        let runner = FakeRunner()
        runner.listScript = [scutilListRow("Connecting")]
        let e = engine(runner)

        e.connect("A", auto: false)

        XCTAssertGreaterThan(runner.listReadCount, 2,
                             "a tunnel still coming up was not re-read at all: the card would "
                             + "sit on «Connecting…» until something else redrew it")
        XCTAssertLessThan(runner.listReadCount, 40,
                          "\(runner.listReadCount) reads of `scutil --nc list` for one connect — "
                          + "a tunnel that never settles must not run a subprocess for ever")
        XCTAssertEqual(e.status("A"), .connecting,
                       "precondition: the tool really did keep saying Connecting")
    }

    /// The control: once the poll has started it does run to the end, and stops
    /// there rather than using up its ceiling.
    func testAPollThatHasStartedFollowsATunnelUpAndThenStops() {
        let runner = FakeRunner()
        runner.listScript = [scutilListRow("Connecting"), scutilListRow("Connecting"), scutilListRow("Connected")]
        let e = engine(runner)

        e.connect("A", auto: false)

        XCTAssertEqual(e.status("A"), .connected, "the poll did not follow the tunnel up")
        XCTAssertLessThan(runner.listReadCount, 8,
                          "the tunnel settled and the engine kept reading: "
                          + "\(runner.listReadCount) reads")
    }

    /// **The sequence the real tool produces: the old status first.** The read
    /// after a connect usually still says `Disconnected`, which is not a
    /// transition, so a poll that stopped when nothing was moving would never
    /// wait for a slow handshake. The exit condition is «settled into what was
    /// asked for».
    func testAConnectIsFollowedUpEvenWhenTheToolHasNotCaughtUpYet() {
        let runner = FakeRunner()
        runner.listScript = [scutilListRow("Disconnected"),   // the tool has not caught up yet
                             scutilListRow("Connecting"),
                             scutilListRow("Connected")]
        let e = engine(runner)

        e.connect("A", auto: false)

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]),
                      "precondition: the connect was issued")
        XCTAssertEqual(e.status("A"), .connected,
                       "the poll gave up after \(runner.listReadCount) read(s) because the tool "
                       + "was still saying Disconnected — which is what it says while a tunnel "
                       + "comes up, and the only state the poll exists for")
    }

    /// **Only a command the tool accepted is followed.** «Keep reading until the
    /// tunnel is up» would spend every attempt on a name `scutil` has already
    /// said does not exist. The precondition keeps this from passing on a module
    /// that has stopped reading refusals.
    func testARefusedConnectIsNotPolledAsIfItHadStarted() {
        let runner = FakeRunner()
        runner.listScript = [scutilListRow("Disconnected")]
        runner.replies["Old office"] = "No service"
        let e = engine(runner)

        e.connect("Old office", auto: false)

        XCTAssertEqual(e.lastFailure?.reason, .noSuchService, "precondition: it was refused")
        XCTAssertLessThan(runner.listReadCount, 4,
                          "\(runner.listReadCount) polls waiting for a tunnel `scutil` said "
                          + "does not exist")
    }
}
