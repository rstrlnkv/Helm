// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// A tunnel that fell over is not a rule doing what it was told.
///
/// The two shared `VPNAutomation.Kind.disconnected` for the life of the module,
/// which meant they shared a volume: somebody who set the rules to fire in
/// silence — reasonably, since they arranged them — was also asking not to be
/// told when the tunnel went down underneath them and their Mac started sending
/// in clear. Splitting the kind is only half of it; the settings have to be able
/// to differ, and the colour must not.
final class ADropIsItsOwnNewsTests: XCTestCase {
    private var settings: VPNSettings!

    override func setUp() {
        super.setUp()
        settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                      backing: InMemoryKeyValueStore()))
    }

    /// The default, so the split changes nothing for somebody who never opens
    /// the page. `.system` would be the louder default and would be a lie:
    /// macOS grants the banner permission only when asked, and this module asks
    /// only when a person picks that mode.
    func testBothStartWhereTheOneSettingUsedTo() {
        XCTAssertEqual(settings.notice, .menuBar)
        XCTAssertEqual(settings.dropNotice, .menuBar)
    }

    /// The whole point: silence for the rules is not silence for a drop.
    func testSilencingTheRulesLeavesTheDropAlone() {
        settings.setNotice(.silent)
        settings.setDropNotice(.system)

        XCTAssertEqual(settings.notice(for: .connected), .silent)
        XCTAssertEqual(settings.notice(for: .disconnected), .silent,
                       "a quit rule is a rule; it answers to the rules' setting")
        XCTAssertEqual(settings.notice(for: .dropped), .system,
                       "the tunnel fell over and the module read the rules' setting")
    }

    /// And the other way, so the guard above is not simply "the drop is always
    /// louder".
    func testSilencingTheDropLeavesTheRulesAlone() {
        settings.setNotice(.system)
        settings.setDropNotice(.silent)

        XCTAssertEqual(settings.notice(for: .connected), .system)
        XCTAssertEqual(settings.notice(for: .dropped), .silent)
    }

    /// Two settings, two accounts. Writing one must not write the other — the
    /// failure this catches is a single stored key read through two names.
    func testTheTwoAreStoredApart() {
        settings.setNotice(.silent)
        XCTAssertEqual(settings.dropNotice, .menuBar,
                       "setting the rules' mode moved the drop's")
        settings.setDropNotice(.system)
        XCTAssertEqual(settings.notice, .silent,
                       "setting the drop's mode moved the rules'")
    }

    /// Three kinds of news, **two colours**. The ring says which way the tunnel
    /// went, and there are two ways — so a drop turns it in whatever the person
    /// chose for a tunnel going down, not in a default nobody set. Deriving the
    /// key from `rawValue` would have opened a third one silently.
    func testADropTurnsTheRingInTheColourChosenForATunnelGoingDown() {
        settings.setSpinTint("purple", for: .disconnected)

        XCTAssertEqual(settings.spinTint(for: .dropped), "purple",
                       "a tunnel that fell over turned the ring in a colour nobody picked")
        XCTAssertEqual(settings.spinTint(for: .connected), "green",
                       "precondition: the connect colour is untouched, so the assertion above "
                       + "is about the drop and not about one shared key")
    }

    /// Setting it *through* `.dropped` writes the same one, so the settings page
    /// and a firing cannot disagree about where the colour lives.
    func testSettingTheColourThroughTheDropKindWritesTheOneRowThePageDraws() {
        settings.setSpinTint("red", for: .dropped)

        XCTAssertEqual(settings.spinTint(for: .disconnected), "red")
    }
}
