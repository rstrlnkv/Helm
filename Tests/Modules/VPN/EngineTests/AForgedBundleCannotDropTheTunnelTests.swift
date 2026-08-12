// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// The attack, end to end, through the engine: launch a bundle carrying a mapped
/// `CFBundleIdentifier`, quit it, and watch the tunnel go down.
///
/// It is written against the engine rather than against `VPNRuleTrust` because the
/// pure rule can be perfect and reach nothing: the identity is checked at
/// **launch**, and the quit is refused by consequence — `VPNAutoConnectCore` only
/// undoes launches it recorded. That is one gate rather than two, and it is the
/// only place a check is possible at all, since at quit time there is no longer a
/// bundle to read.
final class AForgedBundleCannotDropTheTunnelTests: XCTestCase {

    private let bundleID = "com.example.app"
    private let real = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")
    private let forged = CodeIdentity(signingID: "com.attacker.thing", teamID: nil)
    private let header = "Available network connection services:"
    private let serviceID = "11111111-1111-1111-1111-111111111111"

    private func row(_ status: String) -> String {
        "* (\(status)) \(serviceID) IPSec \"Office\" [IPSec:1]"
    }

    /// A module with one rule, its tunnel up, and Helm holding it — the state a
    /// quit is supposed to undo.
    ///
    /// **The caller must keep what this returns.** `apps.startObserving`'s closure
    /// holds the engine weakly, so an engine nobody retains is deallocated the
    /// moment this returns and `fire()` reaches nothing — every assertion about
    /// something *not* happening would then pass with the whole gate deleted. It
    /// cost one debugging round here, which is the trap ARCHITECTURE.md § A check
    /// that cannot fail describes: assert first that the subject happened.
    private func holding(_ apps: FakeApps, _ runner: FakeRunner,
                         identity: CodeIdentity?) -> VPNEngine {
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        settings.setRulesJSON(VPNRules.encode(
            [bundleID: VPNAppRule(vpnName: "Office", identity: identity)]))
        runner.listOutput = [header, row("Disconnected")].joined(separator: "\n")
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps, work: .inline)
        engine.activate()
        return engine
    }

    /// The real app launches, Helm raises the tunnel, and the forged bundle then
    /// launches and quits.
    func testABundleThatIsNotTheAppCannotTakeTheTunnelDown() {
        let apps = FakeApps()
        let runner = FakeRunner()
        apps.identities[bundleID] = real
        apps.bundleIDs = [bundleID]
        let engine = holding(apps, runner, identity: real)
        runner.listOutput = [header, row("Connected")].joined(separator: "\n")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("Office"),
                      "precondition: the rule fired and Helm is holding the tunnel")

        // The real app quits and the forged one takes its place, so the set of
        // running identifiers never changes — then the forged one quits.
        apps.identities[bundleID] = forged
        apps.bundleIDs = []
        apps.fire()

        let stops = runner.issued.filter { $0.count > 1 && $0[1] == "stop" }
        XCTAssertEqual(stops.count, 1,
                       "precondition: a quit does take the tunnel down, so the assertions "
                       + "below are about who was allowed to cause it")
    }

    /// The forged bundle on its own: it launches, nothing happens, it quits,
    /// nothing happens. This is the whole finding.
    func testAForgedLaunchRaisesNothingAndItsQuitTakesNothingDown() {
        let apps = FakeApps()
        let runner = FakeRunner()
        apps.identities[bundleID] = forged
        let engine = holding(apps, runner, identity: real)

        apps.bundleIDs = [bundleID]
        apps.fire()
        XCTAssertTrue(runner.issued.filter { $0.count > 1 && $0[1] == "start" }.isEmpty,
                      "a bundle wearing the identifier raised the tunnel")

        apps.bundleIDs = []
        apps.fire()
        XCTAssertTrue(runner.issued.filter { $0.count > 1 && $0[1] == "stop" }.isEmpty,
                      "a bundle wearing the identifier took the tunnel down: \(runner.issued)")
        XCTAssertNil(engine.lastAutomation,
                     "…and the app announced it as a rule doing as it was asked")
    }

    /// The control, and it is not optional: the real app still works. Without it
    /// every assertion above passes on a module whose rules never fire.
    func testTheRealAppStillRaisesAndLowersTheTunnel() {
        let apps = FakeApps()
        let runner = FakeRunner()
        apps.identities[bundleID] = real
        let engine = holding(apps, runner, identity: real)

        apps.bundleIDs = [bundleID]
        apps.fire()
        XCTAssertFalse(runner.issued.filter { $0.count > 1 && $0[1] == "start" }.isEmpty,
                       "the app the person chose no longer raises its tunnel")

        runner.listOutput = [header, row("Connected")].joined(separator: "\n")
        engine.refresh()
        apps.bundleIDs = []
        apps.fire()
        XCTAssertFalse(runner.issued.filter { $0.count > 1 && $0[1] == "stop" }.isEmpty,
                       "…and quitting it no longer takes it down")
    }

    /// A rule stored before identities existed refuses, and says so in the log —
    /// a rule that has quietly stopped firing is the failure ARCHITECTURE.md § A
    /// rule that is being ignored is not a rule that is quiet is about.
    func testARuleWithNoRecordedIdentityRefusesAndSaysSo() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        let apps = FakeApps()
        let runner = FakeRunner()
        apps.identities[bundleID] = real
        let engine = holding(apps, runner, identity: nil)

        apps.bundleIDs = [bundleID]
        apps.fire()

        XCTAssertTrue(runner.issued.filter { $0.count > 1 && $0[1] == "start" }.isEmpty,
                      "a rule with no identity on record fired anyway")
        let lines = HelmLog.shared.recentEntries().filter { $0.category == "vpn" }
        XCTAssertTrue(lines.contains { $0.message.contains("noIdentityRecorded") },
                      "nothing in the log says why the rule did nothing: \(lines.map(\.message))")
        XCTAssertFalse(lines.contains { $0.message.contains(bundleID) },
                       "and the bundle id reached the diagnostic file in clear")
        XCTAssertNil(engine.lastAutomation)
    }

    /// The seeding path at launch is the same gate. `activate()` replays
    /// `appLaunched` for everything already running, and a gate on only the live
    /// route would let a forged bundle that was started *before* Helm through.
    ///
    /// Both directions in one test, because the assertion that matters is an
    /// absence: with the real identity the same seeding does raise the tunnel.
    func testTheLaunchSeedingIsGatedToo() {
        for (identity, expected) in [(real, 1), (forged, 0)] {
            let apps = FakeApps()
            let runner = FakeRunner()
            apps.identities[bundleID] = identity
            apps.bundleIDs = [bundleID]
            let engine = holding(apps, runner, identity: real)

            XCTAssertEqual(runner.issued.filter { $0.count > 1 && $0[1] == "start" }.count,
                           expected,
                           "a bundle already running when Helm started, signed as "
                           + "\(identity.signingID ?? "nothing")")
            withExtendedLifetime(engine) {}
        }
    }
}
