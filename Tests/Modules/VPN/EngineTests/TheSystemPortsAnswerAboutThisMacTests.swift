// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmTestSupport
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

    /// **A port that answered nil to everything used to pass this.** The only
    /// positive assertion sat inside `if let primary`, and the other line
    /// asserts an absence — so a mistyped store key, or a `SCDynamicStoreCreate`
    /// that stopped working on a later macOS, would leave the tile strip absent
    /// on every Mac with the suite green.
    ///
    /// The machine running the suite has a default route, or it is not on a
    /// network at all and has bigger problems than this assertion: `scutil -r`
    /// and `route -n get default` answer for the same store this reads. So the
    /// answer is required, and the nil below is required to stay nil — a port
    /// answering an interface for a service id nobody has would be inventing
    /// one.
    func testThePrimaryInterfaceIsThisMacsOwn() {
        let port = DynamicStoreInterfaces()

        let primary = try? XCTUnwrap(port.primaryInterface(),
                                     "the dynamic store named no default route on a Mac that "
                                     + "has one — the key this reads is `State:/Network/Global/"
                                     + "IPv4`, and the strip is absent for everybody if it is "
                                     + "wrong")
        XCTAssertEqual(primary?.isEmpty, false)
    }

    /// **The store's service ids are not the ids the module has.** This is the
    /// defect that shipped, as a fact about the machine rather than a story: the
    /// identifiers in `scutil --nc list` are configurations', the store is keyed
    /// by network service, and asking it with the wrong one answers nil for
    /// every NetworkExtension tunnel. What replaced that lookup is
    /// `VPNStatusParser` over `scutil --nc status <name>`, and this only pins
    /// that the store is no longer asked a question it cannot answer.
    func testTheStoreIsNotAskedAboutConfigurationIdsAnyMore() throws {
        let port = DynamicStoreInterfaces()
        let members = Mirror(reflecting: port as Any).children.compactMap(\.label)
        XCTAssertFalse(members.contains("interface"))
        // Comments stripped first: the reason this rule exists is written in
        // that file, and it quotes the key — a scan that reads comments reports
        // the explanation as the offence.
        let code = try RepoSource.lines(of: "Sources/Modules/VPN/Engine/SystemPorts.swift")
            .map(RepoSource.code)
        XCTAssertFalse(code.contains { $0.contains("State:/Network/Service/") },
                       "the dynamic store is being asked by service id again, with an id that "
                       + "names a configuration — the strip is then absent on every Mac")
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

    /// **A reading carries how long it took to take.**
    ///
    /// The page draws an arc against an expected length while a measurement
    /// runs, and that length was a constant in a view — 22 s, measured on one
    /// Mac on one link on one afternoon. The tool already times itself here, so
    /// the number the arc is drawn against can be a fact about *this* person's
    /// link instead. Not a stage and not a fraction: the engine still knows only
    /// whether a run is in flight (`VPNEngine.measuringSpeed`), and this is the
    /// length of the last one.
    func testAReadingCarriesHowLongItsRunTook() {
        let clock = ClockBox([Date(timeIntervalSince1970: 10_000),
                              Date(timeIntervalSince1970: 10_019)])
        let port = NetworkQualitySpeed(now: clock.next, run: { _ in
            HelmProcess.Result(status: 0, output:
                #"{"dl_throughput": 212345678, "ul_throughput": 95123456}"#)
        })
        let reading = port.measure(onInterface: nil)
        XCTAssertEqual(reading?.took, 19)
        XCTAssertEqual(reading?.at, Date(timeIntervalSince1970: 10_019), """
            the reading is stamped when the run began rather than when it             answered, so a twenty-second measurement is twenty seconds old the             moment it lands
            """)
    }

    /// **A clock that does not move is not a run of no length.**
    ///
    /// Every other test in this file injects a `now` that answers the same
    /// instant for ever, which is a run of exactly zero seconds — and an arc
    /// drawn against zero is `HelmExpectedWait`'s own «no claim» case, reached
    /// by arithmetic rather than by anybody deciding it. A length that is not
    /// positive is no length.
    func testARunWithNoLengthCarriesNone() {
        let at = Date(timeIntervalSince1970: 10_000)
        let port = NetworkQualitySpeed(now: { at }, run: { _ in
            HelmProcess.Result(status: 0, output:
                #"{"dl_throughput": 212345678, "ul_throughput": 95123456}"#)
        })
        XCTAssertNil(port.measure(onInterface: nil)?.took)
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

/// A clock handed out one reading at a time, so a test can say what the tool
/// took: the port asks `now` twice and a constant closure makes every run
/// instantaneous.
private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [Date]
    private var last: Date

    init(_ dates: [Date]) {
        remaining = dates
        last = dates.last ?? Date()
    }

    /// The next stamp, and the final one for ever after — a port that asked a
    /// third time must get an answer rather than a crash.
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        guard !remaining.isEmpty else { return last }
        return remaining.removeFirst()
    }
}

/// The arguments a run was given, across the thread it was given them on.
private final class ArgumentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [[String]] = []
    func record(_ args: [String]) { lock.lock(); seen.append(args); lock.unlock() }
    var all: [[String]] { lock.lock(); defer { lock.unlock() }; return seen }
}
