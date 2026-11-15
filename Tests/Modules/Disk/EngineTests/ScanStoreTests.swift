import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

final class ScanStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ScanStore!

    override func setUpWithError() throws {
        directory = scratchDirectory("scanstore")
        store = ScanStore(directory: directory)
    }

    private func result(root: String, bytes: Int) -> ScanResult {
        ScanResult(root: DiskEntry(name: (root as NSString).lastPathComponent, path: root,
                                   bytes: bytes, isDirectory: true, noAccess: false, children: []),
                   freeBytes: 42, filesScanned: 7, seconds: 1.5)
    }

    func testSavedScanComesBack() throws {
        let saved = result(root: "/", bytes: 1000)
        store.save(saved, at: Date(timeIntervalSince1970: 1_800_000_000))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.result, saved)
        XCTAssertEqual(loaded.savedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// The detached save is fire-and-forget; it must still carry the date it was given.
    func testDetachedSaveKeepsTheDateItWasGiven() async throws {
        let saved = result(root: "/", bytes: 1000)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.saveDetached(saved, at: date)
        var loaded = store.load()
        for _ in 0..<200 where loaded == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
            loaded = store.load()
        }
        let cached = try XCTUnwrap(loaded)
        XCTAssertEqual(cached.result, saved)
        XCTAssertEqual(cached.savedAt, date)
    }

    func testNothingSavedYet() {
        XCTAssertNil(store.load())
    }

    /// Only the most recent scan is kept — the ring shows one tree.
    func testSavingAgainReplacesThePrevious() throws {
        store.save(result(root: "/", bytes: 1), at: Date(timeIntervalSince1970: 1))
        store.save(result(root: "/Users/me", bytes: 2), at: Date(timeIntervalSince1970: 2))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.result.root.path, "/Users/me")
    }

    func testClearRemovesIt() {
        store.save(result(root: "/", bytes: 1), at: Date())
        store.clear()
        XCTAssertNil(store.load())
    }

    /// A file from an older Helm (or a truncated write) must not crash the
    /// module — a missing cache just means "scan again".
    func testCorruptFileIsIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
    }

    /// A missing file is the first launch and says nothing; a file that is there
    /// and will not decode is a lost measurement and says so once, naming no path.
    func testAnUndecodableFileIsLoggedOnceAndAMissingOneNever() throws {
        tailTheLog()
        func lines() -> [String] {
            loggedLines(DiskEngine.moduleID)
        }
        XCTAssertNil(store.load())
        XCTAssertEqual(lines(), [], "a missing file logged")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())
        XCTAssertEqual(lines().count, 1, "an undecodable file did not log exactly once")
        XCTAssertFalse(lines().joined().contains(directory.path), "the line names the path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path), "the file was removed")
    }
}
