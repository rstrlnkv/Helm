// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
@testable import Module_VPN_Engine

/// **A rule's work is announced only after the tool has accepted it.**
///
/// The firing (the ring, the menu-bar name, a macOS notification saying
/// «Connected to Office») and the books of what Helm raised follow the reply of
/// `scutil --nc start` / `stop`, not the request. A rule pointing at a
/// configuration renamed in System Settings (`VPNFailure.Reason.noSuchService`)
/// must not tell the person they are behind a tunnel that was never raised: that
/// is the belief `VPNAutomation.Kind.dropped` exists to correct.
///
/// `VPNAutomationRecordingTests` runs with `FakeRunner.reply` at `""`, what
/// `scutil` prints when it succeeded, so the refusals are proved here.
final class ARefusalIsNotAnnouncedAsDoneTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func settings(rules: String? = nil) -> VPNSettings {
        let s = VPNSettings.inMemory()
        if let rules { s.setRulesJSON(rules) }
        return s
    }

    private func engine(_ runner: FakeRunner,
                        apps: FakeApps = FakeApps(),
                        settings: VPNSettings? = nil) -> VPNEngine {
        let at = self.at
        return VPNEngine(settings: settings ?? self.settings(), runner: runner, apps: apps,
                         interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                         now: { at }, work: .inline)
    }

    // MARK: - The control

    /// The partner of every «nothing was announced» below: with the tool
    /// accepting, this same call *does* announce.
    func testAToolThatAcceptsIsStillAnnounced() {
        let runner = FakeRunner(list: scutilListRow("Disconnected"))
        runner.reply = ""                     // what scutil prints when it worked
        let e = engine(runner)

        e.connect("A", auto: true)

        XCTAssertEqual(e.lastAutomation, VPNAutomation(at: at, name: "A", kind: .connected),
                       "precondition: an accepted connect is a firing")
    }

    // MARK: - The connect the tool never performed

    /// A rule whose configuration is gone. `scutil` prints `No service`, exits 0,
    /// and the tunnel does not come up — and the person is told it did.
    func testAConnectTheToolRefusedIsNotAConnection() {
        let runner = FakeRunner(list: scutilListRow("Disconnected", "Office"))
        runner.reply = "No service"
        let e = engine(runner)

        e.connect("Old office", auto: true)

        XCTAssertEqual(e.lastFailure?.reason, .noSuchService,
                       "precondition: the engine did read the refusal")
        XCTAssertNotEqual(e.lastAutomation?.kind, .connected,
                          "the banner said «connected to Old office» and no tunnel was raised — "
                          + "the person is sending in clear believing they are not")
    }

    /// The same for anything else the tool says. `.refused` is the open case, so a
    /// message nobody has enumerated must not read as success either.
    func testAConnectTheToolComplainedAboutIsNotAConnection() {
        let runner = FakeRunner(list: scutilListRow("Disconnected"))
        runner.reply = "cannot start A: busy"
        let e = engine(runner)

        e.connect("A", auto: true)

        XCTAssertEqual(e.lastFailure?.reason, .refused, "precondition: the refusal was read")
        XCTAssertNotEqual(e.lastAutomation?.kind, .connected)
    }

    /// The state the page is handed, decoded from the event: one payload must
    /// not carry «Helm connected you to Old office» and «there is no
    /// configuration called Old office» at once.
    func testTheEmittedStateDoesNotCarryBothAConnectionAndItsRefusal() async {
        let runner = FakeRunner(list: scutilListRow("Disconnected", "Office"))
        runner.reply = "No service"
        let e = engine(runner)

        e.connect("Old office", auto: true)

        var payload: VPNEngine.StatePayload?
        for await state in e.stream() {
            payload = state
            break
        }
        guard let payload else {
            return XCTFail("no state event was emitted, so there is nothing to contradict")
        }
        XCTAssertFalse(payload.lastAutomation?.kind == .connected && payload.lastFailure != nil,
                       "one payload says the tunnel came up and says the configuration does not "
                       + "exist: \(String(describing: payload.lastAutomation)) / "
                       + "\(String(describing: payload.lastFailure))")
    }

    /// Nor into Helm's book of «tunnels I raised», which the quit rule and the
    /// green dot read: the refresh path only forgets names once seen up, so a
    /// name that never came up would stay for the life of the process.
    func testARefusedConnectDoesNotClaimTheTunnelAsHelmsOwn() {
        let runner = FakeRunner(list: scutilListRow("Disconnected", "Office"))
        runner.reply = "No service"
        let e = engine(runner)

        e.connect("Old office", auto: true)
        e.refresh()
        e.refresh()

        XCTAssertFalse(e.autoConnected.contains("Old office"),
                       "Helm owns a tunnel the tool told it does not exist, and nothing "
                       + "ever clears it")
    }

    // MARK: - The teardown the tool never performed

    /// The rule's app quits and the configuration has been renamed since it was
    /// raised: the stop fails, the tunnel stays up, and the person must not be
    /// told it came down.
    func testATeardownTheToolRefusedIsNotADisconnection() {
        let runner = FakeRunner(list: scutilListRow("Disconnected"))
        let apps = FakeApps.trustingA()
        let e = engine(runner, apps: apps, settings: settings(rules: ruleJSONForA))

        e.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        runner.listOutput = scutilListRow("Connected")     // the tunnel came up
        e.refresh()
        e.clearLastAutomationForTesting()

        // Renamed in System Settings between the launch and the quit: the list
        // still answers, the name the rule holds no longer resolves.
        runner.reply = "No service"
        apps.bundleIDs = []
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]),
                      "precondition: the rule did fire")
        XCTAssertEqual(e.lastFailure?.reason, .noSuchService,
                       "precondition: the engine read the refusal")
        XCTAssertNotEqual(e.lastAutomation?.kind, .disconnected,
                          "the tunnel is still up and the person was told Helm took it down")
    }

    /// …and the tunnel it failed to stop is still Helm's: `refreshNow` only
    /// announces a drop for a name still in `_autoConnected`.
    func testARefusedTeardownDoesNotForgetTheTunnelItLeftUp() {
        let runner = FakeRunner(list: scutilListRow("Disconnected"))
        let apps = FakeApps.trustingA()
        let e = engine(runner, apps: apps, settings: settings(rules: ruleJSONForA))

        e.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        runner.listOutput = scutilListRow("Connected")
        e.refresh()
        XCTAssertTrue(e.autoConnected.contains("A"), "precondition: Helm raised it")

        runner.reply = "No service"
        apps.bundleIDs = []
        apps.fire()

        XCTAssertTrue(e.autoConnected.contains("A"),
                      "the stop was refused and the tunnel is up, but Helm has stopped "
                      + "counting it as its own — so its eventual drop is news nobody sends")
    }
}
