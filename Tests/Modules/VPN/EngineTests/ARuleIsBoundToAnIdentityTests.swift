// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **A rule is bound to a code signature, not to a bundle identifier.**
///
/// `RunningApps` reports bundle identifiers with no signature check, so any
/// local unprivileged process could launch and quit a bundle carrying a matching
/// `CFBundleIdentifier` and take the tunnel down, booked as a rule doing as it
/// was asked. The verdict is a value with a reason rather than a `Bool`, because
/// the log says which of the four refusals happened.
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

    /// **A rule with no recorded identity refuses.** Trusting the name until the
    /// app is picked again would leave the hole open for ever, since nothing makes
    /// anybody pick again. The refusal is logged, and choosing the app again
    /// records the identity without disturbing the rest of the rule.
    func testARuleFromBeforeIdentitiesExistedDoesNotFire() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(nil), running: real), .noIdentityRecorded)
    }

    /// A rule for a bundle nobody signed is kept but does not fire: any other
    /// unsigned bundle can produce the same identity.
    func testARuleForAnUnsignedAppSaysSoRatherThanPretending() {
        let unsigned = CodeIdentity(signingID: nil, teamID: nil)
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(unsigned), running: unsigned),
                       .appNotSigned)
    }

    /// The two rule-level verdicts are the two that need nothing running.
    func testTheRuleLevelVerdictsDoNotDependOnWhatIsRunning() {
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(nil), running: nil), .noIdentityRecorded)
        XCTAssertEqual(VPNRuleTrust.judge(rule: rule(CodeIdentity(signingID: "", teamID: nil)),
                                          running: nil), .appNotSigned)
    }

    // MARK: - What is on disk

    /// A stored rule without the field still decodes: `JSONDecoder` gives up on
    /// the whole document, so a throw would cost every rule.
    func testRulesWrittenBeforeTheFieldExistedStillDecode() {
        let old = #"{"com.example.app":{"vpnName":"Office","connectOnLaunch":true,"disconnectOnQuit":true}}"#
        let decoded = VPNRules.decode(old)
        XCTAssertEqual(decoded["com.example.app"]?.vpnName, "Office")
        XCTAssertNil(decoded["com.example.app"]?.identity)
    }

    /// And the legacy `[bundleID: vpnName]` map.
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

    /// **The repair path for a rule with no identity.** Picking an app that
    /// already has a rule records the identity and leaves every choice the person
    /// made exactly as it was.
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
