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

    /// Authorization refused: the loud mode becomes the quiet one, never
    /// silence. The person asked to be told.
    func testADeniedBannerFallsBackToTheLabelAndNotToSilence() {
        XCTAssertTrue(VPNNotice.system.effective(bannerAuthorized: false).showsMenuBarName)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: false), .menuBar)
        XCTAssertEqual(VPNNotice.system.effective(bannerAuthorized: true), .system)
        XCTAssertEqual(VPNNotice.silent.effective(bannerAuthorized: false), .silent)
    }
}
