// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

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
}
