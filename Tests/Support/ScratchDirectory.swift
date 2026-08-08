import Foundation
import XCTest

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
    /// So the teardown drains instead of firing once. It removes, yields, and
    /// removes again, so a write landing anywhere in the window is reclaimed by
    /// a later pass — and it asserts at the end, because a teardown that cannot
    /// fail is how the 7621 accumulated. **The loop does not stop early when the
    /// directory is gone**: gone now is not gone, and the yields are what give a
    /// pending write its chance to arrive while somebody is still watching.
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
            for _ in 0..<200 {
                try? fm.removeItem(at: url)
                await Task.yield()
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
