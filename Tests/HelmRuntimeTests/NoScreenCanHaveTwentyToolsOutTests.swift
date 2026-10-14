// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
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

    /// And the ceiling is a queue rather than a refusal for a run without a
    /// deadline: every such run asked for still runs, in its turn. A cap that
    /// dropped work would trade a crash for a screen that quietly shows less
    /// than it was asked to. A bounded run that gets no slot by its deadline is
    /// not run, and says so with `timedOutStatus`
    /// (`testABoundedRunQueuedBehindFullSlotsStillAnswersByItsDeadline`).
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

    /// A bounded run asked for while every slot is held answers by its own
    /// deadline. `launchCeiling` unbounded runs hold every slot for five
    /// seconds; one more is asked for with a half-second timeout and a tool
    /// that would answer at once if it ever started. The deadline is the
    /// caller's promise of how long it will wait, and queueing for a slot is
    /// waiting.
    ///
    /// **Every slot is released before the row ends**: each holder is an
    /// `exec`'d `sleep 5`, so it ends on its own, and the row waits for every
    /// holder's run to return before it finishes. The pids the holders wrote are
    /// removed at teardown if that wait was cut short.
    func testABoundedRunQueuedBehindFullSlotsStillAnswersByItsDeadline() throws {
        let ceiling = HelmProcess.launchCeiling
        let dir = scratchDirectory("slots-held")
        let holder = ScratchTool.script("""
            echo $$ > "$1/h$2"
            exec /bin/sleep 5
            """, named: "holds-a-slot", in: dir)
        let quick = ScratchTool.script("printf hi", named: "answers-at-once", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let group = DispatchGroup()
        for n in 0..<ceiling {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                _ = HelmProcess.run("/bin/sh", [holder, dir.path, String(n)])
            }
        }
        defer {
            XCTAssertEqual(group.wait(timeout: .now() + 30), .success,
                           "the slot holders never finished, so the next family queues behind them")
        }
        for n in 0..<ceiling {
            XCTAssertTrue(ScratchTool.waitForFile(dir.appendingPathComponent("h\(n)"), within: 20),
                          "holder \(n) never started, so the slots were not all held")
        }

        let asked = Date()
        let result = HelmProcess.run("/bin/sh", [quick], timeout: 0.5)
        let waited = Date().timeIntervalSince(asked)

        XCTAssertEqual(result.status, HelmProcess.timedOutStatus, """
            a run with a half-second deadline, asked for while all \(ceiling) slots \
            were held, answered \(result.status) \(result.output.debugDescription) \
            instead of a timeout
            """)
        XCTAssertLessThan(waited, 2.5, """
            a run with a half-second deadline came back after \(waited) s: its \
            deadline started when it got a slot, not when it was asked for
            """)
    }

    /// A bounded run that gets its slot late has only what is left of its
    /// deadline. `launchCeiling` unbounded runs hold every slot for three
    /// seconds; one more is asked for with a four-second timeout and a tool
    /// that never answers. The slot comes after about three seconds, so a run
    /// that counts its deadline from the call is back at about four, and one
    /// that counts it from the slot is back at about seven.
    ///
    /// Each holder is an `exec`'d `sleep 3`, so it ends on its own, and the row
    /// waits for every holder's run to return, under a clock deadline, before it
    /// finishes. The hanging tool is an `exec`'d `sleep 30` that the timeout
    /// terminates; its pid is removed at teardown if that did not happen.
    func testABoundedRunThatGetsItsSlotLateIsOwedOnlyWhatIsLeftOfItsDeadline() throws {
        let ceiling = HelmProcess.launchCeiling
        let dir = scratchDirectory("slots-held-late")
        let holder = ScratchTool.script("""
            echo $$ > "$1/h$2"
            exec /bin/sleep 3
            """, named: "holds-a-slot", in: dir)
        let hanging = ScratchTool.script("""
            echo $$ > "$1/hung"
            exec /bin/sleep 30
            """, named: "never-answers", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let group = DispatchGroup()
        for n in 0..<ceiling {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                _ = HelmProcess.run("/bin/sh", [holder, dir.path, String(n)])
            }
        }
        defer {
            XCTAssertEqual(group.wait(timeout: .now() + 30), .success,
                           "the slot holders never finished, so the next family queues behind them")
        }
        for n in 0..<ceiling {
            XCTAssertTrue(ScratchTool.waitForFile(dir.appendingPathComponent("h\(n)"), within: 20),
                          "holder \(n) never started, so the slots were not all held")
        }

        let asked = Date()
        let result = HelmProcess.run("/bin/sh", [hanging, dir.path], timeout: 4)
        let waited = Date().timeIntervalSince(asked)

        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "the tool never answers; the run was meant to time out")
        XCTAssertNotNil(ScratchTool.pid(dir.appendingPathComponent("hung")),
                        "the tool never started, so what was measured is the wait for a slot alone")
        XCTAssertLessThan(waited, 5.5, """
            a run with a four-second deadline, asked for while all \(ceiling) slots \
            were held for three, came back after \(waited) s: its deadline was \
            counted from the slot and not from the call
            """)
    }

    private final class LockedCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}
