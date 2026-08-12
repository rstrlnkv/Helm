// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `lastUsedName` is an unsealed plist string that steers which configuration a
/// one-click toggle acts on, and any process running as this user can rewrite the
/// module's defaults.
///
/// What stops that from being worth anything is the **bound**: the stored word is
/// not a command, it is a lookup key into the list `scutil` just answered with, so
/// the worst a forged value can do is nominate a configuration the person already
/// has. That bound is the whole defence, so it is a test rather than a sentence —
/// and the alternative, sealing the value, is refused on purpose: it is read from
/// `defaultConnection` on every state the engine emits and during `activate()`,
/// and ARCHITECTURE.md § A seal needs a signature records what a keychain read at
/// launch costs on an ad-hoc-signed bundle.
final class AForgedLastUsedNameIsBoundedTests: XCTestCase {

    private let header = "Available network connection services:"
    private func row(_ status: String, _ id: String, _ name: String) -> String {
        "* (\(status)) \(id) IPSec \"\(name)\" [IPSec:1]"
    }
    private let a = "11111111-1111-1111-1111-111111111111"
    private let b = "22222222-2222-2222-2222-222222222222"

    func testANameNobodyHasConfiguredIsNotADefault() {
        let configured = [VPNConnection(id: "a", name: "Office", status: .disconnected, kind: nil),
                          VPNConnection(id: "b", name: "Field", status: .disconnected, kind: nil)]
        let chosen = VPNListParser.defaultConnection(from: configured,
                                                     lastUsedName: "Attacker's Gateway")
        XCTAssertNotNil(chosen)
        XCTAssertTrue(configured.contains { $0.name == chosen?.name },
                      "a stored word became a connection this Mac does not have")
    }

    /// The same read from the far end: whatever the store says, the command the
    /// tool is given names something the tool listed.
    func testTheToggleOnlyEverSpellsAConfiguredName() {
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        settings.setLastUsed("Attacker's Gateway")
        let runner = FakeRunner()
        runner.listOutput = [header, row("Disconnected", a, "Office"), row("Disconnected", b, "Field")]
            .joined(separator: "\n")
        let engine = VPNEngine(settings: settings, runner: runner, apps: FakeApps(), work: .inline)

        engine.toggleDefault()

        let commands = runner.issued.filter { $0.first == "--nc" && $0.count >= 3 }
        XCTAssertTrue(commands.contains { $0[1] == "start" }, "precondition: something was asked for")
        XCTAssertTrue(commands.allSatisfy { ["Office", "Field"].contains($0[2]) },
                      "the tool was given a name out of the store: \(commands)")
    }
}
