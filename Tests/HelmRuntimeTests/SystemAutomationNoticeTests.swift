// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// The one class in the tree that talks to `UNUserNotificationCenter`.
///
/// `UNUserNotificationCenter.current()` raises "bundleProxyForCurrentProcess is
/// nil" in a process that is not a bundled app, and an ObjC exception does not
/// fail a case: it takes the whole `swift test` run down. So the class asks
/// whether it is inside an app bundle before it asks macOS anything: under
/// `xctest`, `Bundle.main` has an empty extension; the shipped app's is
/// `Helm.app`.
final class SystemAutomationNoticeTests: XCTestCase {

    func testATestProcessIsNotAnAppBundle() {
        XCTAssertNotEqual(Bundle.main.bundleURL.pathExtension, "app",
                          "this suite is running inside an app bundle, so the guard below "
                          + "proves nothing and the real notification centre is one call away")
    }

    /// Every method, because any one of them reaching the centre ends the run.
    func testNothingReachesMacOSFromHere() async {
        let port = SystemAutomationNotice(area: "test")
        let state = await port.authorizationState()
        XCTAssertEqual(state, .notDetermined)
        let requested = await port.requestAuthorization()
        XCTAssertEqual(requested, .notDetermined)
        await port.post(title: "no banner", body: "may be posted from a test")
    }
}
