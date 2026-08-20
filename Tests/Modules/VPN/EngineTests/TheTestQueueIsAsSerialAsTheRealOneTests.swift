// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **`VPNWorkQueue.inline` is not a queue, and the thing it stands for is one.**
///
/// `.background` is `DispatchQueue(label: "helm.vpn")` and its own comment says
/// why it is serial: «the commands it sends to `scutil` still have to arrive in
/// the order they were asked for». `.inline` runs the block on whatever thread
/// handed it over, which is the same thread for everything a test drives
/// directly — and a **different** one for the two pieces of work that leave the
/// module and come back through `work.run`: `checkExit`'s completion and
/// `startMeasuring`'s. Under `.background` those arrive behind the refresh that
/// started them. Under `.inline` they arrive *inside* it, on another thread,
/// which is the one thing the real queue rules out.
///
/// So this is CLAUDE.md § «A fake can also be freer than the port», read of the
/// queue itself: the fake admits a state the real one cannot produce, and every
/// test in this module is written against the fake.
///
/// **What it costs, measured.** `emitState` compares and stamps `_lastEmitted`
/// under the lock and then emits *outside* it. Two callers with the same payload
/// therefore produce exactly one emission — the loser publishes nothing — and
/// the winner's `emit` lands whenever its thread is next scheduled, which can be
/// after the test has already read the wire. Measured on a two-tunnel fixture
/// with an exit port that answers, same binary, five consecutive processes: the
/// refresh's state reached the transport in two of them and in three it did not.
/// The failure that produces is «the engine said nothing», which reads as a
/// defect in the subject rather than in the harness — the shape CLAUDE.md
/// records for Autopilot's `folders` getter, «7 failures in 70 and never twice
/// in a row». Commit 4a3d2b81 repaired four tests in this module for a
/// neighbouring reason and this one was still under them.
///
/// **The shipped app is not exposed**: `.background` is serial, so there is only
/// ever one caller inside `emitState`. What is exposed is the suite.
///
/// The occupancy below is asserted rather than counted over repetitions,
/// because the window in the engine is a handful of instructions wide and a
/// repetition count large enough to catch it reliably is a threshold nobody can
/// justify. Two callers or one is a structure, and structure does not need luck.
final class TheTestQueueIsAsSerialAsTheRealOneTests: XCTestCase {

    /// How many blocks were inside the queue at once, at the most.
    ///
    /// Under its own lock: the whole point is that two threads reach it.
    private final class Occupancy: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private var _peak = 0
        private var _entries = 0

        func enter() {
            lock.lock(); current += 1; _entries += 1; _peak = max(_peak, current); lock.unlock()
        }
        func leave() { lock.lock(); current -= 1; lock.unlock() }
        /// The most that were ever inside together. One is a serial queue.
        var peak: Int { lock.lock(); defer { lock.unlock() }; return _peak }
        /// How many ran at all — the precondition, so «never two at once» cannot
        /// be satisfied by a queue that ran nothing.
        var entries: Int { lock.lock(); defer { lock.unlock() }; return _entries }
    }

    /// Hands the queue two blocks from two threads, the first of which is still
    /// inside when the second is offered.
    ///
    /// The first block parks on a semaphore rather than sleeping: the second is
    /// offered only once the first has signalled that it is in, so «they
    /// overlapped» is a fact about the queue and never about how long anything
    /// took.
    private func peakOccupancy(of queue: VPNWorkQueue) -> Occupancy {
        let occupancy = Occupancy()
        let firstIsIn = DispatchSemaphore(value: 0)
        let letTheFirstGo = DispatchSemaphore(value: 0)
        let bothDone = DispatchGroup()

        bothDone.enter()
        DispatchQueue.global().async {
            // The group is left **inside** the block, not after `run` returns:
            // `.background` returns the instant the block is enqueued, so
            // leaving outside would say «both finished» before either had
            // started — a wait that answers about nothing.
            queue.run {
                occupancy.enter()
                firstIsIn.signal()
                letTheFirstGo.wait()
                occupancy.leave()
                bothDone.leave()
            }
        }
        XCTAssertEqual(firstIsIn.wait(timeout: .now() + 5), .success,
                       "precondition: the first block never ran, so nothing below means anything")

        bothDone.enter()
        DispatchQueue.global().async {
            queue.run {
                occupancy.enter()
                occupancy.leave()
                bothDone.leave()
            }
        }
        // Long enough for a queue that does not serialise to have finished the
        // second block; a queue that does serialise is still holding it, and the
        // release below is what lets it through.
        Thread.sleep(forTimeInterval: 0.2)
        letTheFirstGo.signal()
        XCTAssertEqual(bothDone.wait(timeout: .now() + 5), .success,
                       "precondition: a block never came back, so the reading is incomplete")
        return occupancy
    }

    /// The queue the app runs on. This is the behaviour `.inline` stands in for,
    /// asserted here so the expectation below is the real one's and not this
    /// test's opinion.
    func testTheQueueTheAppUsesAdmitsOneBlockAtATime() {
        let occupancy = peakOccupancy(of: .background)
        XCTAssertEqual(occupancy.entries, 2, "precondition: both blocks did not run")
        XCTAssertEqual(occupancy.peak, 1,
                       "the module's own queue is documented serial and let two blocks in at once")
    }

    /// **The finding.** The queue every test in this module runs on lets two in.
    func testTheQueueEveryTestUsesAdmitsOneBlockAtATime() {
        let occupancy = peakOccupancy(of: .inline)
        XCTAssertEqual(occupancy.entries, 2, "precondition: both blocks did not run")
        XCTAssertEqual(occupancy.peak, 1, """
            `VPNWorkQueue.inline` ran a second block while the first was still \
            inside, which `.background` cannot do — so the exit check's \
            completion and the speed run's land *inside* the refresh that \
            started them instead of behind it, two callers reach `emitState`, \
            and one of the two payloads is withheld as a duplicate of the other \
            with the survivor emitted from a thread the test has already run past
            """)
    }
}
