// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// A rule bound to an identity can refuse, and a rule that refuses in silence is
/// the failure ARCHITECTURE.md § A rule that is being ignored is not a rule that is
/// quiet is about — the row goes on showing the app, the VPN and the timing, and
/// nothing fires.
///
/// Two of the five verdicts belong to the rule itself and can be drawn from the
/// page with nothing running; the other three depend on what is running at that
/// instant, which the page does not know and must not guess at.
@MainActor
final class ARuleThatCannotFireSaysSoTests: XCTestCase {

    func testTheTwoRuleLevelRefusalsEachHaveTheirOwnSentence() {
        let repick = VPNStr.ruleTrustNote(.noIdentityRecorded)
        let unsigned = VPNStr.ruleTrustNote(.appNotSigned)
        XCTAssertNotNil(repick)
        XCTAssertNotNil(unsigned)
        XCTAssertNotEqual(repick, unsigned,
                          "a rule that needs the app chosen again and one for an app nobody "
                          + "signed were given the same advice, and only one of them can act on it")
    }

    /// The row draws nothing for a rule that is fine, and nothing for the two
    /// verdicts that are about this instant rather than about the rule: a note
    /// saying "the running copy could not be read" under a rule whose app is not
    /// running at all would be a page inventing a problem.
    func testARuleThatIsFineAndAnInstantThatIsNotTheRuleSayNothing() {
        XCTAssertNil(VPNStr.ruleTrustNote(.act))
        XCTAssertNil(VPNStr.ruleTrustNote(.runningInstanceUnreadable))
        XCTAssertNil(VPNStr.ruleTrustNote(.mismatch))
    }

    /// And the note the page actually asks for comes from the rule, so a rule
    /// stored before identities existed is the one that shows it.
    func testTheNoteForAStoredRuleComesFromItsOwnIdentity() {
        let legacy = VPNAppRule(vpnName: "Office")
        XCTAssertEqual(VPNStr.ruleTrustNote(VPNRuleTrust.judge(rule: legacy, running: nil)),
                       VPNStr.ruleTrustNote(.noIdentityRecorded))

        let bound = VPNAppRule(vpnName: "Office",
                               identity: CodeIdentity(signingID: "com.example.app", teamID: "T"))
        XCTAssertNil(VPNStr.ruleTrustNote(VPNRuleTrust.judge(rule: bound, running: nil)),
                     "a rule that is bound and whose app is simply not running has nothing wrong "
                     + "with it")
    }
}
