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
    /// nothing from a yield — and short enough to be paid once per scratch
    /// directory, of which a full run makes several hundred.
    static let pause: TimeInterval = 0.002
    /// Absent this many readings running before the drain believes it. Eight
    /// are about 25 ms of watching, enough for a writer that arrives 10 ms late
    /// to be reclaimed; the price is that same 25 ms per scratch directory.
    static let readingsThatSettleIt = 8
    /// The ceiling: a writer that keeps re-creating the directory is followed
    /// for a bounded number of passes and then reported rather than waited on
    /// for ever.
    static let passes = 200
}

/// A directory a test writes into, and the files it puts there.
///
/// Every test that needs a folder gets it here; `scratchDirectory` says how its
/// removal is done.
public extension XCTestCase {

    /// A temporary directory that is really gone when the test is.
    ///
    /// **Removing it once is not enough.** A view
    /// model saves from a task of its own, so the removal can arrive before the
    /// write: `PrivateFile.directory` then makes the folder again and the file
    /// lands in it, after the test has finished and after the teardown block has
    /// run.
    ///
    /// So the teardown drains instead of firing once. It removes, waits, and
    /// removes again, so a write landing anywhere in the window is reclaimed by
    /// a later pass — and it asserts at the end, because a teardown that cannot
    /// fail is how directories accumulate unseen. **The loop does not stop when
    /// the directory is gone**, only when it has *stayed* gone: gone now is not
    /// gone, and each wait is what gives a pending write its chance to arrive
    /// while somebody is still watching.
    ///
    /// **It waits on the clock and not on turns.** A yield buys a turn on the
    /// cooperative pool rather than any wall-clock time, so a machine with no
    /// turn to spare runs every pass before a detached writer is scheduled even
    /// once, and no number of extra passes widens that window, because passes
    /// are not time. A sleep hands the thread back, which is what a task waiting
    /// for one needs (`grace` says the same for the same reason), and the loop
    /// ends on a condition — the directory absent across several separated
    /// readings — so a write that *does* arrive puts the count back to zero and
    /// is followed rather than missed.
    ///
    /// Nothing in the suite guards the count: the assertion below can *pass*
    /// while a late write leaves the directory behind, since the write arrives
    /// after it, and a test of that has to read in a teardown registered before
    /// this one, which therefore runs after it.
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

    /// Every path under `root`, relative and sorted: a folder described by its
    /// contents rather than by a count of them, the only description a race
    /// cannot satisfy by accident.
    func tree(under root: URL) -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }
}
