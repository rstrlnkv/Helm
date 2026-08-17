// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import XCTest

/// **A construction that forgets a port takes the real one, and the real ones
/// here reach the network.**
///
/// `VPNEngine.init` defaults `interfaces` to the dynamic store, `exit` to a
/// request to a server and `speed` to a subprocess that runs for fifteen seconds
/// under load. Eleven `AutopilotEngine` tests took a default that turned out to
/// be the owner's own keychain and rolled their real rules back; the recorded
/// lesson is to name the fake at every construction, and nothing was checking
/// that anybody had (CLAUDE.md § a default argument naming a real port).
///
/// Read off the source rather than the behaviour, because the defect is
/// invisible in a passing run: a test that quietly asked Cloudflare where this
/// Mac is still goes green.
final class NoTestTakesAProductionPortTests: XCTestCase {

    private let required = ["interfaces:", "exit:", "speed:"]
    /// Spelled in two halves so this file is not its own first offender — it
    /// reported itself on the run that found it, which is the scan working.
    private let construction = "VPNEngine" + "("

    func testEveryEngineInThisTargetNamesItsThreeNetworkPorts() throws {
        var constructions = 0
        var offenders: [String] = []
        for file in try RepoSource.swiftFiles(under: "Tests/Modules/VPN/EngineTests") {
            let lines = try RepoSource.lines(of: file)
            for (index, line) in lines.enumerated()
            where RepoSource.code(line).contains(construction) {
                constructions += 1
                // The argument list, however it is wrapped: the widest of these
                // calls runs to five lines.
                let call = lines[index..<min(index + 8, lines.count)].joined(separator: " ")
                let missing = required.filter { !call.contains($0) }
                if !missing.isEmpty {
                    offenders.append("\(file):\(index + 1) — "
                                     + "no \(missing.joined(separator: ", "))")
                }
            }
        }
        XCTAssertGreaterThan(constructions, 20,
                             "only \(constructions) engines were found in this target, so a "
                             + "pass proves nothing — the scan is reading the wrong place")
        XCTAssertTrue(offenders.isEmpty,
                      "an engine built without naming its network ports takes the production "
                      + "one: a request to a server, or `networkQuality` for fifteen seconds, "
                      + "from a unit test:\n" + offenders.joined(separator: "\n"))
    }
}
