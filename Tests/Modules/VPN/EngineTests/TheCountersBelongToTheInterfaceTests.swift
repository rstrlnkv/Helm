// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// What the kernel says an interface has carried, and what of it goes on the
/// wire.
///
/// Both halves are facts of any Mac rather than of this one: `lo0` exists and
/// has carried something on every machine that has ever opened a socket, and an
/// interface nobody named does not exist anywhere. No magnitude is asserted of
/// the machine's own traffic — the number belongs to the machine, and a test
/// that expected one would be asserting on this session. The one magnitude that
/// is asserted comes from `netstat`, which reads the same kernel table from
/// outside the app, so it cannot be fooled by the reading under test.
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

    // MARK: - The counter is wider than the reading used to be

    /// **A counter past 4 GiB is drawn whole, not wrapped.** Measured on the
    /// owner's Mac, 2026-08-18: the strip said «Скачано 188 МБ» for a tunnel
    /// `netstat` gave 4 483 640 977 bytes — a difference of exactly 2^32,
    /// because `getifaddrs` hands back `struct if_data` whose `ifi_ibytes` is
    /// 32 bits wide. It wraps within a session on a tunnel carrying real
    /// traffic, so this is the ordinary case rather than an edge one.
    ///
    /// The oracle is `netstat -ibn`, which reads the kernel's counters from
    /// outside the app and so cannot be fooled by the reading under test: an
    /// assertion built from the app's own answer could not tell a wrapped
    /// counter from a small one. A machine whose
    /// interfaces have all stayed under 4 GiB cannot answer the question at
    /// all, and skips rather than passing — a skip is in the log, a vacuous
    /// pass is not.
    func testACounterPastFourGibibytesIsNotWrapped() throws {
        let carried = Self.whatNetstatSays()
        XCTAssertFalse(carried.isEmpty, "netstat -ibn named no interface at all")
        let wrapping = carried.filter { $0.value.in > Self.wrap || $0.value.out > Self.wrap }
        try XCTSkipIf(wrapping.isEmpty,
                      "no interface on this Mac has carried 4 GiB, so a wrapped 32-bit "
                      + "counter and a whole one read alike here")
        for (name, reference) in wrapping {
            let read = try XCTUnwrap(VPNInterfaceCounters.bytes(on: name),
                                     "netstat names \(name) and the reader does not")
            for (side, ours, theirs) in [("in", read.in, reference.in),
                                         ("out", read.out, reference.out)] {
                // Counters only climb, and the reference was taken first — so a
                // reading *below* it is the wrap, and a reading a whole 2^32
                // above it would be the same defect with the sign turned round.
                XCTAssertGreaterThanOrEqual(
                    ours, theirs,
                    "\(name) \(side): read \(ours) where netstat had already counted "
                    + "\(theirs) — a counter that went backwards is a 32-bit reading of a "
                    + "64-bit number")
                XCTAssertLessThan(ours, theirs + Self.wrap, "\(name) \(side) jumped a wrap")
                if theirs > Self.wrap {
                    XCTAssertGreaterThan(ours, Self.wrap,
                                         "\(name) \(side): \(theirs) bytes arrived as "
                                         + "\(ours), which does not fit in 32 bits either")
                }
            }
        }
    }

    /// The width is the whole defect, so the readings that are narrow are the
    /// guard: each of these is back on the page as a wrapped counter, and
    /// nothing about putting one back is a compile error.
    ///
    /// `getifaddrs` hands back a 32-bit `if_data`. `NET_RT_IFLIST2` declares an
    /// `if_data64` and is the repair everybody reaches for first — it is the
    /// one this fix reached for first — and the kernel fills its two byte
    /// counts from the 32-bit originals anyway, which is measured at the reader
    /// itself. What is left is the interface MIB, and `if_data64` is the struct
    /// it answers with.
    func testTheCountersAreReadFromTheSixtyFourBitTable() throws {
        let code = try RepoSource.lines(of: Self.source).map(RepoSource.code)
        // The absences below are only worth something over the right file, and
        // an empty read would satisfy every one of them.
        XCTAssertTrue(code.contains { $0.contains("ifi_ibytes") },
                      "the file scanned is not the one that reads the counters")
        XCTAssertTrue(code.contains { $0.contains("if_data64") },
                      "the counters no longer name if_data64, which is the only shape of "
                      + "these counts that the kernel fills at full width")
        let narrow = code.map { $0.replacingOccurrences(of: "if_data64", with: "") }
        for reading in ["if_data", "getifaddrs", "if_msghdr2", "NET_RT_IFLIST2"] {
            XCTAssertFalse(narrow.contains { $0.contains(reading) },
                           "\(reading) counts bytes in 32 bits — measured, both of them — so "
                           + "the strip draws a tunnel's 4,48 GB as 188 MB again")
        }
    }

    private static let source = "Sources/Modules/VPN/Engine/Logic/VPNInterfaceCounters.swift"
    private static let wrap = UInt64(UInt32.max) + 1

    /// What `netstat -ibn` has counted for every interface it names. The
    /// trailing seven columns are Ipkts, Ierrs, Ibytes, Opkts, Oerrs, Obytes,
    /// Coll — counted from the right because the Address column is empty for a
    /// `utun` and the leading ones therefore shift.
    private static func whatNetstatSays() -> [String: (in: UInt64, out: UInt64)] {
        let run = HelmProcess.run("/usr/sbin/netstat", ["-ibn"], timeout: 20)
        var totals: [String: (in: UInt64, out: UInt64)] = [:]
        for line in run.output.components(separatedBy: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 8, let name = fields.first.map(String.init),
                  let bytesIn = UInt64(fields[fields.count - 5]),
                  let bytesOut = UInt64(fields[fields.count - 2])
            else { continue }
            let seen = totals[name] ?? (0, 0)
            totals[name] = (max(seen.in, bytesIn), max(seen.out, bytesOut))
        }
        return totals
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
