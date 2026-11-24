import Foundation
import XCTest

/// What the drain is made of, in the unit each number is really in.
///
/// The ceiling is a count of passes and the rest is time: `passes` says «this
/// teardown will end», the pair below it «how long a write may take to arrive
/// and still be seen». Every scratch directory pays the settling readings;
/// `passes` is reached only by a writer that keeps putting the directory back.
private enum Drain {
    /// Long enough to hand the thread over — a task waiting for one gets
    /// nothing from a yield — and short enough to be paid once per scratch
    /// directory, of which a full run makes several hundred.
    static let pause: TimeInterval = 0.002
    /// Absent this many readings running before the drain believes it: about
    /// 25 ms of watching per scratch directory, enough for a late writer.
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
    /// Removing it once is not enough: a view model saves from a task of its
    /// own, so the removal can arrive before the write, and
    /// `PrivateFile.directory` then makes the folder again after the teardown.
    ///
    /// So the teardown drains: it removes, waits and removes again, and stops
    /// only when the directory has stayed gone across several readings. It
    /// asserts at the end, because a teardown that cannot fail is how
    /// directories accumulate unseen.
    ///
    /// It waits on the clock, not on turns: a yield buys a turn on the pool and
    /// no wall-clock time, so a busy machine could run every pass before a
    /// detached writer is scheduled. A write that does arrive resets the count
    /// and is followed.
    ///
    /// The assertion can still pass while a later write leaves the directory
    /// behind; a test of that reads in a teardown registered before this one,
    /// which runs after it.
    ///
    /// The directory exists when handed over; a store that makes its own is
    /// unaffected, since making it twice is not an error.
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
    /// A byte filler, for tests about weight, hashing and counting; a test that
    /// cares what the file says writes its own contents.
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
