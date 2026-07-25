import XCTest
@testable import Module_Disk_Engine

final class ScanStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ScanStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-scanstore-\(UUID().uuidString)")
        store = ScanStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
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
}
