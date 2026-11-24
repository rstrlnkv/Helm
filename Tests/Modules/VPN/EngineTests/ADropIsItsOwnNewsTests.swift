// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// A tunnel that fell over is not a rule doing what it was told.
///
/// Somebody who sets the rules to fire in silence is not asking to be left
/// untold when the tunnel goes down under them and the Mac sends in clear. So a
/// drop has its own kind and its own notice setting, and shares the ring colour
/// of a tunnel going down.
final class ADropIsItsOwnNewsTests: XCTestCase {
    private var settings: VPNSettings!

    override func setUp() {
        super.setUp()
        settings = VPNSettings.inMemory()
    }

    /// Both default to the menu bar. `.system` would be a lie: macOS grants the
    /// banner permission only when asked, and this module asks only when a
    /// person picks that mode.
    func testBothStartWhereTheOneSettingUsedTo() {
        XCTAssertEqual(settings.notice, .menuBar)
        XCTAssertEqual(settings.dropNotice, .menuBar)
    }

    /// The whole point: silence for the rules is not silence for a drop.
    func testSilencingTheRulesLeavesTheDropAlone() {
        settings.store.set(VPNNotice.silent.rawValue, for: VPNSettings.automationNoticeKey)
        settings.store.set(VPNNotice.system.rawValue, for: VPNSettings.dropNoticeKey)

        XCTAssertEqual(settings.notice(for: .connected), .silent)
        // A quit rule's teardown is one nobody asked for at that moment, and any
        // process of this user can provoke a quit, so `VPNNotice.mode` gives it
        // the louder of the two (`VPNNoticeTests`).
        XCTAssertEqual(settings.notice(for: .disconnected), .system,
                       "a teardown Helm performed was announced more quietly than the fall it "
                       + "looks like from outside")
        XCTAssertEqual(settings.notice(for: .dropped), .system,
                       "the tunnel fell over and the module read the rules' setting")
    }

    /// And the other way, so the guard above is not simply "the drop is always
    /// louder".
    func testSilencingTheDropLeavesTheRulesAlone() {
        settings.store.set(VPNNotice.system.rawValue, for: VPNSettings.automationNoticeKey)
        settings.store.set(VPNNotice.silent.rawValue, for: VPNSettings.dropNoticeKey)

        XCTAssertEqual(settings.notice(for: .connected), .system)
        XCTAssertEqual(settings.notice(for: .dropped), .silent)
    }

    /// Two settings, two accounts. Writing one must not write the other — the
    /// failure this catches is a single stored key read through two names.
    func testTheTwoAreStoredApart() {
        settings.store.set(VPNNotice.silent.rawValue, for: VPNSettings.automationNoticeKey)
        XCTAssertEqual(settings.dropNotice, .menuBar,
                       "setting the rules' mode moved the drop's")
        settings.store.set(VPNNotice.system.rawValue, for: VPNSettings.dropNoticeKey)
        XCTAssertEqual(settings.notice, .silent,
                       "setting the drop's mode moved the rules'")
    }

    /// Three kinds of news, **two colours**. The ring says which way the tunnel
    /// went, so a drop turns it in the colour chosen for a tunnel going down.
    /// A key derived from `rawValue` would open a third one nobody set.
    func testADropTurnsTheRingInTheColourChosenForATunnelGoingDown() {
        settings.store.set("purple", for: VPNSettings.spinTintKey(.disconnected))

        XCTAssertEqual(settings.spinTint(for: .dropped), "purple",
                       "a tunnel that fell over turned the ring in a colour nobody picked")
        XCTAssertEqual(settings.spinTint(for: .connected), "green",
                       "precondition: the connect colour is untouched, so the assertion above "
                       + "is about the drop and not about one shared key")
    }
}
