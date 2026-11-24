// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Combine
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// What the menu bar is asked for when a VPN rule fires by itself.
///
/// The windows are asserted against `VPNAutomation`'s own arithmetic rather
/// than against numbers: a test that says "spinUntil is about 1.2 s from now"
/// passes whenever the clock is kind to it.
///
/// Guards: the menu-bar windows follow VPNAutomation's own arithmetic.
@MainActor
final class VPNStatusAppearanceTests: XCTestCase {

    private func descriptor(firing: VPNAutomation?, notice: VPNNotice,
                            bannerAuthorized: Bool = false,
                            spin: Bool = false)
                            -> (VPNDescriptor, VPNViewModel) {
        let model = VPNViewModel(work: FakeVPNWork(),
                                settings: seededVPNSettings(notice: notice,
                                                            bannerAuthorized: bannerAuthorized,
                                                            spin: spin))
        model.setForTesting(automation: firing)
        return (VPNDescriptor(), model)
    }

    private func firing(secondsAgo: TimeInterval, name: String = "Office") -> VPNAutomation {
        VPNAutomation(at: Date().addingTimeInterval(-secondsAgo), name: name, kind: .connected)
    }

    func testFreshFiringSpinsTheRingAndNamesTheConnection() {
        let fired = firing(secondsAgo: 0)
        let (d, model) = descriptor(firing: fired, notice: .menuBar, spin: true)
        let appearance = d.statusAppearance(model)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertEqual(appearance.title, "Office")
    }

    /// The movement is feedback that the app did something rather than a
    /// notification, so the quietest *notice* mode still gets it — the notice
    /// setting decides the fate of the name only. Whether there is movement at
    /// all is its own switch, which this test turns on.
    func testSilentModeStillSpinsButNamesNothing() {
        let fired = firing(secondsAgo: 0)
        let (d, model) = descriptor(firing: fired, notice: .silent, spin: true)
        let appearance = d.statusAppearance(model)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertNil(appearance.title)
    }

    func testFiringOlderThanTheNameWindowAsksForNothing() {
        let older = VPNAutomation.nameDuration + 5
        let (d, model) = descriptor(firing: firing(secondsAgo: older), notice: .menuBar)
        XCTAssertEqual(d.statusAppearance(model), .inactive)
    }

    /// The name outlives the ring on purpose — the movement catches the eye,
    /// the word answers what caught it.
    func testFiringPastTheSpinButInsideTheNameWindowNamesWithoutSpinning() {
        let between = (VPNAutomation.spinDuration + VPNAutomation.nameDuration) / 2
        let (d, model) = descriptor(firing: firing(secondsAgo: between), notice: .menuBar)
        let appearance = d.statusAppearance(model)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertEqual(appearance.title, "Office")
    }

    func testNoFiringAsksForNothing() {
        let (d, model) = descriptor(firing: nil, notice: .menuBar)
        XCTAssertEqual(d.statusAppearance(model), .inactive)
    }

    // MARK: - The banner mode, before there is a banner

    /// The loudest mode must not be the quietest one: `notice.showsMenuBarName`
    /// is false for `.system`, so a person who chose to be told loudly without
    /// the permission would get neither banner nor name. The descriptor asks
    /// `effective(bannerAuthorized:)`, which rules that out.
    func testTheBannerModeNamesTheConnectionWhenMacOSHasNotAuthorizedBanners() {
        let (d, model) = descriptor(firing: firing(secondsAgo: 0), notice: .system,
                                   bannerAuthorized: false)
        XCTAssertEqual(d.statusAppearance(model).title, "Office",
                       "the mode that asks to be told loudly said nothing at all")
    }

    /// And once macOS has authorized them, the banner carries the name and the
    /// menu bar goes back to just turning.
    func testAnAuthorizedBannerLeavesTheNameToTheBanner() {
        let fired = firing(secondsAgo: 0)
        let (d, model) = descriptor(firing: fired, notice: .system, bannerAuthorized: true, spin: true)
        let appearance = d.statusAppearance(model)
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
        await waitUntil("the payload handled", within: .seconds(5)) { !model.connections.isEmpty }
    }

