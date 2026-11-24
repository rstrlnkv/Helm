import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// Opening the page **deletes** the saved scan when the folder it measured has
/// gone.
///
/// `restoreLastScan` says why the app does it. It is held here because it is
/// the branch that makes `TheSuiteDoesNotReadTheUsersLastScanTests` necessary:
/// a test rendering Disk's page with the default `ScanStore()` would run it
/// against wherever that store resolves. The test asserts the fixture was
/// restored first, since a page that restored nothing clears nothing.
@MainActor
final class AVanishedRootClearsTheCacheTests: XCTestCase {

    func testAScanWhoseRootHasGoneIsDeletedFromTheStore() async throws {
        let storeDirectory = scratchDirectory("vanished-root-store")
        let store = ScanStore(directory: storeDirectory)
        // Made, saved, then taken away — the ordinary life of a scanned folder.
        let root = scratchDirectory("vanished-root")
        store.save(saved(at: root), at: Date())
        XCTAssertNotNil(store.load(), "the fixture is not on disk, so nothing below is a test")
        try FileManager.default.removeItem(at: root)

        let model = DiskViewModel(work: AnsweringWork(volumes: []), store: store)
        await model.appear()
        await waitUntil("the saved scan of a vanished root was cleared", within: .seconds(5)) {
            store.load() == nil
        }

        XCTAssertNil(store.load(),
                     "the saved scan survived a root that has gone — if it did not, the read of "
                     + "somebody's own store is a read and not a deletion")
        XCTAssertNil(model.result, "a tree whose root has gone was put on screen")
    }

    /// A tree the store will accept: one child, and a root that exists when it
    /// is written.
    private func saved(at root: URL) -> ScanResult {
        let child = DiskEntry(name: "a", path: root.appendingPathComponent("a").path,
                              bytes: 1000, isDirectory: false, noAccess: false, children: [])
        return ScanResult(root: DiskEntry(name: root.lastPathComponent, path: root.path,
                                          bytes: 1000, isDirectory: true, noAccess: false,
                                          children: [child]),
                          freeBytes: 0, filesScanned: 1, seconds: 1)
    }
}
