// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A local unprivileged process could take somebody's VPN down, quietly.**
///
/// `RunningApps` reports bundle identifiers with no signature check, and a rule
/// fired on the identifier alone: `appTerminated` disconnects when the last mapped
/// id goes. So anybody could build a bundle carrying a matching
/// `CFBundleIdentifier`, launch it, quit it — and the tunnel went down. Worse, the
/// teardown was booked as a rule doing as it was asked, which cleared the books
/// that would have let the *later* real absence be reported as a drop.
///
/// A rule is bound to a signature now. The verdict is a value with a reason rather
/// than a `Bool`, because the settings row and the log each need to say which of
/// the four refusals happened.
final class ARuleIsBoundToAnIdentityTests: XCTestCase {

    private let real = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")
    private let forged = CodeIdentity(signingID: "com.attacker.thing", teamID: nil)

    private func rule(_ identity: CodeIdentity?) -> VPNAppRule {
        VPNAppRule(vpnName: "Office", identity: identity)
    }

    // MARK: - The rule

    func testTheRecordedIdentityLetsTheRealAppAct() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(real), running: real), .act)
    }

    func testABundleWearingTheSameIdentifierIsRefused() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(real), running: forged), .mismatch)
    }

    /// The team identifier is half the answer and cannot be claimed by somebody
    /// else's build: same signing identifier, different team, is not the same app.
    func testTheTeamIdentifierIsPartOfTheIdentity() {
        let sameNameOtherTeam = CodeIdentity(signingID: "com.example.app", teamID: "ZZZZZ99999")
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(real), running: sameNameOtherTeam), .mismatch)
    }

    /// An id that cannot be verified is treated as no rule.
    func testAnUnreadableRunningInstanceIsRefused() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(real), running: nil), .runningInstanceUnreadable)
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(real),
                                          running: CodeIdentity(signingID: nil, teamID: "ABCDE12345")),
                       .runningInstanceUnreadable)
    }

    // MARK: - The migration

    /// **Rules stored before this shipped carry no identity, and they refuse.**
    ///
    /// The alternative — verify by name until re-picked — leaves the whole
    /// vulnerability standing on every installation that already has rules, for
    /// ever, since nothing would ever make somebody re-pick. Refusing is the safe
    /// direction, and it is not silent: the row says the app has to be chosen
    /// again, and choosing it again records the identity without disturbing the
    /// rest of the rule.
    func testARuleFromBeforeIdentitiesExistedDoesNotFire() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(nil), running: real), .noIdentityRecorded)
    }

    /// A rule the person made for a bundle nobody signed. It is kept — they asked
    /// for it — and it does not fire, because an unsigned bundle's identity is
    /// something any other unsigned bundle can produce.
    func testARuleForAnUnsignedAppSaysSoRatherThanPretending() {
        let unsigned = CodeIdentity(signingID: nil, teamID: nil)
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(unsigned), running: unsigned),
                       .appNotSigned)
    }

    /// The two verdicts a settings row can draw are the two that need nothing
    /// running, which is what makes one function serve the page and the engine.
    func testTheRuleLevelVerdictsDoNotDependOnWhatIsRunning() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(nil), running: nil), .noIdentityRecorded)
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(CodeIdentity(signingID: "", teamID: nil)),
                                          running: nil), .appNotSigned)
    }

    // MARK: - What is on disk

    /// A stored rule from before the field existed still decodes. `JSONDecoder`
    /// gives up on the whole document rather than one field, so a throw here would
    /// cost the person every rule they have.
    func testRulesWrittenBeforeTheFieldExistedStillDecode() {
        let old = #"{"com.example.app":{"vpnName":"Office","connectOnLaunch":true,"disconnectOnQuit":true}}"#
        let decoded = VPNRules.decode(old)
        XCTAssertEqual(decoded["com.example.app"]?.vpnName, "Office")
        XCTAssertNil(decoded["com.example.app"]?.identity)
    }

    /// And the legacy `[bundleID: vpnName]` map, which is older still.
    func testTheOldestFormatStillDecodesToo() {
        let ancient = #"{"com.example.app":"Office"}"#
        XCTAssertEqual(VPNRules.decode(ancient)["com.example.app"]?.vpnName, "Office")
    }

    func testAnIdentityMakesItToDiskAndBack() {
        let encoded = VPNRules.encode(["com.example.app": rule(real)])
        XCTAssertEqual(VPNRules.decode(encoded)["com.example.app"]?.identity, real)
    }

    // MARK: - Picking an app, which is where an identity comes from

    func testPickingANewAppRecordsWhatItIsSignedAs() {
        let updated = VPNRules.adopting([(bundleID: "com.example.app", identity: real)],
                                        into: [:], defaultVPN: "Office")
        XCTAssertEqual(updated["com.example.app"]?.identity, real)
        XCTAssertEqual(updated["com.example.app"]?.vpnName, "Office")
    }

    /// **The repair path for a rule that predates identities.** Picking an app
    /// that already has a rule used to be ignored outright — `where rules[id] ==
    /// nil` — so "choose the app again" was advice nothing in the page could
    /// carry out. It records the identity and leaves every choice the person made
    /// exactly as it was.
    func testPickingAnAppThatAlreadyHasARuleRecordsTheIdentityAndChangesNothingElse() {
        let existing = VPNAppRule(vpnName: "Field", connectOnLaunch: false,
                                  disconnectOnQuit: true, identity: nil)
        let updated = VPNRules.adopting([(bundleID: "com.example.app", identity: real)],
                                        into: ["com.example.app": existing],
                                        defaultVPN: "Office")
        XCTAssertEqual(updated["com.example.app"],
                       VPNAppRule(vpnName: "Field", connectOnLaunch: false,
                                  disconnectOnQuit: true, identity: real))
    }

    /// An app nobody signed still gets its rule — the person asked for it — and
    /// the recorded identity says what was found, which is what makes
    /// `.appNotSigned` a different answer from `.noIdentityRecorded`.
    func testPickingAnUnsignedAppRecordsThatItWasUnsigned() {
        let unsigned = CodeIdentity(signingID: nil, teamID: nil)
        let updated = VPNRules.adopting([(bundleID: "com.example.app", identity: unsigned)],
                                        into: [:], defaultVPN: "Office")
        XCTAssertEqual(updated["com.example.app"]?.identity, unsigned)
        XCTAssertEqual(VPNRuleTrust.judge(rule: updated["com.example.app"]!, running: unsigned),
                       .appNotSigned)
    }

    /// A bundle the picker could not read at all is not a rule that silently
    /// never fires: nothing is recorded for it.
    func testAnUnreadableBundleGetsNoRule() {
        XCTAssertTrue(VPNRules.adopting([(bundleID: "com.example.app", identity: nil)],
                                        into: [:], defaultVPN: "Office").isEmpty)
    }
}
