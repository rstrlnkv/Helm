// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// **The name is the only handle this module has, and it is not unique.**
///
/// `scutil --nc start` takes a name, so the name is what a rule stores and what
/// the commands are spelled with, but macOS lets two service configurations
/// carry one display name (the Service Name field is free text). Two failures
/// follow, in opposite directions: a drop never reported because a namesake is
/// up, and a name the parser rewrites so that two configurations become one.
final class ANameIsNotAnIdentityTests: XCTestCase {

    private let clock = TestClock()

    private func row(_ status: String, _ id: String, _ name: String) -> String {
        "* (\(status)) \(id) IPSec \"\(name)\" [IPSec:1]"
    }

    private func engine(_ runner: FakeRunner) -> VPNEngine {
        let clock = self.clock
        return VPNEngine(settings: VPNSettings.inMemory(),
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
    /// The drop must still be announced: it is the one event this module posts
    /// a system notification for.
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
        // The drop is held for the settle window; a namesake being up must not
        // shorten or cancel it.
        clock.advance(VPNDropSettle.window)
        e.refresh()

        XCTAssertEqual(e.lastAutomation?.kind, .dropped,
                       "the tunnel a rule was holding fell over and the module said nothing, "
                       + "because a different configuration of the same name happened to be up")
    }

    /// The control for the test above: with no namesake, the same fall is reported.
    func testTheSameFallIsReportedWithNoNamesake() {
        let runner = FakeRunner(list: [header, row("Disconnected", a, "Office")].joined(separator: "\n"))
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
    /// The line may be skipped, as an empty name is, or read to the last quote.
    /// What must not happen is a *silently different* name, such as «Office »
    /// from the first quoted run, because the name is the command.
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

    /// Two configurations that differ must not become one name: the rule picker
    /// would offer two entries with one tag, and the engine's books one key.
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

    /// A name of nothing but spaces is no more a name than an empty one: a row
    /// with no readable label whose verb sends `--nc start "   "`.
    func testANameOfNothingButSpacesIsNoMoreANameThanAnEmptyOne() {
        XCTAssertTrue(VPNListParser.parseList(row("Disconnected", a, "   ")).isEmpty,
                      "a card with a blank label, and a button that can only fail")
    }

    /// The identity two SwiftUI `ForEach`es are keyed by must not repeat.
    /// `VPNConnection.id` falls back to `<name>#<namesakes before it>` when no
    /// UUID-shaped token is on the line; duplicate ids in a `ForEach` are
    /// undefined behaviour.
    func testTheIdentityOfTwoConnectionsIsNeverTheSame() {
        let parsed = VPNListParser.parseList([header,
                                              "* (Connected) IPSec \"Office\" [IPSec:1]",
                                              "* (Disconnected) IPSec \"Office\" [IPSec:1]"]
            .joined(separator: "\n"))

        XCTAssertEqual(Set(parsed.map(\.id)).count, parsed.count,
                       "two rows share one `Identifiable` id: \(parsed.map(\.id))")
    }
}
