// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The engine publishes why a rule will not fire; the page must say it.** The
/// engine half is `ARuleThatWillNotFireSaysSoTests`; these are the two UI hops it
/// cannot reach: the verdict -> sentence mapping (a nil there is an unattended rule
/// that silently does nothing again) and the view model carrying the payload.
@MainActor
final class ARefusedRuleIsDrawnWithItsNoteTests: XCTestCase {

    /// Every verdict `refusal(of:)` can return has a sentence in every language, and
    /// the two reasons read differently.
    func testEveryRuleLevelRefusalHasASentenceInEveryLanguage() {
        let unsignedRule = VPNAppRule(vpnName: "Office",
                                      identity: CodeIdentity(signingID: nil, teamID: nil))
        let unrecordedRule = VPNAppRule(vpnName: "Office", identity: nil)
        let reasons = [VPNRuleTrust.refusal(of: unsignedRule), VPNRuleTrust.refusal(of: unrecordedRule)]
        XCTAssertEqual(reasons.compactMap { $0 }.count, 2, "precondition: both rules are refused")
        AppLanguage.each { language in
            let sentences = reasons.compactMap { $0 }.map {
                VPNStr.ruleWillNotFire($0, language: language) }
            for sentence in sentences {
                XCTAssertNotNil(sentence, "no note for a refused rule in \(language)")
                XCTAssertFalse((sentence ?? "").isEmpty)
                XCTAssertFalse((sentence ?? "").hasPrefix("ruleWillNotFire"),
                               "an unresolved key in \(language): \(sentence ?? "")")
            }
            XCTAssertNotEqual(sentences[0], sentences[1], "one sentence for two reasons in \(language)")
        }
    }

    /// The model hands the page what the engine published, and clears it.
    func testTheModelCarriesAndWithdrawsTheRefusals() async {
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work)
        let office = VPNConnection(id: "A1", name: "Office", status: .disconnected, kind: "IKEv2")
        work.say(VPNEngine.StatePayload(connections: [office], autoConnected: [],
                                        lastAutomation: nil,
                                        ruleRefusals: ["com.example.app": .appNotSigned]))
        for _ in 0..<500 where model.ruleRefusals.isEmpty { await Task.yield() }
        XCTAssertEqual(model.ruleRefusals, ["com.example.app": .appNotSigned])
        work.say(VPNEngine.StatePayload(connections: [office], autoConnected: [], lastAutomation: nil))
        for _ in 0..<500 where !model.ruleRefusals.isEmpty { await Task.yield() }
        XCTAssertEqual(model.ruleRefusals, [:])
    }
}
