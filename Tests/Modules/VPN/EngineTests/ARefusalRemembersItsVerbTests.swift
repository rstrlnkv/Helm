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
///
/// This half is what the engine recorded. The sentence that reads it is
/// `ARefusedStopIsNotARefusedConnectTests`, one target over, where `VPNStr` is.
final class ARefusalRemembersItsVerbTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        VPNEngine(settings: VPNSettings(store: NamespacedStore(
                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                  runner: runner, apps: FakeApps(), work: .inline)
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

    /// A payload from a build that predates the field still decodes, and the
    /// **whole** payload with it: a synthesised `Decodable` throws on the missing
    /// key, and `JSONDecoder` then gives up on the document rather than on the
    /// field — so the page would lose every connection it draws over one word
    /// (CLAUDE.md § a `defaulted` property on a `Codable` payload).
    func testAFailureFromBeforeTheVerbStillDecodesWithThePayloadAroundIt() throws {
        let legacy = Data("""
        {"connections":[{"id":"1","name":"Office","status":"connected"}],
         "autoConnected":[],"defaultName":"Office",
         "lastFailure":{"name":"Office","reason":"refused"}}
        """.utf8)

        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self, from: legacy)

        XCTAssertEqual(payload.connections.count, 1,
                       "one missing word cost the page everything else in the payload")
        XCTAssertEqual(payload.lastFailure?.verb, .connect,
                       "the only sentence such a build could draw was the connect one")
    }
}
