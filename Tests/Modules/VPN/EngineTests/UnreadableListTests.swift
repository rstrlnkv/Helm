// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm contributors

import XCTest
@testable import Module_VPN_Engine

/// "No VPNs are configured" and "scutil did not answer" are different facts.
///
/// `parseList` skips every line it cannot read, so a failed read parsed alone
/// would produce `[]`, exactly like a machine with nothing configured. Two
/// things would go wrong at once:
///
/// 1. The page would say "No VPNs in System Settings" while two were
///    connected, and every per-app rule would report its connection gone.
/// 2. `refreshNow` computes what dropped from `_autoConnected` and what is up.
///    With an empty read **everything Helm ever raised looks dropped**, and the
///    ring would name a disconnection that never happened.
///
/// The discriminator: a real answer either carries the header `scutil --nc
/// list` prints before it enumerates anything — present even on a machine with
/// no VPNs at all — or contains at least one row we could read. Nothing else
/// is an answer.
final class UnreadableListTests: XCTestCase {

    private let header = "Available network connection services in the current set (*=enabled):"
    private let uuid = "11111111-1111-1111-1111-111111111111"
    private func row(_ status: String, _ name: String) -> String {
        "* (\(status)) \(uuid) PPP --> L2TP \"\(name)\" [PPP:L2TP]"
    }

    private func makeEngine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(),
                  runner: runner,
                  apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    // MARK: - Telling an answer from a silence

    func testAnEmptyReadIsNotAnAnswer() {
        XCTAssertFalse(VPNListParser.isReadable(""))
        XCTAssertFalse(VPNListParser.isReadable("   \n  "))
    }

    func testAToolThatFailedIsNotAnAnswer() {
        XCTAssertFalse(VPNListParser.isReadable("scutil: cannot open connection"))
    }

    /// The case that must not be mistaken for a failure.
    func testAMachineWithNoVPNsIsStillAnAnswer() {
        XCTAssertTrue(VPNListParser.isReadable(header + "\n"))
        XCTAssertTrue(VPNListParser.parseList(header + "\n").isEmpty)
    }

    /// Rows without the header are an answer too: every fixture in this suite
    /// is written that way, and a row we could read is proof the tool spoke.
    func testRowsAloneAreAnAnswer() {
        XCTAssertTrue(VPNListParser.isReadable(row("Connected", "work")))
    }

    // MARK: - What the engine does with a silence

    func testAnUnreadableRefreshKeepsTheConnectionsItAlreadyHad() {
        let runner = FakeRunner(list: row("Connected", "work"))
        let engine = makeEngine(runner)
        engine.refresh()
        XCTAssertEqual(engine.connections.map(\.name), ["work"])

        runner.listOutput = ""              // the read fails
        engine.refresh()

        XCTAssertEqual(engine.connections.map(\.name), ["work"],
                       "an unreadable answer emptied the list, so the page tells the user "
                       + "their VPNs are gone while they are connected")
    }

    func testAnAnswerSayingNothingIsConfiguredIsStillObeyed() {
        let runner = FakeRunner(list: row("Connected", "work"))
        let engine = makeEngine(runner)
        engine.refresh()

        runner.listOutput = header + "\n"   // the tool answered: there are none
        engine.refresh()

        XCTAssertTrue(engine.connections.isEmpty,
                      "a real answer was ignored — removing the last VPN in System Settings "
                      + "would never reach the page")
    }

    /// The dangerous half: a read that failed must not look like every tunnel
    /// dropping at once.
    func testAnUnreadableRefreshDoesNotAnnounceADisconnection() {
        let runner = FakeRunner(list: row("Connected", "work"))
        let engine = makeEngine(runner)
        engine.connect("work", auto: true)
        engine.refresh()                    // it came up because of us
        engine.clearLastAutomationForTesting()

        runner.listOutput = ""              // the read fails
        engine.refresh()

        XCTAssertNil(engine.lastAutomation,
                     "a failed read was reported as the tunnel dropping — the ring would spin "
                     + "and name a disconnection that never happened")
    }
}
