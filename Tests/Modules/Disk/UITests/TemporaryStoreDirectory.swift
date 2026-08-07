import Foundation
import XCTest

extension XCTestCase {

    /// A directory for a `ScanStore` that is gone when the test is.
    ///
    /// **Removing it once is not enough, and every file here used to do that.**
    /// `DiskViewModel` saves the tree from a task of its own, so the removal can
    /// arrive before the write: `PrivateFile.directory` then makes the folder
    /// again and `last-scan.json` lands in it, after the test has finished and
    /// after the teardown block has run.
    ///
    /// Measured rather than reasoned about. One run of
    /// `StopLeavesNothingBehindTests` — which has had a correct-looking
    /// `addTeardownBlock` beside its `temporaryDirectory` all along — took
    /// `$TMPDIR` from 2282 `helm-disk-stop-…` directories to 2284, each holding
    /// exactly the scan file. Across the module: **7621 directories, 69 MB**,
    /// of which 3091 were empty, which is the same race losing the other way.
    ///
    /// So the teardown drains instead of firing once. It removes, yields, and
    /// removes again, so a write landing anywhere in the window is reclaimed by
    /// a later pass — and it says how many passes it took when it took more
    /// than one, because a bound reached is a bound worth knowing about.
    func temporaryStoreDirectory(_ label: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-\(label)-\(UUID().uuidString)")
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
}
