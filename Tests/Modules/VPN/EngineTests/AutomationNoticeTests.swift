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

    func testTheBannerIsPostedOnlyInTheBannerMode() async {
        let port = FakeNotice()
        port.state = .authorized
        let firing = VPNAutomation(at: Date(), name: "work", kind: .connected)
        await AutomationNotice.announce(firing, notice: .system, authorized: true, port: port)
        XCTAssertEqual(port.posted.count, 1)
        XCTAssertTrue(port.posted[0].1.contains("work"), "the banner did not name the connection")

        await AutomationNotice.announce(firing, notice: .menuBar, authorized: true, port: port)
        await AutomationNotice.announce(firing, notice: .silent, authorized: true, port: port)
        XCTAssertEqual(port.posted.count, 1, "a quiet mode posted a banner")
    }

    func testNothingIsPostedWhenAuthorizationWasRefused() async {
        let port = FakeNotice()
        let firing = VPNAutomation(at: Date(), name: "work", kind: .connected)
        await AutomationNotice.announce(firing, notice: .system, authorized: false, port: port)
        XCTAssertTrue(port.posted.isEmpty)
    }

    /// The banner's words are English in all eight languages, and this is what
    /// stops that from reaching anybody.
    ///
    /// `AutomationNotice.Words` cannot call `L()`: that lives in `HelmUI`, and
    /// an engine target depends on `HelmContract` + `HelmRuntime` alone. Nothing
    /// in the app calls `announce` yet, so the English costs nobody anything —
    /// the day something does, this turns red and the words have to be settled
    /// first. A prose note in the file would not have.
    ///
    /// Seen to fail: wiring `announce` into `VPNEngine.recordAutomation` names
    /// that file here and the test reports it.
    func testTheBannerIsNotWiredUpWhileItsWordsAreEnglishOnly() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // VPN
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
        var callers: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  source.contains("AutomationNotice.announce(") else { continue }
            callers.append(url.lastPathComponent)
        }
        XCTAssertTrue(callers.isEmpty, "\(callers.joined(separator: ", ")) posts a banner whose "
            + "words are English in all eight languages. macOS ships the sentence itself in "
            + "Network.appex/Contents/Resources/Localizable.loctable (VPN_CONNECTED) — read the "
            + "eight out of there, put them somewhere L() can reach, and delete this guard.")
    }

    /// A disconnection is not a connection, and the banner must not say it is.
    func testTheTwoKindsReadDifferently() async {
        let port = FakeNotice()
        port.state = .authorized
        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .connected),
                                        notice: .system, authorized: true, port: port)
        await AutomationNotice.announce(VPNAutomation(at: Date(), name: "work", kind: .disconnected),
                                        notice: .system, authorized: true, port: port)
        XCTAssertNotEqual(port.posted[0].0, port.posted[1].0)
    }
}
