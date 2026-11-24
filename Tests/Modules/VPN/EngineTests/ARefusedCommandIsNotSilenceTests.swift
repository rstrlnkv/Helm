// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `scutil --nc start` and `stop` report failure by printing a line and exiting
/// **0** (`scutil --nc start "no-such-vpn-name"` prints `No service`, exit 0; a
/// stop that worked prints nothing). The line is read, so a configuration
/// renamed or deleted in System Settings, or a rule left pointing at one, does
/// not fail in silence. `UnreadableListTests` holds the same for `--nc list`.
final class ARefusedCommandIsNotSilenceTests: XCTestCase {

    // MARK: - The reading

    func testSilenceIsSuccess() {
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: ""), name: "Office"), .accepted)
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: "   \n "), name: "Office"), .accepted)
    }

    func testTheToolsOwnWordsForAMissingConfiguration() {
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: "No service"), name: "Office"), .noSuchService)
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: "No service\n"), name: "Office"), .noSuchService)
        // Matched case-insensitively but never translated: `scutil` is not
        // localized, and a Mac in another language still prints English.
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: "no service"), name: "Office"), .noSuchService)
    }

    /// Anything else is kept verbatim rather than mapped to «failed»: what the
    /// tool can print is not ours to enumerate.
    func testAnythingElseIsCarriedThrough() {
        XCTAssertEqual(VPNCommandReply.of(.init(status: 0, output: "Some future complaint"), name: "Office"),
                       .refused("Some future complaint"))
    }

    // MARK: - What the engine does with it

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(),
                  runner: runner, credentials: nil, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    /// The control: an ordinary connect leaves nothing to report.
    func testAnOrdinaryConnectReportsNothing() {
        let runner = FakeRunner()
        runner.reply = ""
        let e = engine(runner)
        e.connect("Office", auto: false)
        XCTAssertNil(e.lastFailure)
    }

    func testAConnectToAMissingConfigurationIsSaidOutLoud() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.connect("Old office", auto: false)

        XCTAssertEqual(e.lastFailure,
                       VPNFailure(name: "Old office", reason: .noSuchService, verb: .connect),
                       "the tunnel never came up and nothing anywhere said why")
    }

    func testADisconnectReportsToo() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.disconnect("Old office", auto: false)

        XCTAssertEqual(e.lastFailure?.reason, .noSuchService)
    }

    /// …and the next command that works clears it. A failure that outlived its
    /// cause would be a page permanently warning about something already fixed.
    func testTheNextCommandThatWorksClearsIt() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.connect("Old office", auto: false)
        XCTAssertNotNil(e.lastFailure, "precondition")

        runner.reply = ""
        e.connect("Office", auto: false)

        XCTAssertNil(e.lastFailure)
    }

    /// The log carries the fact and not the name: the diagnostic file leaves
    /// the machine and the screen does not.
    func testTheLogDoesNotNameTheConfiguration() {
        tailTheLog()

        let runner = FakeRunner()
        runner.reply = "No service"
        engine(runner).connect("Secret Office VPN", auto: false)

        let lines = loggedLines("vpn")
        XCTAssertFalse(lines.isEmpty, "precondition: something was logged at all")
        XCTAssertFalse(lines.contains { $0.contains("Secret Office VPN") },
                       "the connection's name reached the log file")
        XCTAssertTrue(lines.contains { $0.contains("no such configuration") },
                      "…and the reason did not")
    }
}
