// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// **`VPNWorkQueue.inline` is serial, as the queue it stands for is.**
///
/// `.background` is a serial `DispatchQueue`, because the commands sent to
/// `scutil` have to arrive in the order they were asked for. Two pieces of work
/// leave the module and come back through `work.run` from another thread —
/// `checkExit`'s completion and `startMeasuring`'s. Under `.background` they
/// arrive behind the refresh that started them; a fake that ran them *inside*
/// it would admit a state the real queue cannot produce
/// (Architecture/TestsAndMeasurement.md § Fakes).
///
/// What that would cost: `emitState` compares and stamps `_lastEmitted` under
/// the lock and emits *outside* it, so two callers with one payload produce one
/// emission, landing whenever its thread is next scheduled — «the engine said
/// nothing», read as a defect in the subject rather than in the harness. The
/// shipped app is not exposed; the suite would be.
///
/// The occupancy below is asserted rather than counted over repetitions:
/// the window in the engine is a handful of instructions wide, and two callers
/// or one is a structure, which does not need luck.
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
    private func peakOccupancy(of queue: VPNWorkQueue) async -> Occupancy {
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
        await grace(0.2)
        letTheFirstGo.signal()
        XCTAssertEqual(bothDone.wait(timeout: .now() + 5), .success,
                       "precondition: a block never came back, so the reading is incomplete")
        return occupancy
    }

    /// The queue the app runs on. This is the behaviour `.inline` stands in for,
    /// asserted here so the expectation below is the real one's and not this
    /// test's opinion.
    func testTheQueueTheAppUsesAdmitsOneBlockAtATime() async {
        let occupancy = await peakOccupancy(of: .background)
        XCTAssertEqual(occupancy.entries, 2, "precondition: both blocks did not run")
        XCTAssertEqual(occupancy.peak, 1,
                       "the module's own queue is documented serial and let two blocks in at once")
    }

    /// **The guard.** The queue every test in this module runs on lets one in at a time.
    func testTheQueueEveryTestUsesAdmitsOneBlockAtATime() async {
        let occupancy = await peakOccupancy(of: .inline)
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
