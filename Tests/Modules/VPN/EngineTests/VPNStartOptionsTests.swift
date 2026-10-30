// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SystemConfiguration
@testable import Module_VPN_Engine

/// What each kind of tunnel is handed in place of `--user`, `--password` and
/// `--secret`. The keys are the SystemConfiguration constants' values, spelled
/// out here on purpose: a test that read them from the same constants would
/// pass whatever they were.
final class VPNStartOptionsTests: XCTestCase {

    private let all = VPNCredentials(user: "u", password: "p", secret: "s")

    func testL2TPCarriesThePPPLoginAndTheIPSecSecret() {
        XCTAssertEqual(VPNStartOptions.userOptions(all, interface: "PPP", inner: "L2TP"),
                       ["PPP": ["AuthName": "u", "AuthPassword": "p"],
                        "IPSec": ["SharedSecret": "s"]])
    }

    func testIPSecCarriesTheXAuthLoginAndTheSecretTogether() {
        XCTAssertEqual(VPNStartOptions.userOptions(all, interface: "IPSec", inner: nil),
                       ["IPSec": ["XAuthName": "u", "XAuthPassword": "p", "SharedSecret": "s"]])
    }

    func testEmptyAndMissingFieldsAreLeftOut() {
        XCTAssertEqual(VPNStartOptions.userOptions(VPNCredentials(user: "", password: nil, secret: "s"),
                                                   interface: "PPP", inner: "L2TP"),
                       ["IPSec": ["SharedSecret": "s"]])
        XCTAssertEqual(VPNStartOptions.userOptions(VPNCredentials(), interface: "IPSec", inner: nil), [:])
    }

    /// What `scutil`'s own `nc_start` puts for a plugin VPN: `VPN` →
    /// `AuthName`, `AuthPassword`, and nothing of IPSec's.
    func testAPluginVPNCarriesItsOwnLoginAndNoSecret() {
        XCTAssertEqual(VPNStartOptions.userOptions(all, interface: "VPN", inner: nil),
                       ["VPN": ["AuthName": "u", "AuthPassword": "p"]])
    }

    /// A PPP service that is not L2TP gets the PPP login and no IPSec entry,
    /// as `scutil` does.
    func testPlainPPPCarriesOnlyThePPPLogin() {
        let expected = ["PPP": ["AuthName": "u", "AuthPassword": "p"]]
        XCTAssertEqual(VPNStartOptions.userOptions(all, interface: "PPP", inner: nil), expected)
        XCTAssertEqual(VPNStartOptions.userOptions(all, interface: "PPP", inner: "PPTP"), expected)
    }

    func testAnUnknownTypeStartsWithoutOptions() {
        XCTAssertNil(VPNStartOptions.userOptions(all, interface: "WireGuard", inner: nil))
        XCTAssertNil(VPNStartOptions.userOptions(all, interface: "", inner: nil))
    }
}
