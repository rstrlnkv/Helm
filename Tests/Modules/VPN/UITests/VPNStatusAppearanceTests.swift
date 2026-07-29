// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Combine
import HelmContract
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// What the menu bar is asked for when a VPN rule fires by itself.
///
/// The windows are asserted against `VPNAutomation`'s own arithmetic rather
/// than against numbers: a test that says "spinUntil is about 1.2 s from now"
/// passes whenever the clock is kind to it, which is how a broken fix shipped
/// green once already.
@MainActor
final class VPNStatusAppearanceTests: XCTestCase {

    private func descriptor(firing: VPNAutomation?,
                            notice: VPNNotice) -> (VPNDescriptor, ModuleViewModel) {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        descriptor.viewModel(host).setForTesting(automation: firing, notice: notice)
        return (descriptor, host)
    }

    private func firing(secondsAgo: TimeInterval, name: String = "Office") -> VPNAutomation {
        VPNAutomation(at: Date().addingTimeInterval(-secondsAgo), name: name, kind: .connected)
    }

    func testFreshFiringSpinsTheRingAndNamesTheConnection() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .menuBar)
        let appearance = d.statusAppearance(host)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertEqual(appearance.title, "Office")
    }

    /// The movement is feedback that the app did something, not a notification:
    /// the quietest mode still gets it, or an automation cannot be told apart
    /// from a tunnel that changed on its own.
    func testSilentModeStillSpinsButNamesNothing() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .silent)
        let appearance = d.statusAppearance(host)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertNil(appearance.title)
    }

    func testFiringOlderThanTheNameWindowAsksForNothing() {
        let older = VPNAutomation.nameDuration + 5
        let (d, host) = descriptor(firing: firing(secondsAgo: older), notice: .menuBar)
        XCTAssertEqual(d.statusAppearance(host), .inactive)
    }

    /// The name outlives the ring on purpose — the movement catches the eye,
    /// the word answers what caught it.
    func testFiringPastTheSpinButInsideTheNameWindowNamesWithoutSpinning() {
        let between = (VPNAutomation.spinDuration + VPNAutomation.nameDuration) / 2
        let (d, host) = descriptor(firing: firing(secondsAgo: between), notice: .menuBar)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertEqual(appearance.title, "Office")
    }

    func testNoFiringAsksForNothing() {
        let (d, host) = descriptor(firing: nil, notice: .menuBar)
        XCTAssertEqual(d.statusAppearance(host), .inactive)
    }

    // MARK: - What arrives from the engine

    /// The engine keeps its last firing for good and repeats it in every state
    /// payload, so "there is a firing here" cannot be read as "one just
    /// happened". Waiting on `connections` rather than on a number of yields
    /// keeps this honest: the assertion is only reached once the very payload
    /// carrying the firing has been handled.
    private func settle(_ model: VPNViewModel) async {
        for _ in 0..<500 where model.connections.isEmpty { await Task.yield() }
    }

    private func emit(_ automation: VPNAutomation, on transport: LocalTransport) {
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "A1", name: "Office",
                                        status: .connected, kind: "IKEv2")],
            autoConnected: ["Office"], defaultName: "Office", lastAutomation: automation)
        transport.emit(EngineEvent(name: "state",
                                   payload: try! JSONEncoder().encode(payload)))
    }

    func testAFreshFiringArrivesThroughTheStatePayload() async {
        let transport = LocalTransport()
        let fresh = firing(secondsAgo: 0)
        emit(fresh, on: transport)
        let model = VPNViewModel(transport: transport)
        await settle(model)
        XCTAssertEqual(model.lastAutomation, fresh)
    }

    func testAFiringOlderThanItsNameWindowIsDroppedOnArrival() async {
        let transport = LocalTransport()
        emit(firing(secondsAgo: VPNAutomation.nameDuration + 5), on: transport)
        let model = VPNViewModel(transport: transport)
        await settle(model)
        XCTAssertFalse(model.connections.isEmpty, "the payload never arrived, so this "
                       + "test would pass without dropping anything")
        XCTAssertNil(model.lastAutomation)
    }

    /// The end of the name window needs a redraw as much as its start did.
    ///
    /// Nothing else supplies one: the host's spin tick disarms itself the frame
    /// the spin ends, and `statusChanges` only fires when this model publishes.
    /// Measured in the menu bar — the name sat on the icon for 76 straight
    /// frames after its three seconds were up, until an unrelated firing
    /// happened to redraw it away.
    func testTheNameIsGivenUpWhenItsWindowCloses() async {
        let model = VPNViewModel(transport: LocalTransport())
        model.setForTesting(automation: firing(secondsAgo: VPNAutomation.nameDuration - 0.15),
                            notice: .menuBar)
        XCTAssertNotNil(model.lastAutomation, "still inside its window, so this proves nothing yet")

        for _ in 0..<400 where model.lastAutomation != nil {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertNil(model.lastAutomation,
                     "the firing outlived its own name window with nothing to redraw it away")
    }

    /// Without this the host never learns a rule fired: it reads
    /// `statusAppearance` when something else redraws the icon, and nothing
    /// else does.
    func testStatusChangesFireWhenAFiringArrives() {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        let model = descriptor.viewModel(host)
        guard let changes = descriptor.statusChanges(host) else {
            return XCTFail("VPN publishes no status changes, so a firing never reaches the icon")
        }
        var fired = 0
        let token = changes.sink { fired += 1 }
        model.setForTesting(automation: firing(secondsAgo: 0), notice: .menuBar)
        token.cancel()
        XCTAssertEqual(fired, 1)
    }
}
