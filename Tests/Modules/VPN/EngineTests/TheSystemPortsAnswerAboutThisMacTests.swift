// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// The production ports, tested without a network: the trace parser is read
/// against text the endpoint really prints, and the dynamic store is asked about
/// this Mac, which answers whatever it answers.
final class TheSystemPortsAnswerAboutThisMacTests: XCTestCase {

    func testTheRegionIsReadFromTheTracesOwnLine() {
        let body = """
        fl=123abc
        ip=203.0.113.7
        ts=1755467000.123
        loc=NL
        """
        XCTAssertEqual(TraceExit.region(in: body), "NL")
    }

    /// A response without the line is not a country, and it is certainly not the
    /// address on the line above it.
    func testATraceWithoutALocationIsNoRegion() {
        XCTAssertNil(TraceExit.region(in: "fl=123abc\nip=203.0.113.7"))
    }

    func testAMalformedLocationIsRefused() {
        XCTAssertNil(TraceExit.region(in: "loc=XYZZY"))
        XCTAssertNil(TraceExit.region(in: "loc="))
    }

    /// This Mac has a default route while the suite runs, or it does not — both
    /// are legitimate answers, and what is asserted is that the port answers at
    /// all rather than crashing on a store it could not open.
    func testThePrimaryInterfaceIsReadWithoutThrowing() {
        let port = DynamicStoreInterfaces()
        let primary = port.primaryInterface()
        if let primary { XCTAssertFalse(primary.isEmpty) }
        XCTAssertNil(port.interface(forServiceID: "not-a-service-id"))
    }

    // MARK: - The speed run, without running the tool

    /// **A status of 0 is not a success here, and the code read it as one.**
    /// Measured on this machine, 2026-08-18: `networkQuality -c -I utun6`
    /// against a live tunnel prints this and **exits 0** — an error object, no
    /// throughput keys at all. The guard on the status would have let it
    /// through; what refuses it is the parser's «every field or nothing», and
    /// that is now a test rather than a thing somebody remembers.
    private static let minusOneThousandAndNine = """
    {"error_code": -1009, "error_domain": "NSURLErrorDomain", \
    "error_message": "A server with the specified hostname could not be found."}
    """

    func testARunThatExitedZeroWithNoThroughputIsNoReading() {
        let port = NetworkQualitySpeed(run: { _ in
            HelmProcess.Result(status: 0, output: Self.minusOneThousandAndNine)
        })
        XCTAssertNil(port.measure(onInterface: nil))
    }

    /// And the ordinary run does answer, so the refusal above is about the
    /// output rather than about a port that always says no.
    func testAnOrdinaryRunIsRead() {
        let at = Date(timeIntervalSince1970: 10_000)
        let port = NetworkQualitySpeed(now: { at }, run: { _ in
            HelmProcess.Result(status: 0, output:
                #"{"dl_throughput": 212345678, "ul_throughput": 95123456, "#
                + #""responsiveness": 850}"#)
        })
        XCTAssertEqual(port.measure(onInterface: nil)?.down, 212)
    }

    /// A tool that could not be launched at all answers nothing, whatever it
    /// printed on the way out.
    func testARunThatDidNotHappenIsNoReading() {
        let port = NetworkQualitySpeed(run: { _ in
            HelmProcess.Result(status: HelmProcess.timedOutStatus, output: "")
        })
        XCTAssertNil(port.measure(onInterface: nil))
    }

    /// The arguments the tool is actually given: machine-readable, and bound
    /// only when the caller named an interface.
    func testTheInterfaceIsOnTheCommandLineOnlyWhenThereIsOne() {
        let seen = ArgumentBox()
        let port = NetworkQualitySpeed(run: { args in
            seen.record(args)
            return HelmProcess.Result(status: 0, output: "")
        })
        _ = port.measure(onInterface: nil)
        _ = port.measure(onInterface: "utun6")
        XCTAssertEqual(seen.all, [["-c"], ["-c", "-I", "utun6"]])
    }
}

/// The arguments a run was given, across the thread it was given them on.
private final class ArgumentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [[String]] = []
    func record(_ args: [String]) { lock.lock(); seen.append(args); lock.unlock() }
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return seen }
}
