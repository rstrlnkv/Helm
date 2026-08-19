// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// **Nothing bounded how many tools Helm had out at once, and one screen found
/// out.**
///
/// Homebrew's search field put every press of Return on its own unbounded
/// `Task`, and one press is two `brew search` runs of about nine seconds
/// followed by a `brew desc` per kind. Ten presses were twenty-odd Ruby
/// processes: the crash report shows ten threads inside one `brew` call and
/// nine more parked on a pipe, and the thread that started the twenty-first is
/// where the app died.
///
/// `HomebrewViewModel`'s `LatestRequest` stops that screen from asking. This is
/// the floor under every screen not yet written — a caller may still ask for
/// more than `launchCeiling`, and what it gets is a queue.
final class NoScreenCanHaveTwentyToolsOutTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The peak is cumulative until read, so anything an earlier test left
        // behind would be read here as this test's own load.
        _ = HelmProcess.peakLaunchesForTesting()
    }

    /// Twice the ceiling asked for at once, each holding its slot long enough
    /// that they would overlap if nothing stopped them.
    ///
    /// **The precondition is that they really did overlap** — a run of twelve
    /// tools that happened to finish one after another would satisfy any
    /// ceiling and prove nothing, so the peak has to reach the cap before the
    /// assertion that it does not pass it means anything.
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

    private final class LockedCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}