    private func emit(_ automation: VPNAutomation, on work: FakeVPNWork) {
        work.say(VPNEngine.StatePayload(
            connections: [VPNConnection(id: "A1", name: "Office",
                                        status: .connected, kind: "IKEv2")],
            autoConnected: ["Office"], lastAutomation: automation))
    }

    func testAFreshFiringArrivesThroughTheStatePayload() async {
        let work = FakeVPNWork()
        let fresh = firing(secondsAgo: 0)
        emit(fresh, on: work)
        let model = VPNViewModel(work: work, settings: seededVPNSettings())
        await settle(model)
        XCTAssertEqual(model.lastAutomation, fresh)
    }

    func testAFiringOlderThanItsNameWindowIsDroppedOnArrival() async {
        let work = FakeVPNWork()
        emit(firing(secondsAgo: VPNAutomation.nameDuration + 5), on: work)
        let model = VPNViewModel(work: work, settings: seededVPNSettings())
        await settle(model)
        XCTAssertFalse(model.connections.isEmpty, "the payload never arrived, so this "
                       + "test would pass without dropping anything")
        XCTAssertNil(model.lastAutomation)
    }

    /// The end of the name window needs a redraw as much as its start did.
    ///
    /// Nothing else supplies one: the host's spin tick disarms itself the frame
    /// the spin ends, and `statusChanges` only fires when this model publishes,
    /// so the name would sit on the icon until an unrelated redraw.
    func testTheNameIsGivenUpWhenItsWindowCloses() async {
        let model = VPNViewModel(work: FakeVPNWork(), settings: seededVPNSettings(notice: .menuBar))
        model.setForTesting(automation: firing(secondsAgo: VPNAutomation.nameDuration - 0.15))
        XCTAssertNotNil(model.lastAutomation, "still inside its window, so this proves nothing yet")

        await waitUntil("the name window closed", within: .seconds(2)) { model.lastAutomation == nil }

        XCTAssertNil(model.lastAutomation,
                     "the firing outlived its own name window with nothing to redraw it away")
    }

    /// Without this the host never learns a rule fired: it reads
    /// `statusAppearance` when something else redraws the icon, and nothing
    /// else does.
    func testStatusChangesFireWhenAFiringArrives() {
        let descriptor = VPNDescriptor()
        let model = VPNViewModel(work: FakeVPNWork(), settings: seededVPNSettings())
        guard let changes = descriptor.statusChanges(model) else {
            return XCTFail("VPN publishes no status changes, so a firing never reaches the icon")
        }
        var fired = 0
        let token = changes.sink { fired += 1 }
        model.setForTesting(automation: firing(secondsAgo: 0))
        token.cancel()
        XCTAssertEqual(fired, 1)
    }

    // MARK: - The spin setting

    /// Movement in the menu bar is a person's to switch on: the default is off.
    func testNothingTurnsUntilSomebodyAsksForIt() {
        let (d, model) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar)
        let appearance = d.statusAppearance(model)
        XCTAssertNil(appearance.spinUntil, "the ring must not turn when nobody asked")
        XCTAssertEqual(appearance.title, "Office", "the name is a separate setting and still applies")
    }

    /// A tint is a claim on the icon between moments, and this module makes
    /// none; the colour work must not spend that.
    func testTheModuleStillNeverTints() {
        let (d, model) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar, spin: true)
        XCTAssertNil(d.statusAppearance(model).tintToken,
                     "no tint, ever — the spin colour is a different field")
    }

    /// A spin that is over carries no colour either, so a spent appearance
    /// cannot be mistaken for a live one further up.
    func testASpentSpinCarriesNoColour() {
        let (d, model) = descriptor(firing: firing(secondsAgo: 60), notice: .menuBar, spin: true)
        let appearance = d.statusAppearance(model)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertNil(appearance.spinTintToken)
    }
}
