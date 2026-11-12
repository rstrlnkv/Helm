// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest

/// **A construction that forgets a port takes the real one, and the real ones
/// here reach the network.**
///
/// `VPNEngine.init` defaults `interfaces` to the dynamic store, `exit` to a request
/// to a server and `speed` to a subprocess that runs for fifteen seconds under
/// load. Eleven `AutopilotEngine` tests took a default that turned out to be the
/// owner's own keychain and rolled their real rules back; the recorded lesson is to
/// name the fake at every construction, and nothing was checking that anybody had
/// (CLAUDE.md § What not to do, and what breaks if you do).
///
/// Read off the source rather than the behaviour, because the defect is
/// invisible in a passing run: a test that quietly asked Cloudflare where this
/// Mac is still goes green.
final class NoTestTakesAProductionPortTests: XCTestCase {

    func testEveryVPNEngineUnderTheVPNTestsNamesItsThreeNetworkPorts() throws {
        try PortsAtConstruction.check("VPNEngine", under: "Tests/Modules/VPN",
                                      naming: ["interfaces", "exit", "speed"], atLeast: 50)
    }
}
