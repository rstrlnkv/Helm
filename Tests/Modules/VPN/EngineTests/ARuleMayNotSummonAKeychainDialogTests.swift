// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A rule is not a person, and only a person's gesture may reach the System
/// keychain.**
///
/// `vpnAppRules` is an unsealed plist string, decoded in `reloadRulesNow` — which
/// `activate()` calls at launch. A forged rule therefore names a configuration of
/// the attacker's choosing at a moment of the attacker's choosing, and the
/// credential read that follows reaches `/usr/bin/security` against
/// `/Library/Keychains/System.keychain` on a cache miss. macOS gates that read
/// behind a dialog — one attributed to `security`, not to Helm — so the rule can
/// summon an authorization prompt in front of somebody who did nothing.
///
/// Sealing the rules is the wrong repair and is refused: they are read during
/// `activate()`, and ARCHITECTURE.md § A seal needs a signature records what a
/// keychain read at launch costs on this ad-hoc-signed bundle. What is gated
/// instead is the prompt itself: an automatic connect may read Helm's own cache
/// and must give up if the secret is not there.
final class ARuleMayNotSummonAKeychainDialogTests: XCTestCase {

    private let header = "Available network connection services:"
    private let id = "11111111-1111-1111-1111-111111111111"

    private func engine(_ runner: FakeRunner, _ creds: FakeCreds,
                        status: String = "Disconnected") -> VPNEngine {
        runner.listOutput = [header,
                             "* (\(status)) \(id) IPSec \"Office\" [IPSec:1]"].joined(separator: "\n")
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, credentials: creds, apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.refresh()
        return engine
    }

    func testARuleMayNotAskForAPromptableSecret() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: true)

        XCTAssertEqual(creds.asks.map(\.promptingAllowed), [false],
                       "a rule was allowed to reach the System keychain, which is a dialog")
        let start = runner.issued.first { $0.count > 1 && $0[1] == "start" } ?? []
        XCTAssertFalse(start.contains("--secret"),
                       "the secret it could not read honestly still reached the argument list")
    }

    /// The control: somebody pressing Connect is exactly the gesture the prompt
    /// is meant to sit behind, so that path still reads it.
    func testAPersonPressingConnectStillReachesTheSystemKeychain() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds).connect("Office")

        XCTAssertEqual(creds.asks.map(\.promptingAllowed), [true])
        let start = runner.issued.first { $0.count > 1 && $0[1] == "start" } ?? []
        XCTAssertTrue(start.contains("--secret"), "the connect a person asked for lost its secret")
    }

    /// And a rule whose secret Helm has already cached works as it always did:
    /// the gate is on the prompt, not on automatic connecting.
    func testARuleStillUsesHelmsOwnCache() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: true)

        let start = runner.issued.first { $0.count > 1 && $0[1] == "start" } ?? []
        XCTAssertTrue(start.contains("--secret"), "an automatic connect stopped working")
    }

    /// **Nothing needs doing, so nothing is read.** `--nc start` on a tunnel that
    /// is already up is a no-op the code says so about itself, and `activate()`
    /// replays `appLaunched` for every app already running — so a rule whose app
    /// runs all day re-read the secret at every launch of Helm and put it in an
    /// argument list every time, for nothing.
    func testATunnelThatIsAlreadyUpIsNotWorthASecret() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds, status: "Connected").connect("Office", auto: true)

        XCTAssertTrue(creds.asks.isEmpty,
                      "the secret was read for a start that changes nothing: \(creds.asks)")
        let start = runner.issued.first { $0.count > 1 && $0[1] == "start" } ?? []
        XCTAssertFalse(start.contains("--secret"),
                       "and it was written into an argument list every other process can read")
    }
}
