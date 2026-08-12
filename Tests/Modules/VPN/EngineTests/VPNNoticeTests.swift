// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

final class VPNNoticeTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn-test-\(UUID().uuidString)",
                                            backing: InMemoryKeyValueStore()))
    }

    /// A module that acts on its own should say what it did, and the label is
    /// the only mode that needs no new permission.
    func testTheDefaultIsTheMenuBarLabel() {
        XCTAssertEqual(settings().notice, .menuBar)
    }

    func testTheChoiceRoundTrips() {
        let s = settings()
        s.setNotice(.system)
        XCTAssertEqual(s.notice, .system)
        s.setNotice(.silent)
        XCTAssertEqual(s.notice, .silent)
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() {
        let store = NamespacedStore(namespace: "vpn-test-\(UUID().uuidString)",
                                    backing: InMemoryKeyValueStore())
        store.set("shout", for: "automationNotice")
        XCTAssertEqual(VPNSettings(store: store).notice, .menuBar)
    }

    /// The name is shown beside the icon in exactly one mode.
    func testOnlyTheMenuBarModeNamesTheConnectionInTheMenuBar() {
        XCTAssertTrue(VPNNotice.menuBar.showsMenuBarName)
        XCTAssertFalse(VPNNotice.silent.showsMenuBarName)
        XCTAssertFalse(VPNNotice.system.showsMenuBarName)
    }

    /// And the banner is posted in exactly one mode, the other one.
    func testOnlyTheSystemModePostsABanner() {
        XCTAssertTrue(VPNNotice.system.postsBanner)
        XCTAssertFalse(VPNNotice.menuBar.postsBanner)
        XCTAssertFalse(VPNNotice.silent.postsBanner)
    }

    /// Nothing has asked macOS yet, so nothing may claim it said yes: the
    /// default has to be the one that keeps `.system` audible as the label.
    func testBannerAuthorizationIsNotAssumedBeforeAnyoneHasAsked() {
        XCTAssertFalse(settings().bannerAuthorized)
    }

    /// Remembered across launches on purpose — macOS is asked once, and a
    /// mirror that resets at every launch would demote `.system` to the label
    /// for a person who granted the permission months ago.
    func testTheAuthorizationMirrorRoundTrips() {
        let s = settings()
        s.setBannerAuthorized(true)
        XCTAssertTrue(s.bannerAuthorized)
        s.setBannerAuthorized(false)
        XCTAssertFalse(s.bannerAuthorized)
    }

    // MARK: - A teardown nobody asked for at that moment

    /// **An automatic disconnect is not quieter than a drop.**
    ///
    /// `.disconnected` is Helm taking a tunnel down because a mapped app quit,
    /// and it answered to the *rules'* setting — which on this machine is
    /// `silent` while `dropNotice` is `system`: the person asked to be told
    /// loudly about losing a tunnel and quietly about rules doing as they were
    /// told, and a teardown they did not ask for at that instant took the quiet
    /// channel. The two events end the same way, with traffic in clear after the
    /// last thing said was that it was not, so the teardown is announced at least
    /// as loudly as the fall would have been.
    ///
    /// It matters more than a volume: a quit can be provoked. Anything running as
    /// this user can launch and quit a bundle carrying a mapped identifier, and
    /// the teardown that follows is booked as a rule doing as asked.
    func testAnAutomaticTeardownTakesTheLouderOfTheTwoSettings() {
        XCTAssertEqual(VPNNotice.mode(for: .disconnected, rules: .silent, drop: .system), .system)
        XCTAssertEqual(VPNNotice.mode(for: .disconnected, rules: .system, drop: .silent), .system)
        XCTAssertEqual(VPNNotice.mode(for: .disconnected, rules: .silent, drop: .menuBar), .menuBar)
    }

    /// The controls: the other two kinds each answer to one setting, and only
    /// one. Without them «the louder of the two» could be applied to everything,
    /// which is a module that announces whatever is loudest and reads neither
    /// choice.
    func testTheOtherTwoKindsEachAnswerToTheirOwnSetting() {
        XCTAssertEqual(VPNNotice.mode(for: .connected, rules: .silent, drop: .system), .silent)
        XCTAssertEqual(VPNNotice.mode(for: .dropped, rules: .system, drop: .silent), .silent)
    }

    /// The store reads the same rule, so nothing decides this twice.
    func testTheSettingsAgreeWithTheRule() {
        let s = settings()
        s.setNotice(.silent)
        s.setDropNotice(.system)
        XCTAssertEqual(s.notice(for: .disconnected), .system)
        XCTAssertEqual(s.notice(for: .connected), .silent)
        XCTAssertEqual(s.notice(for: .dropped), .system)
    }

    /// Authorization refused: the loud mode becomes the quiet one, never
    /// silence. The person asked to be told.
    func testADeniedBannerFallsBackToTheLabelAndNotToSilence() {
        XCTAssertTrue(VPNNotice.system.effective(bannerAuthorized: false).showsMenuBarName)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: false), .menuBar)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: true), .system)
        XCTAssertEqual(VPNNotice.silent.effective(bannerAuthorized: false), .silent)
    }
}
