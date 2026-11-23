// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine

final class AutomationNoticeTests: XCTestCase {

    /// Asking for a notification permission before anyone wants notifications
    /// is how people learn to deny them.
    func testAuthorizationIsAskedForOnlyWhenTheBannerIsChosen() async {
        let port = FakeAutomationNotice(state: .notDetermined)
        _ = await AutomationNotice.prepare(for: .menuBar, port: port)
        XCTAssertEqual(port.requests, 0)
        _ = await AutomationNotice.prepare(for: .system, port: port)
        XCTAssertEqual(port.requests, 1)
    }

    func testADeniedBannerReportsItselfAsDenied() async {
        let port = FakeAutomationNotice()
        port.state = .denied
        // Hoisted out of the assertion: XCTAssertEqual takes autoclosures, and
        // an autoclosure cannot await.
        let state = await AutomationNotice.prepare(for: .system, port: port)
        XCTAssertEqual(state, .denied)
    }

    /// The engine decides whether a banner is posted; it does not write it.
    ///
    /// `L()` lives in `HelmUI` and an engine target cannot see it, so the words
    /// come in from the caller that can — and they must arrive on the banner
    /// untouched, or the eight languages stop where this boundary is.
    func testTheWordsPostedAreTheOnesHandedIn() async {
        let port = FakeAutomationNotice()
        port.state = .authorized
        await AutomationNotice.announce(notice: .system, title: "TITLE", body: "BODY", port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertEqual(port.posted[0].title, "TITLE")
        XCTAssertEqual(port.posted[0].body, "BODY")
    }

    func testTheBannerIsPostedOnlyInTheBannerMode() async {
        let port = FakeAutomationNotice()
        port.state = .authorized
        await AutomationNotice.announce(notice: .system, title: "t",
                                        body: "work is connected", port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertTrue(port.posted[0].body.contains("work"), "the banner did not name the connection")

        await AutomationNotice.announce(notice: .menuBar, title: "t", body: "b", port: port)
        await AutomationNotice.announce(notice: .silent, title: "t", body: "b", port: port)
        XCTAssertEqual(port.posted.count, 1, "a quiet mode posted a banner")
    }

    func testNothingIsPostedWhenAuthorizationWasRefused() async {
        let port = FakeAutomationNotice()
        port.state = .denied
        await AutomationNotice.announce(notice: .system, title: "t", body: "b", port: port)
        XCTAssertTrue(port.posted.isEmpty)
    }

    /// The permission is read when the rule fires, not remembered from when the
    /// person last opened a settings page: revoking it in System Settings tells
    /// the app nothing, and this is the moment being wrong is expensive.
    func testTheBannerModeAsksMacOSAtEveryFiring() async {
        let port = FakeAutomationNotice()
        port.state = .authorized
        var heard = await AutomationNotice.announce(notice: .system, title: "t", body: "b",
                                                    port: port)
        XCTAssertEqual(heard, .authorized)
        XCTAssertEqual(port.posted.count, 1)

        port.state = .denied   // revoked in System Settings, with nobody watching
        heard = await AutomationNotice.announce(notice: .system, title: "t", body: "b", port: port)
        XCTAssertEqual(heard, .denied, "the caller cannot fall back to the label without this")
        XCTAssertEqual(port.posted.count, 1, "a banner was posted into a refusal")
        XCTAssertEqual(port.requests, 0, "a firing prompted the person")
    }

    /// A mode whose behaviour the permission cannot change does not ask about
    /// it — and nil says so, distinctly from a refusal.
    func testTheQuietModesAskMacOSNothing() async {
        let port = FakeAutomationNotice()
        for notice in [VPNNotice.silent, .menuBar] {
            let heard = await AutomationNotice.announce(notice: notice, title: "t", body: "b",
                                                        port: port)
            XCTAssertNil(heard, "\(notice) asked macOS about a permission it does not use")
        }
        XCTAssertEqual(port.reads, 0)
    }
}
