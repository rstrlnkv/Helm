// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A refusal has a verb, and this value carried none.**
///
/// `VPNFailure` held a name and a reason, so a `--nc stop` the tool would not
/// perform reached the page as the only sentence the page could draw: «macOS
/// refused to connect «Office»» — read by the person who had just asked to bring
/// that tunnel *down*, about a tunnel that is still up and still carrying
/// everything this Mac sends. The same class of sentence
/// `VPNAutomation.Kind.dropped` exists to warn about, produced by the app itself,
/// and invisible to every test because the value had no verb in it to be wrong.
final class ARefusalRemembersItsVerbTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(
                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                  runner: runner, apps: FakeApps(),
                  interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                  work: .inline)
    }

    private func runner(refusing text: String) -> FakeRunner {
        let runner = FakeRunner()
        runner.listOutput = "(Connected) \(uuid) IPSec \"Office\""
        runner.reply = text
        return runner
    }

    func testAStopTheToolRefusedIsRecordedAsAStop() {
        let e = engine(runner(refusing: "cannot stop Office: resource busy"))

        e.disconnect("Office")

        XCTAssertEqual(e.lastFailure?.reason, .refused, "precondition: the refusal was read")
        XCTAssertEqual(e.lastFailure?.verb, .disconnect,
                       "the person asked to bring a tunnel down, the tool would not, and the "
                       + "page tells them Helm could not connect it")
    }

    /// The control, without which the assertion above could be bought by a module
    /// that reports every command as a stop.
    func testAConnectTheToolRefusedIsStillRecordedAsAConnect() {
        let e = engine(runner(refusing: "cannot start Office: resource busy"))

        e.connect("Office")

        XCTAssertEqual(e.lastFailure?.verb, .connect)
    }
}
