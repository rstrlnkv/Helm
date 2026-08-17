// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// `networkQuality -c` prints JSON in bits per second; the tile says megabits.
/// The conversion and the refusals live here, where they can be read.
final class TheSpeedIsReadFromTheToolsOwnWordsTests: XCTestCase {

    /// Captured from `/usr/bin/networkQuality -c` on macOS 27. Trimmed to the
    /// keys this parser reads — the tool prints more.
    private let real = """
    {"dl_throughput": 212345678, "ul_throughput": 95123456, "responsiveness": 850,
     "dl_flows": 16, "ul_flows": 16, "interface_name": "utun4"}
    """

    private let at = Date(timeIntervalSince1970: 10_000)

    func testBitsPerSecondBecomeMegabits() {
        let reading = VPNSpeedReading.parse(real, at: at)
        XCTAssertEqual(reading?.down, 212)
        XCTAssertEqual(reading?.up, 95)
        XCTAssertEqual(reading?.rpm, 850)
        XCTAssertEqual(reading?.at, at)
    }

    /// A tool that was killed at the deadline prints nothing. Nil, never zero:
    /// «0 Мбит/с» is a claim about the link, and the truth is that nobody knows.
    func testAnEmptyAnswerIsNoReading() {
        XCTAssertNil(VPNSpeedReading.parse("", at: at))
    }

    /// Half an answer is no answer: the tool interrupted mid-run has printed a
    /// download figure and no upload, and a tile saying «212 ↓ 0 ↑» is wrong
    /// about the half it did not measure.
    func testAPartialAnswerIsRefused() {
        XCTAssertNil(VPNSpeedReading.parse(#"{"dl_throughput": 212345678}"#, at: at))
    }

    func testRubbishIsRefused() {
        XCTAssertNil(VPNSpeedReading.parse("networkQuality: command failed", at: at))
    }

    /// **The tool omits `responsiveness` on a link it could not characterise**,
    /// and this used to read that absence as `0 rpm` — a figure, in the type
    /// whose own rule is «every field or nothing». Nobody measured a
    /// responsiveness of zero; nobody measured one at all.
    func testALinkWithNoResponsivenessFigureHasNone() {
        let reading = VPNSpeedReading.parse(
            #"{"dl_throughput": 212345678, "ul_throughput": 95123456}"#, at: at)
        XCTAssertEqual(reading?.down, 212)
        XCTAssertNil(reading?.rpm, "0 rpm is a claim about a link nobody characterised")
    }

    /// A number the tool should never print, in the function whose whole job is
    /// not trusting what it printed. `Int(_: Double)` **traps** on a value
    /// outside `Int`'s range, so refusing it is the difference between a nil
    /// and the app going down on a line of JSON. `1e30` bits per second is
    /// nonsense a text stream can carry and `Double` can hold.
    func testAThroughputTooLargeForTheTypeIsRefused() {
        XCTAssertNil(VPNSpeedReading.parse(
            #"{"dl_throughput": 1e30, "ul_throughput": 95123456}"#, at: at))
        XCTAssertNil(VPNSpeedReading.parse(
            #"{"dl_throughput": 212345678, "ul_throughput": 1e30}"#, at: at))
        XCTAssertNil(VPNSpeedReading.parse(
            #"{"dl_throughput": 212345678, "ul_throughput": 95123456, "#
            + #""responsiveness": 1e30}"#, at: at))
    }

    /// Nobody measured a negative link either.
    func testANegativeThroughputIsRefused() {
        XCTAssertNil(VPNSpeedReading.parse(
            #"{"dl_throughput": -212345678, "ul_throughput": 95123456}"#, at: at))
    }
}
