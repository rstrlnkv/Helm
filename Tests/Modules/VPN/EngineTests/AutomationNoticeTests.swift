// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

private final class FakeNotice: AutomationNoticePort, @unchecked Sendable {
    var state: NoticeAuthorization = .notDetermined
    var requested = 0
    var posted: [(String, String)] = []
    func authorizationState() async -> NoticeAuthorization { state }
    func requestAuthorization() async -> NoticeAuthorization { requested += 1; return state }
    func post(title: String, body: String) async { posted.append((title, body)) }
}

final class AutomationNoticeTests: XCTestCase {

    /// Asking for a notification permission before anyone wants notifications
    /// is how people learn to deny them.
    func testAuthorizationIsAskedForOnlyWhenTheBannerIsChosen() async {
        let port = FakeNotice()
        _ = await AutomationNotice.prepare(for: .menuBar, port: port)
        XCTAssertEqual(port.requested, 0)
        _ = await AutomationNotice.prepare(for: .system, port: port)
        XCTAssertEqual(port.requested, 1)
    }

    func testADeniedBannerReportsItselfAsDenied() async {
        let port = FakeNotice()
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
        let port = FakeNotice()
        await AutomationNotice.announce(notice: .system, authorized: true,
                                        title: "TITLE", body: "BODY", port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertEqual(port.posted[0].0, "TITLE")
        XCTAssertEqual(port.posted[0].1, "BODY")
    }

    func testTheBannerIsPostedOnlyInTheBannerMode() async {
        let port = FakeNotice()
        port.state = .authorized
        await AutomationNotice.announce(notice: .system, authorized: true,
                                        title: "t", body: "work is connected", port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertTrue(port.posted[0].1.contains("work"), "the banner did not name the connection")

        await AutomationNotice.announce(notice: .menuBar, authorized: true,
                                        title: "t", body: "b", port: port)
        await AutomationNotice.announce(notice: .silent, authorized: true,
                                        title: "t", body: "b", port: port)
        XCTAssertEqual(port.posted.count, 1, "a quiet mode posted a banner")
    }

    func testNothingIsPostedWhenAuthorizationWasRefused() async {
        let port = FakeNotice()
        await AutomationNotice.announce(notice: .system, authorized: false,
                                        title: "t", body: "b", port: port)
        XCTAssertTrue(port.posted.isEmpty)
    }
}
