// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmRuntime
@testable import Module_VPN_Engine

/// **The module announces a rule's work before it has asked the tool to do it.**
///
/// `connectNow` records the firing — the ring, the menu-bar name and, in the
/// banner mode, a macOS notification saying «Connected to Office» — and *then*
/// runs `scutil --nc start`. `disconnectNow` is the same shape: it announces and
/// wipes both books before the `stop` is issued. Neither looks at the reply.
///
/// So a rule pointing at a configuration that was renamed in System Settings —
/// the case `VPNCommandReply` and `ARefusedCommandIsNotSilenceTests` exist for,
/// and the very case `VPNFailure.Reason.noSuchService` is named after — tells the
/// person they are behind a tunnel that was never raised. That is the one
/// sentence this module must never produce: `VPNAutomation.Kind.dropped` exists
/// because the app decided that «you believe you are tunnelled and you are not»
/// is worth a system notification, and here the app manufactures that belief
/// itself.
///
/// Every test in `VPNAutomationRecordingTests` runs with `FakeRunner.reply` left
/// at `""`, which is what `scutil` prints when it **succeeded**. The whole
/// recording table was therefore proved against a tool that cannot refuse, which
/// is why the ordering was never seen.
final class ARefusalIsNotAnnouncedAsDoneTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func list(_ status: String, _ name: String = "A") -> String {
        "(\(status)) \(uuid) IPSec \"\(name)\""
    }

    private func settings(rules: String? = nil) -> VPNSettings {
        let s = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                   backing: InMemoryKeyValueStore()))
        if let rules { s.setRulesJSON(rules) }
        return s
    }

    private func engine(_ runner: FakeRunner,
                        apps: FakeApps = FakeApps(),
                        settings: VPNSettings? = nil) -> VPNEngine {
        let at = self.at
        return VPNEngine(settings: settings ?? self.settings(), runner: runner, apps: apps,
                         now: { at }, work: .inline)
    }

    // MARK: - The control

    /// The partner assertion every «nothing was announced» below needs: with the
    /// tool accepting, this same call *does* announce. Without it, a module that
    /// had stopped recording altogether would pass the whole file.
    func testAToolThatAcceptsIsStillAnnounced() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
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
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected", "Office")
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
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        runner.reply = "cannot start A: busy"
        let e = engine(runner)

        e.connect("A", auto: true)

        XCTAssertEqual(e.lastFailure?.reason, .refused, "precondition: the refusal was read")
        XCTAssertNotEqual(e.lastAutomation?.kind, .connected)
    }

    /// The state the page is actually handed, decoded from the event rather than
    /// from the accessors: one payload carrying «Helm connected you to Old office»
    /// and «there is no configuration called Old office» at the same time. The
    /// page draws the failure banner *and* the view model posts the banner, so
    /// the two channels contradict each other in one frame.
    func testTheEmittedStateDoesNotCarryBothAConnectionAndItsRefusal() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected", "Office")
        runner.reply = "No service"
        let e = engine(runner)

        e.connect("Old office", auto: true)

        var payload: VPNEngine.StatePayload?
        for await event in e.transport.events where event.name == "state" {
            payload = try? JSONDecoder().decode(VPNEngine.StatePayload.self, from: event.payload)
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

    /// And Helm must not write it into its own book of «tunnels I raised». That
    /// book is what the quit rule and the page's green «working now» dot read, and
    /// a name that never came up stays in it for the life of the process — the
    /// refresh path only forgets names that were once seen up.
    func testARefusedConnectDoesNotClaimTheTunnelAsHelmsOwn() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected", "Office")
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

    /// The rule's app quits, Helm asks for the stop, and the configuration has
    /// been renamed since it was raised. The stop fails; the tunnel stays up; the
    /// person is told it came down, and both books are wiped so no later drop can
    /// be reported for it either.
    func testATeardownTheToolRefusedIsNotADisconnection() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let apps = FakeApps.trustingA()
        let e = engine(runner, apps: apps, settings: settings(rules: ruleJSONForA))

        e.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        runner.listOutput = list("Connected")     // the tunnel came up
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

    /// …and the tunnel it failed to stop is still Helm's. Forgetting it is what
    /// makes the later drop unreportable: `refreshNow` only announces a drop for a
    /// name that is still in `_autoConnected`.
    func testARefusedTeardownDoesNotForgetTheTunnelItLeftUp() {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let apps = FakeApps.trustingA()
        let e = engine(runner, apps: apps, settings: settings(rules: ruleJSONForA))

        e.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        runner.listOutput = list("Connected")
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
