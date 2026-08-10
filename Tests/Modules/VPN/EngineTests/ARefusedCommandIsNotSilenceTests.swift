// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `scutil --nc start` reports failure by printing a line and exiting **0**,
/// and both call sites threw that line away — `_ = runner.run(args)`.
///
/// Measured on macOS 27, on the Mac this was written on:
///
/// ```
/// $ scutil --nc stop "NBCom VPN"      # a real service
/// $ echo $?
/// 0                                  # …and no output at all
/// $ scutil --nc start "no-such-vpn-name"
/// No service
/// $ echo $?
/// 0
/// ```
///
/// So a configuration renamed or deleted in System Settings — or a per-app rule
/// left pointing at one — failed in complete silence: no log line, nothing on
/// screen, and a tunnel that simply never came up.
///
/// The sibling path had already learned this. `UnreadableListTests` exists
/// because `--nc list` answering nothing looked exactly like a Mac with no VPN,
/// and its own comment says the runner «returns only the tool's stdout and
/// throws the exit status away». The list was fixed; the two commands were not.
final class ARefusedCommandIsNotSilenceTests: XCTestCase {

    // MARK: - The reading

    func testSilenceIsSuccess() {
        XCTAssertEqual(VPNCommandReply.of(""), .accepted)
        XCTAssertEqual(VPNCommandReply.of("   \n "), .accepted)
    }

    func testTheToolsOwnWordsForAMissingConfiguration() {
        XCTAssertEqual(VPNCommandReply.of("No service"), .noSuchService)
        XCTAssertEqual(VPNCommandReply.of("No service\n"), .noSuchService)
        // Matched case-insensitively but never translated: `scutil` is not
        // localized, and a Mac in another language still prints English.
        XCTAssertEqual(VPNCommandReply.of("no service"), .noSuchService)
    }

    /// Anything else is kept verbatim rather than mapped to «failed». The set
    /// of things this tool can print is not ours to enumerate, and an unknown
    /// message is worth more in the trail than a word we chose.
    func testAnythingElseIsCarriedThrough() {
        XCTAssertEqual(VPNCommandReply.of("Some future complaint"),
                       .refused("Some future complaint"))
    }

    // MARK: - What the engine does with it

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                               backing: InMemoryKeyValueStore())),
                  runner: runner, credentials: nil, apps: FakeApps(), work: .inline)
    }

    /// The control. An ordinary connect leaves nothing to report — otherwise
    /// every assertion below passes on a module that reports constantly.
    func testAnOrdinaryConnectReportsNothing() {
        let runner = FakeRunner()
        runner.reply = ""
        let e = engine(runner)
        e.connect("Office")
        XCTAssertNil(e.lastFailure)
    }

    func testAConnectToAMissingConfigurationIsSaidOutLoud() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.connect("Old office")

        XCTAssertEqual(e.lastFailure, VPNFailure(name: "Old office", reason: .noSuchService),
                       "the tunnel never came up and nothing anywhere said why")
    }

    func testADisconnectReportsToo() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.disconnect("Old office")

        XCTAssertEqual(e.lastFailure?.reason, .noSuchService)
    }

    /// …and the next command that works clears it. A failure that outlived its
    /// cause would be a page permanently warning about something already fixed.
    func testTheNextCommandThatWorksClearsIt() {
        let runner = FakeRunner()
        runner.reply = "No service"
        let e = engine(runner)
        e.connect("Old office")
        XCTAssertNotNil(e.lastFailure, "precondition")

        runner.reply = ""
        e.connect("Office")

        XCTAssertNil(e.lastFailure)
    }

    /// The log carries the fact and not the name. Every other line this module
    /// writes goes through `Redact.vpn`, because the diagnostic file leaves the
    /// machine and the screen does not.
    func testTheLogDoesNotNameTheConfiguration() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        let runner = FakeRunner()
        runner.reply = "No service"
        engine(runner).connect("Secret Office VPN")

        let lines = HelmLog.shared.recentEntries().filter { $0.category == "vpn" }
        XCTAssertFalse(lines.isEmpty, "precondition: something was logged at all")
        XCTAssertFalse(lines.contains { $0.message.contains("Secret Office VPN") },
                       "the connection's name reached the log file")
        XCTAssertTrue(lines.contains { $0.message.contains("no such configuration") },
                      "…and the reason did not")
    }
}
