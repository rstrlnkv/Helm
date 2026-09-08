// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
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
///
/// **That refusal was a sentence with nothing under it until 2026-09-08**, which
/// is the shape this house names: a promise written in prose is a rule nobody
/// can break loudly. `testTheRulesAreReadOnTheLaunchPath` is the sentence made
/// checkable — it reads the *keys* `activate()` asks the store for. The day that
/// read moves off the launch path the test fails, and that is the day sealing
/// them becomes a question worth reopening rather than a change that puts a
/// keychain dialog in front of every launch.
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

    /// **Why `vpnAppRules` is not sealed, as a measurement rather than a
    /// sentence.** `ModuleHost.bootstrap` runs from
    /// `applicationDidFinishLaunching` and calls `activate()` on every enabled
    /// module; `activate()` reloads the rules. So a seal over this key is a
    /// `SettingGuard.verdict` on the launch path, and a verdict is one
    /// `SealKeyPort.key()` — a login-keychain round trip that, on a bundle signed
    /// `--sign -`, is an authorization dialog rather than data, at every launch
    /// after every install (ARCHITECTURE.md § A seal needs a signature).
    ///
    /// The `IfWarm` shape the other two sealed settings use does not rescue it:
    /// `disabledScans` and `keepPolicy` are read when a page opens or a scan
    /// starts, and answering «not yet» there costs a redraw. Answering «not yet»
    /// here is auto-connect not firing at launch, which is the feature.
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

    /// The other half of the same measurement, so the sentence above does not
    /// rest on «a seal is presumably expensive»: one verdict is one fetch of the
    /// key, every time, because whether a value is Helm's own is a live fact and
    /// is never cached (`SealKeyCache` caches the key alone).
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
