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

    /// **A port that answers nil to everything fails this.** A mistyped store
    /// key, or a `SCDynamicStoreCreate` that stops working on a later macOS, would
    /// otherwise leave the tile strip absent on every Mac with the suite green.
    ///
    /// The machine running the suite has a default route, or it is not on a
    /// network at all: `scutil -r` and `route -n get default` answer for the same
    /// store this reads. So the answer is required, and the nil below is required
    /// to stay nil — a port answering an interface for a service id nobody has
    /// would be inventing one.
    func testThePrimaryInterfaceIsThisMacsOwn() {
        let port = DynamicStoreInterfaces()

        let primary = try? XCTUnwrap(port.primaryInterface(),
                                     "the dynamic store named no default route on a Mac that "
                                     + "has one — the key this reads is `State:/Network/Global/"
                                     + "IPv4`, and the strip is absent for everybody if it is "
                                     + "wrong")
        XCTAssertEqual(primary?.isEmpty, false)
    }

    // MARK: - The speed run, without running the tool

    /// **A status of 0 is not a success here.** `networkQuality -c -I utun6`
    /// against a live tunnel prints this and **exits 0** — an error object, no
    /// throughput keys. What refuses it is the parser's «both throughput figures
    /// or nothing».
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
    /// runs; the tool times itself, so that length can be a fact about *this*
    /// person's link. Not a stage and not a fraction: the engine knows only
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
    /// A `now` that answers the same instant for ever is a run of exactly zero
    /// seconds, and an arc drawn against zero would be `HelmExpectedWait`'s «no
    /// claim» case reached by arithmetic. A length that is not positive is no
    /// length.
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
        let seen = Locked<[[String]]>([])
        let port = NetworkQualitySpeed(run: { args in
            seen.withLock { $0.append(args) }
            return HelmProcess.Result(status: 0, output: "")
        })
        _ = port.measure(onInterface: nil)
        _ = port.measure(onInterface: "utun6")
        XCTAssertEqual(seen.value, [["-c"], ["-c", "-I", "utun6"]])
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
