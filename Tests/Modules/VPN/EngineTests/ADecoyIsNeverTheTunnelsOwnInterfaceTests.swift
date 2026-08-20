// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **«The outermost `InterfaceName` wins» is implemented as «the shallowest one
/// seen», and those differ when the tunnel's own line is not there.**
///
/// `VPNStatusParser` spends a paragraph on the seven `InterfaceName : en0` lines
/// a configuration's excluded routes carry, and calls them the decoys: «A parser
/// taking the first match answers `en0`, the verdict then compares `en0` against
/// a primary interface of `utun8` and the page says «traffic is not going
/// through the tunnel» on a Mac where it is: a false alarm in the one sentence
/// this feature exists to get right.»
///
/// The walk it built answers the decoy anyway whenever the tunnel's own line is
/// absent, because the winner is «the shallowest of whatever turned up» and a
/// decoy that is the only candidate is the shallowest candidate. There is no
/// state in `Reading` for «I saw interfaces, and none of them was the tunnel's»,
/// so the function cannot say it.
///
/// **How the input arises.** `scutil` prints a dictionary's keys in order, and
/// in the `IPv4` dictionary that order is `Addresses`, `ExcludedRoutes`,
/// `InterfaceName`, `Router`, `ServerAddress` — the decoys come **before** the
/// line that overrules them. So any `IPv4` dictionary that is populated as far
/// as its excluded routes and no further is this input: a tunnel a moment past
/// `Connected` whose `utunN` has not been filed yet, which is precisely the
/// state the parser's caller already expects («a tunnel that is still coming up
/// names no interface yet, and the next refresh asks again»). It is also what
/// output cut short at any point inside `ExcludedRoutes` looks like.
///
/// **And the wrong answer is then permanent.** `VPNEngine.readInterfaces` caches
/// a reading that is not nil for the whole life of the tunnel — it re-asks only
/// while the answer is nil — so one transient read of `en0` is a tile that draws
/// `en0`'s byte counters (which count since boot, the trap the design spec names
/// by name) under a verdict of `.throughTunnel` whenever the default route is
/// also `en0`. A green tick, a country, and a throughput figure, all about the
/// interface the traffic is leaving the tunnel *by*.
///
/// Nil is the answer, and the caller is already written for it.
final class ADecoyIsNeverTheTunnelsOwnInterfaceTests: XCTestCase {

    /// The control, and it is the committed fixture's own shape: with the
    /// tunnel's line present the decoys are stepped over. Run first so the
    /// assertion below cannot be satisfied by a parser that has stopped reading
    /// `InterfaceName` at all.
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

    /// **The finding.** The same dictionary, cut off before the tunnel's own
    /// line, and the parser answers the interface the traffic leaves *around*
    /// the tunnel by.
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
