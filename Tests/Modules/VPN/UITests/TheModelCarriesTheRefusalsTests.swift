// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Combine
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The model hands the page the refusals the engine published, and clears them.**
/// The sentence mapping is `ARefusedRuleIsDrawnWithItsNoteTests`.
@MainActor
final class TheModelCarriesTheRefusalsTests: XCTestCase {

    func testTheModelCarriesAndWithdrawsTheRefusals() {
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work, settings: seededVPNSettings())
        let office = VPNConnection(id: "A1", name: "Office", status: .disconnected, kind: "IKEv2")

        let carried = expectation(description: "the refusal reaches the model")
        let carriedToken = model.$ruleRefusals.sink { if !$0.isEmpty { carried.fulfill() } }
        defer { carriedToken.cancel() }
        work.say(VPNEngine.StatePayload(connections: [office], autoConnected: [],
                                        lastAutomation: nil,
                                        ruleRefusals: ["com.example.app": .appNotSigned]))
        wait(for: [carried], timeout: 5)
        XCTAssertEqual(model.ruleRefusals, ["com.example.app": .appNotSigned])

        let withdrawn = expectation(description: "the refusal is withdrawn")
        let withdrawnToken = model.$ruleRefusals.dropFirst().sink { if $0.isEmpty { withdrawn.fulfill() } }
        defer { withdrawnToken.cancel() }
        work.say(VPNEngine.StatePayload(connections: [office], autoConnected: [], lastAutomation: nil))
        wait(for: [withdrawn], timeout: 5)
        XCTAssertEqual(model.ruleRefusals, [:])
    }
}
