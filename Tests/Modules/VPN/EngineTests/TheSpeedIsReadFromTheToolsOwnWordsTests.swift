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
}
