// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime
import HelmTestSupport

/// How many tools Helm has out at once is bounded.
///
/// A repeatedly pressable control that starts a tool each press (one Homebrew
/// search is several `brew` runs of seconds each) would otherwise pile up
/// processes and threads parked on pipes until a launch kills the app.
/// `LatestRequest` stops a screen from asking; this is the floor under every
/// caller of `run` or `runData`, which may ask for more than `launchCeiling`
/// and gets a queue.
final class NoScreenCanHaveTwentyToolsOutTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The peak is cumulative until read, so anything an earlier test left
        // behind would be read here as this test's own load.
        _ = HelmProcess.peakLaunchesForTesting()
    }

    /// The two cases below measure against `launchCeiling`, so a ceiling raised
    /// to any number would pass them; the number itself is what the name of this
    /// class promises to keep under twenty.
    func testTheCeilingIsBelowTwenty() {
        XCTAssertLessThan(HelmProcess.launchCeiling, 20)
    }

    /// Twice the ceiling asked for at once, each holding its slot long enough
    /// that they would overlap if nothing stopped them.
    ///
    /// The precondition is that they really overlapped: tools that finished one
    /// after another satisfy any ceiling, so the peak must reach the cap first.
    func testTwiceTheCeilingAskedForAtOnceIsStillTheCeiling() {
        let asked = HelmProcess.launchCeiling * 2
        let group = DispatchGroup()
        for _ in 0..<asked {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                _ = HelmProcess.run("/bin/sleep", ["0.25"])
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success,
                       "the runs never finished, so the ceiling is a queue that does not drain")

        let peak = HelmProcess.peakLaunchesForTesting()
        XCTAssertLessThanOrEqual(peak, HelmProcess.launchCeiling, """
            \(asked) runs were asked for at once and \(peak) were out together — \
            the ceiling is \(HelmProcess.launchCeiling), and without one a page \
            that asks for twenty gets twenty
            """)
        XCTAssertGreaterThan(peak, 1, """
            the runs never overlapped at all (peak \(peak)), so this measured a \
            queue that happened to be idle rather than a ceiling
            """)
    }

    /// And the ceiling is a queue rather than a refusal: everything asked for
    /// still runs, in its turn. A cap that dropped work would trade a crash for
    /// a screen that quietly shows less than it was asked to.
    func testEverythingAskedForStillRuns() {
        let asked = HelmProcess.launchCeiling + 4
        let done = LockedCount()
        let group = DispatchGroup()
        for _ in 0..<asked {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                if HelmProcess.run("/bin/echo", ["x"]).status == 0 { done.bump() }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(done.value, asked,
                       "\(asked - done.value) of \(asked) runs were dropped rather than queued")
    }

}
