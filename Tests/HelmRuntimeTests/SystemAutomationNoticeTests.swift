// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// The one class in the tree that talks to `UNUserNotificationCenter`, and the
/// one that could not be run at all.
///
/// It sat in VPN's engine until Keep Awake's battery veto needed a banner too;
/// the class and this file moved to `HelmRuntime` together, because a test that
/// stays behind in the module the code left is a test of nothing.
///
/// `UNUserNotificationCenter.current()` raises `NSInternalInconsistencyException`
/// — "bundleProxyForCurrentProcess is nil" — in a process that is not a bundled
/// app, and an ObjC exception does not fail a case: it takes the whole
/// `swift test` run down. So the class was written to be reached only in the
/// app and left with no coverage at all, one careless `await` away from a suite
/// that cannot run.
///
/// It now asks whether it is inside an app bundle before it asks macOS
/// anything. Measured rather than assumed: under `xctest` `Bundle.main` is
/// `/Applications/Xcode.app/Contents/Developer/usr/bin`, whose extension is
/// empty; the shipped app's is `Helm.app`.
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
