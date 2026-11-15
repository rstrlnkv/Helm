// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// **The words the log carries for a read that answered nothing are one
/// function's, for both the engine's list read and the keychain's show read.**
/// A timeout names its deadline; any other failure names its exit status.
final class AFailedReadIsNamedOnceTests: XCTestCase {
    func testATimeoutNamesTheDeadline() {
        XCTAssertEqual(vpnReadFailureReason(HelmProcess.timedOutStatus),
                       "timed out after \(Int(vpnReadDeadline)) s")
    }

    func testAnyOtherStatusNamesItself() {
        XCTAssertEqual(vpnReadFailureReason(1), "exit status 1")
        XCTAssertEqual(vpnReadFailureReason(-1), "exit status -1")
    }
}
