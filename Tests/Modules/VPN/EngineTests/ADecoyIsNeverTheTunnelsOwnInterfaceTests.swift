// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **An `InterfaceName` inside an excluded route is never the tunnel's.**
///
/// A configuration's excluded routes carry `InterfaceName : en0` lines, the
/// decoys `VPNStatusParser` steps over. `scutil` prints the `IPv4` dictionary's
/// keys in order (`Addresses`, `ExcludedRoutes`, `InterfaceName`, ...), so the
/// decoys come before the line that overrules them, and a dictionary filled as
/// far as its excluded routes and no further (a tunnel a moment past
/// `Connected`, or output cut short) holds only decoys. «The shallowest one
/// seen» would then answer a decoy. Nil is the answer: the caller re-asks while
/// it is nil, but caches a non-nil reading for the life of the tunnel, so one
/// decoy would draw `en0`'s since-boot counters under «through the tunnel».
final class ADecoyIsNeverTheTunnelsOwnInterfaceTests: XCTestCase {

    /// The control: with the tunnel's line present the decoys are stepped over,
    /// so the test below cannot pass on a parser that reads no `InterfaceName`.
    func testTheTunnelsOwnLineStillWinsOverTheDecoys() throws {
        let reading = try XCTUnwrap(VPNStatusParser.reading(in: """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            ExcludedRoutes : <array> {
              0 : <dictionary> {
                DestinationAddress : 17.0.0.0
                InterfaceName : en0
                SubnetMask : 255.0.0.0
              }
            }
            InterfaceName : utun8
          }
          IsPrimaryInterface : 1
        }
        """))
        XCTAssertEqual(reading.interface, "utun8",
                       "precondition: the decoys are not being stepped over at all")
    }

    /// The same dictionary, cut off before the tunnel's own line, names no
    /// interface.
    func testAReadingWithOnlyDecoysInItNamesNoInterface() {
        let reading = VPNStatusParser.reading(in: """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            Addresses : <array> {
              0 : 10.10.0.2
            }
            ExcludedRoutes : <array> {
              0 : <dictionary> {
                DestinationAddress : 17.0.0.0
                InterfaceName : en0
                SubnetMask : 255.0.0.0
              }
        """)
        XCTAssertNil(reading?.interface, """
            a status read that never reached the tunnel's own `InterfaceName` \
            answered «\(reading?.interface ?? "")» — an interface named inside \
            an excluded route, which is by definition the one the traffic leaves \
            around the tunnel by. The caller caches any non-nil reading for the \
            life of the tunnel, so the tile then draws that interface's \
            since-boot counters under a green «traffic goes through the tunnel»
            """)
    }

    /// The same input with two decoys at different depths, so that a repair
    /// which merely prefers the shallowest **decoy** is still red: neither of
    /// them is the tunnel's.
    func testTheShallowestDecoyIsNotAnAnswerEither() {
        let reading = VPNStatusParser.reading(in: """
        Connected
        Extended Status <dictionary> {
          InterfaceName : en0
          IPv4 : <dictionary> {
            ExcludedRoutes : <array> {
              0 : <dictionary> {
                DestinationAddress : 10.0.0.0
                InterfaceName : en1
                SubnetMask : 255.0.0.0
              }
        """)
        XCTAssertNil(reading?.interface, """
            an `InterfaceName` outside the tunnel's own `IPv4` dictionary was \
            taken for the tunnel's because it was the shallowest one in the \
            output — the rule is «the tunnel's own line», and «the shallowest \
            line» is only the same thing while that line is present
            """)
    }
}
