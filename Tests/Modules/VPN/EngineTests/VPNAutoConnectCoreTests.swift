// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

final class VPNAutoConnectCoreTests: XCTestCase {
    func test_launch_connects_on_first_and_not_again() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V"), "b": VPNAppRule(vpnName: "V")])
        var connects: [String] = []
        core.appLaunched("a", connect: { connects.append($0) }, disconnect: { _ in })
        core.appLaunched("b", connect: { connects.append($0) }, disconnect: { _ in })
        XCTAssertEqual(connects, ["V"])
    }
    func test_quit_disconnects_only_when_last_leaves() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V"), "b": VPNAppRule(vpnName: "V")])
        core.appLaunched("a", connect: { _ in }, disconnect: { _ in })
        core.appLaunched("b", connect: { _ in }, disconnect: { _ in })
        var disc: [String] = []
        core.appTerminated("a", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(disc, [])
        core.appTerminated("b", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(disc, ["V"])
    }
    func test_flags_respected() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V", connectOnLaunch: false, disconnectOnQuit: false)])
        var connects: [String] = [], disc: [String] = []
        core.appLaunched("a", connect: { connects.append($0) }, disconnect: { _ in })
        core.appTerminated("a", connect: { _ in }, disconnect: { disc.append($0) })
        XCTAssertEqual(connects, []); XCTAssertEqual(disc, [])
    }
    func test_unmapped_app_ignored() {
        var core = VPNAutoConnectCore(rules: [:])
        var n = 0
        core.appLaunched("x", connect: { _ in n += 1 }, disconnect: { _ in n += 1 })
        XCTAssertEqual(n, 0)
    }
    func test_activeVPNs() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V")])
        core.appLaunched("a", connect: { _ in }, disconnect: { _ in })
        XCTAssertEqual(core.activeVPNs, ["V"])
        core.appTerminated("a", connect: { _ in }, disconnect: { _ in })
        XCTAssertTrue(core.activeVPNs.isEmpty)
    }
}
