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

    private func descriptor(firing: VPNAutomation?, notice: VPNNotice,
                            bannerAuthorized: Bool = false,
                            spin: Bool = false,
                            spinTints: [VPNAutomation.Kind: String]? = nil)
                            -> (VPNDescriptor, ModuleViewModel) {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        descriptor.viewModel(host).setForTesting(automation: firing, notice: notice,
                                                 bannerAuthorized: bannerAuthorized,
                                                 spin: spin, spinTints: spinTints)
        return (descriptor, host)
    }

    private func firing(secondsAgo: TimeInterval, name: String = "Office") -> VPNAutomation {
        VPNAutomation(at: Date().addingTimeInterval(-secondsAgo), name: name, kind: .connected)
    }

    private func firing(secondsAgo: TimeInterval, name: String = "Office",
                        kind: VPNAutomation.Kind) -> VPNAutomation {
        VPNAutomation(at: Date().addingTimeInterval(-secondsAgo), name: name, kind: kind)
    }

    func testFreshFiringSpinsTheRingAndNamesTheConnection() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .menuBar, spin: true)
        let appearance = d.statusAppearance(host)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertEqual(appearance.title, "Office")
    }

    /// The movement is feedback that the app did something rather than a
    /// notification, so the quietest *notice* mode still gets it — the notice
    /// setting decides the fate of the name only. Whether there is movement at
    /// all is now its own switch, which this test turns on.
    func testSilentModeStillSpinsButNamesNothing() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .silent, spin: true)
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

    // MARK: - The banner mode, before there is a banner

    /// The loudest mode was the quietest one.
    ///
    /// The descriptor asked `notice.showsMenuBarName`, which is false for
    /// `.system`, so a person who chose to be told loudly and had refused (or
    /// never been asked for) the permission got nothing at all — neither banner
    /// nor name. `effective(bannerAuthorized:)` exists precisely to rule that
    /// out, and the descriptor has to be the one asking it.
    func testTheBannerModeNamesTheConnectionWhenMacOSHasNotAuthorizedBanners() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 0), notice: .system,
                                   bannerAuthorized: false)
        XCTAssertEqual(d.statusAppearance(host).title, "Office",
                       "the mode that asks to be told loudly said nothing at all")
    }

    /// And once macOS has authorized them, the banner carries the name and the
    /// menu bar goes back to just turning.
    func testAnAuthorizedBannerLeavesTheNameToTheBanner() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .system, bannerAuthorized: true, spin: true)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.title)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired),
                       "the ring turns in every mode — that is feedback, not a notification")
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

    // MARK: - The spin setting

    /// The reversal, pinned. The automation-feedback spec had the ring turning
    /// in every mode; movement in the menu bar is a person's to switch off, and
    /// the default is off.
    func testNothingTurnsUntilSomebodyAsksForIt() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.spinUntil, "the ring must not turn when nobody asked")
        XCTAssertEqual(appearance.title, "Office", "the name is a separate setting and still applies")
    }

    func testEachKindTurnsInItsOwnColour() {
        let tints: [VPNAutomation.Kind: String] = [.connected: "purple", .disconnected: "pink"]
        let (up, upHost) = descriptor(firing: firing(secondsAgo: 0, kind: .connected),
                                      notice: .menuBar, spin: true, spinTints: tints)
        XCTAssertEqual(up.statusAppearance(upHost).spinTintToken, "purple")

        let (down, downHost) = descriptor(firing: firing(secondsAgo: 0, kind: .disconnected),
                                          notice: .menuBar, spin: true, spinTints: tints)
        XCTAssertEqual(down.statusAppearance(downHost).spinTintToken, "pink")
    }

    func testTheDefaultColoursDifferByKind() {
        let (up, upHost) = descriptor(firing: firing(secondsAgo: 0, kind: .connected),
                                      notice: .menuBar, spin: true)
        let (down, downHost) = descriptor(firing: firing(secondsAgo: 0, kind: .disconnected),
                                          notice: .menuBar, spin: true)
        XCTAssertEqual(up.statusAppearance(upHost).spinTintToken, "green")
        XCTAssertEqual(down.statusAppearance(downHost).spinTintToken, "orange")
    }

    /// The decision this module wrote down three days ago, which the colour
    /// work must not quietly spend: a tint is a claim on the icon between
    /// moments, and this module makes none.
    func testTheModuleStillNeverTints() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar, spin: true)
        XCTAssertNil(d.statusAppearance(host).tintToken,
                     "no tint, ever — the spin colour is a different field")
    }

    /// A spin that is over carries no colour either, so a spent appearance
    /// cannot be mistaken for a live one further up.
    func testASpentSpinCarriesNoColour() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 60), notice: .menuBar, spin: true)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertNil(appearance.spinTintToken)
    }
}
