// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine

/// **A rule is not a person, and only a person's gesture may reach the System
/// keychain.**
///
/// `vpnAppRules` is an unsealed plist string, decoded in `reloadRulesNow` at
/// `activate()`, so a forged rule names a configuration at a moment of the
/// attacker's choosing. A credential read that misses Helm's cache reaches
/// `/usr/bin/security` against `/Library/Keychains/System.keychain`, which
/// macOS gates behind a dialog attributed to `security`, not to Helm. So an
/// automatic connect may read Helm's own cache and gives up if the secret is
/// not there; only a person's press may prompt.
///
/// The rules stay unsealed because they are read during `activate()`
/// (Architecture/StoredSettings.md § Sealed settings).
/// `testTheRulesAreReadOnTheLaunchPath` checks that: if the read moves off the
/// launch path, sealing them becomes a question worth reopening.
final class ARuleMayNotSummonAKeychainDialogTests: XCTestCase {

    /// A store that remembers which keys were asked for, so a test can say
    /// *when* a setting is read rather than only what it answered.
    private final class KeyNotingStore: KeyValueStore, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Any] = [:]
        private var asked: [String] = []
        var keysRead: [String] { lock.lock(); defer { lock.unlock() }; return asked }
        func object(forKey key: String) -> Any? {
            lock.lock(); defer { lock.unlock() }
            asked.append(key)
            return values[key]
        }
        func set(_ value: Any?, forKey key: String) {
            lock.lock(); defer { lock.unlock() }
            values[key] = value
        }
    }

    /// **Why `vpnAppRules` is not sealed.** `ModuleHost.bootstrap` calls
    /// `activate()` from `applicationDidFinishLaunching`, and `activate()`
    /// reloads the rules, so a seal would put `SealKeyPort.key()`, a
    /// login-keychain round trip that is a dialog on an ad-hoc-signed bundle, on
    /// every launch (Architecture/StoredSettings.md § Sealed settings). The
    /// `IfWarm` shape does not rescue it: «not yet» here is auto-connect not
    /// firing at launch.
    func testTheRulesAreReadOnTheLaunchPath() {
        let backing = KeyNotingStore()
        let runner = FakeRunner()
        runner.listOutput = [header,
                             "* (Disconnected) \(id) IPSec \"Office\" [IPSec:1]"]
            .joined(separator: "\n")
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                                           backing: backing)),
                               runner: runner, credentials: FakeCreds(), apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        let beforeActivate = backing.keysRead.count

        engine.activate()
        defer { engine.deactivate() }

        let duringActivate = Array(backing.keysRead.dropFirst(beforeActivate))
        XCTAssertTrue(duringActivate.contains("module.vpn.vpnAppRules"),
                      "the rules are no longer read while the module comes up — sealing them "
                      + "may now be possible, so read § A seal needs a signature again "
                      + "instead of leaving this test failing: \(duringActivate)")
    }

    /// The other half: one verdict is one fetch of the key, every time, because
    /// whether a value is Helm's own is never cached (`SealKeyCache` caches the
    /// key alone).
    func testOneSealedReadIsOneTripToTheKeychain() {
        let probe = SealKeyProbe()
        let sealed = SettingGuard(keys: probe)

        _ = sealed.verdict(payload: Data("{}".utf8), mac: "")

        XCTAssertEqual(probe.reads, 1,
                       "a sealed read that costs nothing would make the refusal above "
                       + "groundless")
    }

    private let header = "Available network connection services:"
    private let id = "11111111-1111-1111-1111-111111111111"

    private func engine(_ runner: FakeRunner, _ creds: FakeCreds,
                        status: String = "Disconnected") -> VPNEngine {
        runner.listOutput = [header,
                             "* (\(status)) \(id) IPSec \"Office\" [IPSec:1]"].joined(separator: "\n")
        let engine = VPNEngine(settings: VPNSettings.inMemory(),
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
        XCTAssertTrue(runner.supplied.isEmpty,
                      "the secret it could not read honestly still reached the system")
    }

    /// The control: somebody pressing Connect is exactly the gesture the prompt
    /// is meant to sit behind, so that path still reads it.
    func testAPersonPressingConnectStillReachesTheSystemKeychain() {
        let creds = FakeCreds()
        creds.behindAPrompt["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: false)

        XCTAssertEqual(creds.asks.map(\.promptingAllowed), [true])
        XCTAssertEqual(runner.supplied.map(\.name), ["Office"],
                       "the connect a person asked for lost its secret")
        XCTAssertEqual(runner.supplied.first?.credentials.secret, "s")
    }

    /// A rule whose secret Helm has cached still connects: the gate is on the
    /// prompt, not on automatic connecting.
    func testARuleStillUsesHelmsOwnCache() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds).connect("Office", auto: true)

        XCTAssertEqual(runner.supplied.map(\.name), ["Office"], "an automatic connect stopped working")
        XCTAssertEqual(runner.supplied.first?.credentials.secret, "s")
    }

    /// **Nothing needs doing, so nothing is read.** A start on a tunnel already
    /// up is a no-op, and `activate()` replays `appLaunched` for every app
    /// already running, so a rule whose app runs all day would otherwise read the
    /// secret and hand it to the system at every launch of Helm.
    func testATunnelThatIsAlreadyUpIsNotWorthASecret() {
        let creds = FakeCreds()
        creds.map["Office"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let runner = FakeRunner()

        engine(runner, creds, status: "Connected").connect("Office", auto: true)

        XCTAssertTrue(creds.asks.isEmpty,
                      "the secret was read for a start that changes nothing: \(creds.asks)")
        XCTAssertTrue(runner.supplied.isEmpty,
                      "and it was handed to the system for a start that changes nothing")
    }
}
