// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **The name is the only handle this module has, and it is not unique.**
///
/// `scutil --nc start` takes a name, so the name is what a rule stores and what
/// the two commands are spelled with — but `VPNConnection` carries an `id`
/// precisely because the name does not identify anything. macOS lets two service
/// configurations carry one display name (the Service Name field in Network
/// Settings is free text, and nothing there is unique-constrained), and every
/// book this engine keeps — `_autoConnected`, `_cameUp`, `up`, `status(_:)`,
/// `VPNAppRule.vpnName` — is keyed by that name.
///
/// The two failures below are what that costs, and they run in opposite
/// directions: a drop that is never reported, and a name whose spelling the
/// parser silently changes so that two configurations become one.
final class ANameIsNotAnIdentityTests: XCTestCase {

    private let clock = TestClock()

    private var at: Date { clock.now }

    private func row(_ status: String, _ id: String, _ name: String) -> String {
        "* (\(status)) \(id) IPSec \"\(name)\" [IPSec:1]"
    }

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        let clock = self.clock
        return VPNEngine(settings: VPNSettings(store: NamespacedStore(
                            namespace: "vpn", backing: InMemoryKeyValueStore())),
                         runner: runner, apps: FakeApps(),
                         interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                         now: { clock.now }, work: .inline)
    }

    private let a = "11111111-1111-1111-1111-111111111111"
    private let b = "22222222-2222-2222-2222-222222222222"
    private let header = "Available network connection services:"

    // MARK: - The drop nobody is told about

    /// Two configurations called «Office»: the one a rule raised, and a second the
    /// person keeps for a different gateway. The rule's tunnel falls over; the
    /// other one is up at that moment for its own reasons.
    ///
    /// `up` is a `Set<String>` of names, so «Office» is in it — and the drop
    /// detection asks nothing else. The person is never told that the tunnel their
    /// rule was holding went away, which is the one event this module posts a
    /// system notification for, and Helm's own dot stays green over a rule that
    /// has stopped working.
    ///
    /// The control below it is what makes this a finding rather than an assertion
    /// that drops are never reported at all.
    func testADropIsStillADropWhenANamesakeIsUp() {
        let runner = FakeRunner()
        runner.listOutput = [header,
                             row("Disconnected", a, "Office"),
                             row("Disconnected", b, "Office")].joined(separator: "\n")
        let e = engine(runner)

        e.connect("Office", auto: true)
        runner.listOutput = [header,
                             row("Connected", a, "Office"),
                             row("Disconnected", b, "Office")].joined(separator: "\n")
        e.refresh()
        e.clearLastAutomationForTesting()

        // The one a rule raised goes; the namesake comes up by itself.
        runner.listOutput = [header,
                             row("Disconnected", a, "Office"),
                             row("Connected", b, "Office")].joined(separator: "\n")
        e.refresh()
        // The drop is held for the settle window now; a namesake being up must
        // not shorten or cancel it, which is what this test is about.
        clock.advance(VPNDropSettle.window)
        e.refresh()

        XCTAssertEqual(e.lastAutomation?.kind, .dropped,
                       "the tunnel a rule was holding fell over and the module said nothing, "
                       + "because a different configuration of the same name happened to be up")
    }

    /// The control for the test above: with no namesake, the same fall is reported.
    /// Without this, a module that had stopped reporting drops entirely would make
    /// the assertion above look like a narrow bug instead of a dead feature.
    func testTheSameFallIsReportedWithNoNamesake() {
        let runner = FakeRunner()
        runner.listOutput = [header, row("Disconnected", a, "Office")].joined(separator: "\n")
        let e = engine(runner)

        e.connect("Office", auto: true)
        runner.listOutput = [header, row("Connected", a, "Office")].joined(separator: "\n")
        e.refresh()
        e.clearLastAutomationForTesting()
        runner.listOutput = [header, row("Disconnected", a, "Office")].joined(separator: "\n")
        e.refresh()
        clock.advance(VPNDropSettle.window)
        e.refresh()

        XCTAssertEqual(e.lastAutomation?.kind, .dropped, "precondition: a drop is reported at all")
    }

    // MARK: - The name the parser rewrote

    /// **A quote in the name, which the Service Name field accepts.**
    ///
    /// `between(line, "\"", "\"")` takes the first quoted run, so «Office "B"»
    /// comes back as «Office » — a name `scutil --nc start` will answer `No
    /// service` to for ever, and one that two different configurations share.
    ///
    /// The assertion is written so that either repair passes: the line may be
    /// skipped the way an empty name already is (a name we cannot read is not a
    /// connection), or read to the last quote. What must not happen is a
    /// *silently different* name, because the name is the command.
    func testANameContainingAQuoteIsNotSilentlyTruncated() {
        for spelling in ["Office \"B\"", "Office \\\"B\\\""] {
            let parsed = VPNListParser.parseList(row("Disconnected", a, spelling))
            guard let only = parsed.first else { continue }   // skipping it is a fair answer
            XCTAssertEqual(parsed.count, 1, "one line, one connection")
            XCTAssertEqual(only.name, spelling,
                           "the parser handed back «\(only.name)» for a configuration called "
                           + "«\(spelling)» — every command this module sends is spelled with "
                           + "that string")
        }
    }

    /// The consequence, stated on its own so it cannot be argued away as cosmetic:
    /// two configurations that differ become one name. The grid draws two cards,
    /// the rule picker offers two entries with one tag, and both of this engine's
    /// books hold a single key for the pair.
    func testTwoConfigurationsDoNotCollapseIntoOneName() {
        let parsed = VPNListParser.parseList([header,
                                              row("Connected", a, "Office \"A\""),
                                              row("Disconnected", b, "Office \"B\"")]
            .joined(separator: "\n"))

        XCTAssertEqual(Set(parsed.map(\.name)).count, parsed.count,
                       "two configurations came back under one name: "
                       + "\(parsed.map(\.name)) — one of them is unreachable and the other "
                       + "answers for both")
    }

    /// A name that is nothing but spaces walks past the empty-name guard, which
    /// was written for exactly this failure one character earlier: a row with no
    /// readable label whose verb sends `--nc start "   "`.
    func testANameOfNothingButSpacesIsNoMoreANameThanAnEmptyOne() {
        XCTAssertTrue(VPNListParser.parseList(row("Disconnected", a, "   ")).isEmpty,
                      "a card with a blank label, and a button that can only fail")
    }

    /// The identity two SwiftUI `ForEach`es are keyed by must not repeat.
    /// `VPNConnection.id` falls back to the *name* when no UUID-shaped token is on
    /// the line, so the fallback turns the identity question back into the one
    /// this whole file is about — and duplicate ids in a `ForEach` are undefined,
    /// not merely ugly.
    func testTheIdentityOfTwoConnectionsIsNeverTheSame() {
        let parsed = VPNListParser.parseList([header,
                                              "* (Connected) IPSec \"Office\" [IPSec:1]",
                                              "* (Disconnected) IPSec \"Office\" [IPSec:1]"]
            .joined(separator: "\n"))

        XCTAssertEqual(Set(parsed.map(\.id)).count, parsed.count,
                       "two rows share one `Identifiable` id: \(parsed.map(\.id))")
    }
}
