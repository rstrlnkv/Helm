// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A rule for an unsigned or unrecorded app looked like a working one.** The
/// refusal reached only `helm.log`, so an unattended rule that never fired showed
/// in the rules popover as a rule that did. The engine now publishes the reason
/// per rule (`StatePayload.ruleRefusals`), from the expression `judge` consults.
final class ARuleThatWillNotFireSaysSoTests: XCTestCase {

    private let bundleID = "com.example.app"
    private let header = "Available network connection services:"
    private let real = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")

    private let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                              backing: InMemoryKeyValueStore()))
    private let runner = FakeRunner()

    private func engine(identity: CodeIdentity?, apps: FakeApps) -> VPNEngine {
        settings.setRulesJSON(VPNRules.encode(
            [bundleID: VPNAppRule(vpnName: "Office", identity: identity)]))
        runner.listOutput = [header,
            "* (Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"Office\" [IPSec:1]"]
            .joined(separator: "\n")
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.activate()
        return engine
    }

    private func published(_ engine: VPNEngine) async -> [String: VPNRuleTrust.Verdict]? {
        for await state in engine.stream() { return state.ruleRefusals }
        return nil
    }

    /// The note's reason is the one the launch is refused with: the same rule
    /// launched, and the log line carries the verdict the payload carries.
    func testEachRuleLevelRefusalIsPublishedWithTheReasonTheLaunchIsRefusedFor() async {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        let cases: [(CodeIdentity?, VPNRuleTrust.Verdict)] = [
            (nil, .noIdentityRecorded),
            (CodeIdentity(signingID: nil, teamID: nil), .appNotSigned)]
        for (identity, expected) in cases {
            HelmLog.shared.clearTail()
            let apps = FakeApps()
            apps.identities[bundleID] = real
            let engine = engine(identity: identity, apps: apps)
            apps.bundleIDs = [bundleID]
            apps.fire()

            let lines = HelmLog.shared.recentEntries().filter { $0.category == "vpn" }
            XCTAssertTrue(lines.contains { $0.message.contains("did not fire: \(expected.rawValue)") },
                          "precondition: the engine refuses for \(expected): \(lines.map(\.message))")
            let note = await published(engine)
            XCTAssertEqual(note, [bundleID: expected],
                           "the note and the refusal came from two different answers")
        }
    }

    /// The control: a trusted rule publishes nothing, and does fire.
    func testATrustedRulePublishesNoNote() async {
        let apps = FakeApps()
        apps.identities[bundleID] = real
        let engine = engine(identity: real, apps: apps)
        apps.bundleIDs = [bundleID]
        apps.fire()
        XCTAssertFalse(runner.issued.filter { $0.count > 1 && $0[1] == "start" }.isEmpty,
                       "precondition: the trusted rule fired")
        let note = await published(engine)
        XCTAssertEqual(note, [:])
    }

    /// Choosing the app again records an identity: the next reload withdraws the note.
    func testPickingTheAppAgainWithdrawsTheNote() async {
        let apps = FakeApps()
        let engine = engine(identity: nil, apps: apps)
        let before = await published(engine)
        XCTAssertEqual(before, [bundleID: .noIdentityRecorded], "precondition")
        settings.setRulesJSON(VPNRules.encode(
            [bundleID: VPNAppRule(vpnName: "Office", identity: real)]))
        engine.reloadRules()
        let after = await published(engine)
        XCTAssertEqual(after, [:])
    }
}
