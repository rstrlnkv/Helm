// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// What is up comes first, because from now on the page hides the tail.
///
/// The grid draws six cards and puts the rest behind «Show all». In the order
/// `scutil --nc list` hands back — which is the order the configurations were
/// made in, and nothing else — the connected tunnel can be the ninth, so the
/// one card the page exists to show would be the one a person cannot see. A cap
/// without an order is that defect; this is the order.
///
/// `isUp`, not `isConnected`: a handshake in flight is something happening on
/// this Mac, and the card that can cancel it belongs on screen while it runs.
final class ATunnelThatIsUpIsNeverHiddenTests: XCTestCase {

    private func conn(_ name: String, _ status: VPNStatus) -> VPNConnection {
        VPNConnection(id: name, name: name, status: status, kind: "IKEv2")
    }

    func testTheConnectedOneComesFirstHoweverLateItIs() {
        let list = (1...8).map { conn("VPN \($0)", $0 == 8 ? .connected : .disconnected) }
        XCTAssertEqual(VPNConnectionOrder.upFirst(list).first?.name, "VPN 8")
    }

    func testAHandshakeInFlightIsUpToo() {
        let list = [conn("a", .disconnected), conn("b", .disconnected), conn("c", .connecting)]
        XCTAssertEqual(VPNConnectionOrder.upFirst(list).map(\.name), ["c", "a", "b"])
    }

    func testEverythingElseKeepsTheOrderTheSystemGaveIt() {
        // Not sorted by name: the system's order is the order the person made
        // them in, and re-sorting the tail would move cards for no reason
        // whenever a tunnel came up.
        let list = [conn("zeta", .disconnected), conn("alpha", .disconnected),
                    conn("mid", .connected), conn("beta", .disconnected)]
        XCTAssertEqual(VPNConnectionOrder.upFirst(list).map(\.name),
                       ["mid", "zeta", "alpha", "beta"])
    }

    func testTwoTunnelsUpKeepTheirOwnOrder() {
        let list = [conn("a", .connected), conn("b", .disconnected), conn("c", .connected)]
        XCTAssertEqual(VPNConnectionOrder.upFirst(list).map(\.name), ["a", "c", "b"])
    }

    func testNothingIsLostOrDuplicated() {
        let list = (1...9).map { conn("VPN \($0)", $0 % 4 == 0 ? .connected : .disconnected) }
        let ordered = VPNConnectionOrder.upFirst(list)
        XCTAssertEqual(ordered.count, list.count)
        XCTAssertEqual(Set(ordered.map(\.name)), Set(list.map(\.name)))
    }
}
