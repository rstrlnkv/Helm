// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// What the kernel says an interface has carried, and what of it goes on the
/// wire.
///
/// Both halves are facts of any Mac rather than of this one: `lo0` exists and
/// has carried something on every machine that has ever opened a socket, and an
/// interface nobody named does not exist anywhere. No magnitude is asserted —
/// the number belongs to the machine, and a test that expected one would be
/// asserting on this session's traffic.
final class TheCountersBelongToTheInterfaceTests: XCTestCase {

    func testLoopbackHasCarriedSomething() throws {
        let counters = try XCTUnwrap(VPNInterfaceCounters.bytes(on: "lo0"),
                                     "lo0 exists on every Mac; a nil here is the reader, "
                                     + "not the machine")
        XCTAssertGreaterThan(counters.in, 0)
        XCTAssertGreaterThan(counters.out, 0)
    }

    /// The answer for an interface that is not there is nil, not zero: a tunnel
    /// that has just gone has no counters, and drawing that as «0 bytes carried»
    /// is a measurement of something that never existed.
    func testAnInterfaceThatDoesNotExistAnswersNothing() {
        XCTAssertNil(VPNInterfaceCounters.bytes(on: "utun-nobody-made-this"))
    }

    // MARK: - What the wire carries

    /// The counters are the one field of the payload that moves on their own,
    /// and the engine withholds only a payload equal to the last one it sent —
    /// so a raw byte count would make every re-read news
    /// (`AnUnchangedStateIsSaidOnceTests` for what that costs). Whole kilobytes
    /// is the granularity the strip draws at: `HelmBytes` writes bytes exactly
    /// below a kilobyte and rounds to whole kilobytes above one.
    func testTheWireCarriesWholeKilobytes() {
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(0), 0)
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(499), 0)
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(500), 1000)
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(1499), 1000)
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(1_234_567), 1_235_000)
    }

    /// Rounded, not truncated, so the kilobyte the strip draws is the one the
    /// kernel counted: a floor would draw 1 KB where the Finder writes 2 KB.
    func testTheDrawnKilobyteIsTheKernelsOwn() {
        for bytes in stride(from: UInt64(0), to: 20_000, by: 137) {
            let expected = (Double(bytes) / 1000).rounded() * 1000
            XCTAssertEqual(Double(VPNInterfaceCounters.onTheWire(bytes)), expected,
                           "\(bytes) rounded to the wrong kilobyte")
        }
    }

    /// A counter near the top of its type is arithmetic nobody performs on
    /// purpose, and a trap in an engine is a crash in the app.
    func testACounterAtTheTopOfItsTypeDoesNotTrap() {
        XCTAssertEqual(VPNInterfaceCounters.onTheWire(.max), .max)
    }
}
