// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest

/// **A construction that forgets a port takes the real one, and the real ones
/// here reach the network.**
///
/// `VPNEngine.init` defaults `interfaces` to the dynamic store, `exit` to a
/// request to a server and `speed` to a subprocess that runs for many seconds
/// under load. The rule is to name the fake at every construction
/// (Architecture/TestsAndMeasurement.md § Fakes).
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
