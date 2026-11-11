// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// A model built asks the engine nothing; after `stop()` a press, a re-read or a
/// state the engine still yields reaches nothing, is not drawn and is not
/// announced.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`,
/// on the person's switch and on quit. A page still on screen, or a task already
/// queued, may press a control after that: a stopped model reaches no work, and a
/// stream task left running keeps a subscriber on a stream nobody reads. Defect
/// class kept: a stopped model still talks to the engine, still listens to it, or
/// still speaks for a firing it heard.
///
/// Every absence is paired with a control that proves the fake counts the same
/// call while the model lives (`FakeVPNWork` names each call by its member, a press by its verb).
@MainActor
final class AStoppedVPNModelReachesNoWorkTests: XCTestCase {

    private static func state(measuring: String? = nil,
                              firing: VPNAutomation? = nil) -> VPNEngine.StatePayload {
        VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "Office", status: .connected,
                                        kind: "IKEv2")],
            autoConnected: [], lastAutomation: firing,
            tunnels: measuring.map { [VPNTunnelState(name: $0, interface: "utun3", since: nil,
                                                      bytesIn: nil, bytesOut: nil,
                                                      exit: .unknown, speed: nil,
                                                      measuring: true)] } ?? [])
    }

    func testBuildingTheModelAsksTheEngineNothing() {
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work)
        XCTAssertEqual(work.calls, ["stream"],
                       "the model asked the engine for something beside its stream when built")
        model.stop()
    }

    func testAPressAfterStopReachesNoWork() async {
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work)

        // Control: every door reaches the work while the model lives.
        model.refresh()
        model.connect("Office")
        model.disconnect("Office")
        model.measureSpeed("Office")
        model.rulesChanged()
        let live = ["stream", "refresh", "connect Office", "disconnect Office",
                    "measureSpeed Office", "reloadRules"]
        XCTAssertEqual(work.calls, live, "control: the presses did not reach the work")
        XCTAssertEqual(model.measuring, "Office", "control: a press marks the run")

        work.say(Self.state())
        await waitUntil("the engine's answer clears the mark") { model.measuring == nil }

        model.stop()
        model.refresh()
        model.connect("Office")
        model.disconnect("Office")
        model.measureSpeed("Office")
        model.rulesChanged()
        await grace()
        XCTAssertEqual(work.calls, live, "a stopped model reached the engine")
        XCTAssertNil(model.measuring, "a stopped model marked a run nothing will answer")
    }

    func testAStateAfterStopIsNotDrawnOrAnnounced() async {
        let work = FakeVPNWork()
        let port = FakeAutomationNotice(state: .authorized)
        let model = VPNViewModel(work: work, notices: port)
        model.setForTesting(automation: nil, notice: .system, bannerAuthorized: true)

        // Control: a state reaches the page, and its firing is announced.
        work.say(Self.state())
        await waitUntil("a state reaches the model") { !model.connections.isEmpty }

        model.stop()
        await waitUntil("the stream is given back") { work.subscribers == 0 }
        XCTAssertEqual(work.finishedStreams, 1)

        work.say(Self.state(measuring: "Office",
                            firing: VPNAutomation(at: Date(), name: "Office", kind: .connected)))
        await grace()
        XCTAssertNil(model.measuring, "a stopped model went on drawing what the engine said")
        XCTAssertNil(model.lastAutomation, "a stopped model adopted a firing")
        XCTAssertTrue(port.posted.isEmpty, "a stopped model announced a firing: \(port.posted)")
    }
}
