import Foundation
import XCTest

/// What the drain is made of, in the unit each number is really in.
///
/// The ceiling is a count of passes and the rest is time, because the two are
/// answering different questions: `passes` is «this teardown will end», and the
/// pair below it is «how long a write may take to arrive and still be seen».
/// Priced against the suite: the settling readings are what every scratch
/// directory pays whether or not anything ever comes back, and `passes` is only
/// reached by a writer that keeps putting the directory back.
private enum Drain {
    /// Long enough to hand the thread over — a task waiting for one gets
    /// nothing from a yield — and short enough to be paid several hundred
    /// times: one full run of this suite makes over five hundred scratch
    /// directories, counted by instrumenting this function.
    static let pause: TimeInterval = 0.002
    /// Absent this many readings running before the drain believes it. One
    /// reading is what the 42 hand-written teardowns had, and 200 readings of
    /// no elapsed time is what replaced them.
    ///
    /// Eight of them are 25 ms of watching on this Mac — `Task.sleep` costs
    /// about 3.1 ms for a 2 ms request — against the 4.6 ms the yielding loop
    /// spent, and a writer that arrives 10 ms late is reclaimed where the old
    /// loop left it behind 10 runs out of 10. The price is that same 25 ms per
    /// scratch directory, on a suite whose slowest single test is 32 s.
    static let readingsThatSettleIt = 8
    /// The ceiling, in the unit the old loop counted in: a writer that keeps
    /// re-creating the directory is followed for about six hundred
    /// milliseconds and then reported rather than waited on for ever.
    static let passes = 200
}

/// A directory a test writes into, and the files it puts there.
///
/// This was written 42 times, in nine test targets, as the same four lines of
/// `setUp` and one line of `tearDown` — and the one line was wrong in a way
/// nobody could see by reading it.
public extension XCTestCase {

    /// A temporary directory that is really gone when the test is.
    ///
    /// **Removing it once is not enough, and 42 files used to do that.** A view
    /// model saves from a task of its own, so the removal can arrive before the
    /// write: `PrivateFile.directory` then makes the folder again and the file
    /// lands in it, after the test has finished and after the teardown block has
    /// run.
    ///
    /// Measured rather than reasoned about. One run of
    /// `StopLeavesNothingBehindTests` — which had a correct-looking
    /// `addTeardownBlock` beside its temporary directory all along — took
    /// `$TMPDIR` from 2282 `helm-disk-stop-…` directories to 2284, each holding
    /// exactly the scan file. Across that one module: **7621 directories, 69 MB**,
    /// of which 3091 were empty, which is the same race losing the other way.
    ///
    /// So the teardown drains instead of firing once. It removes, waits, and
    /// removes again, so a write landing anywhere in the window is reclaimed by
    /// a later pass — and it asserts at the end, because a teardown that cannot
    /// fail is how the 7621 accumulated. **The loop does not stop when the
    /// directory is gone**, only when it has *stayed* gone: gone now is not
    /// gone, and each wait is what gives a pending write its chance to arrive
    /// while somebody is still watching.
    ///
    /// **It waits on the clock and not on turns, and that is the repair of
    /// 2026-08-21.** The loop was `removeItem` + `Task.yield()`, two hundred
    /// times, and a yield buys a *turn* on the cooperative pool rather than any
    /// wall-clock time at all — so a machine with no turn to spare ran all two
    /// hundred passes before the detached writer was scheduled even once, and
    /// `ScratchDirectoryDrainTests` failed 1 run in 3 leaving 19 of its 20
    /// files behind. Measured on this Mac with nothing coming back: the two
    /// hundred yielding passes were **4.6 ms** of watching, fixed whatever the
    /// writer was doing. That is the whole window a starved write had to land
    /// in, and no number of extra passes widens it, because passes are not
    /// time. Two things change with a sleep: the thread is handed back, which
    /// is what a task waiting for one actually needs (`grace` above it says the
    /// same thing for the same reason), and the loop now ends on a condition —
    /// the directory absent across several separated readings — so a write that
    /// *does* arrive puts the count back to zero and is followed rather than
    /// missed.
    ///
    /// `ScratchDirectoryDrainTests` is what makes the count a rule. Until it
    /// existed `0..<200` could be `0..<1` — the shape all 42 hand-written
    /// teardowns had — with the whole suite still green, because nothing in it
    /// wrote into a scratch directory late enough to need a second pass. Note
    /// what that test had to do to see it: the assertion below can *pass* while
    /// the directory is left behind, since the write arrives after it, so the
    /// proof lives in a teardown registered before this one and therefore run
    /// after it.
    ///
    /// The directory is created before it is handed over, because a test that
    /// writes into it should not have to; a caller that wants it absent — a
    /// store that makes its own — is unaffected, since making it twice is not
    /// an error.
    func scratchDirectory(_ label: String,
                          file: StaticString = #filePath,
                          line: UInt = #line) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            let fm = FileManager.default
            var settled = 0
            for _ in 0..<Drain.passes {
                try? fm.removeItem(at: url)
                await grace(Drain.pause)
                settled = fm.fileExists(atPath: url.path) ? 0 : settled + 1
                if settled == Drain.readingsThatSettleIt { break }
            }
            try? fm.removeItem(at: url)
            XCTAssertFalse(fm.fileExists(atPath: url.path),
                           "the harness left \(url.lastPathComponent) behind",
                           file: file, line: line)
        }
        return url
    }

    /// A file of `bytes` filler at `relative` under `root`, with whatever
    /// directories it needs above it.
    ///
    /// The filler is a byte rather than a string because that is what these
    /// tests are about: how much a file weighs, whether two of them hash the
    /// same, whether a walk counted one twice. A test that cares what the file
    /// *says* writes its own contents — those are not this.
    @discardableResult
    func write(_ relative: String, in root: URL,
               bytes: Int = 4, filler: UInt8 = 0x41) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: filler, count: bytes).write(to: url)
        return url
    }
}
