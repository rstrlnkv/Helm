// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// A row of `scutil --nc list` that carries no service id gets one made up, and
/// the only other thing such a row carries is its **place in the list** — so the
/// made-up id changed whenever the list was printed in a different order.
///
/// `_cameUp` is keyed by id, and its whole purpose is to tell "this one came up
/// and then went" from "this one is not up yet": an id that changes under a
/// stationary tunnel reads as the tunnel disappearing. The person gets the one
/// banner this module interrupts them for — a drop — for a tunnel that never
/// went anywhere.
final class AnIdentityIsNotAPositionTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_000_000)
    private let header = "Available network connection services:"

    /// No UUID-shaped token, which is the case the fallback id exists for.
    private func row(_ status: String, _ name: String) -> String {
        "* (\(status)) IPSec \"\(name)\" [IPSec:1]"
    }

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        let at = self.at
        return VPNEngine(settings: VPNSettings(store: NamespacedStore(
                            namespace: "vpn", backing: InMemoryKeyValueStore())),
                         runner: runner, apps: FakeApps(), now: { at }, work: .inline)
    }

    func testARowKeepsItsIdentityWhenTheListIsPrintedInAnotherOrder() {
        let first = VPNListParser.parseList([header,
                                             row("Connected", "Office"),
                                             row("Disconnected", "Field")].joined(separator: "\n"))
        let shuffled = VPNListParser.parseList([header,
                                                row("Disconnected", "Field"),
                                                row("Connected", "Office")].joined(separator: "\n"))

        let before = Dictionary(uniqueKeysWithValues: first.map { ($0.name, $0.id) })
        let after = Dictionary(uniqueKeysWithValues: shuffled.map { ($0.name, $0.id) })
        XCTAssertEqual(before, after,
                       "the same two configurations came back with different identities "
                       + "because the tool listed them the other way round")
    }

    /// The identity still has to be an identity: two configurations of one name
    /// and no service id are two rows, and a `ForEach` keyed on a repeated id is
    /// undefined.
    func testTwoNamesakesWithoutServiceIdsAreStillTwoIdentities() {
        let parsed = VPNListParser.parseList([header,
                                              row("Connected", "Office"),
                                              row("Disconnected", "Office")].joined(separator: "\n"))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(Set(parsed.map(\.id)).count, 2,
                       "two rows share one `Identifiable` id: \(parsed.map(\.id))")
    }

    /// The harm, at the level it reaches the person: the list is re-read, the
    /// order has changed, nothing has moved — and the module announces a drop.
    func testAReorderedListIsNotADrop() {
        let runner = FakeRunner()
        runner.listOutput = [header,
                             row("Disconnected", "Office"),
                             row("Disconnected", "Field")].joined(separator: "\n")
        let e = engine(runner)

        e.connect("Office", auto: true)
        runner.listOutput = [header,
                             row("Connected", "Office"),
                             row("Disconnected", "Field")].joined(separator: "\n")
        e.refresh()
        e.clearLastAutomationForTesting()

        // Same two configurations, same states, printed the other way round.
        runner.listOutput = [header,
                             row("Disconnected", "Field"),
                             row("Connected", "Office")].joined(separator: "\n")
        e.refresh()

        XCTAssertNil(e.lastAutomation,
                     "a tunnel that never went was reported as a drop, because its identity "
                     + "was its place in the list")
        XCTAssertTrue(e.autoConnected.contains("Office"),
                      "and the module stopped believing it was holding the tunnel it is holding")
    }
}
