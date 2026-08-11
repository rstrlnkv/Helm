import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Opening the page **deletes** the saved scan when the folder it measured has
/// gone.
///
/// That is the right thing for the app to do — `restoreLastScan` says why: a
/// memory of a folder that no longer exists restores a breadcrumb, a "Scan
/// again" button and an empty screen, with no way out that looks like one. It is
/// recorded here for the other reason: it is the branch that makes
/// `TheSuiteDoesNotReadTheUsersLastScanTests` a hazard rather than a turn of
/// phrase. While `DiskViewModel.shared(vm:)` builds its store as `ScanStore()`,
/// every test that renders Disk's settings page runs this branch against the
/// person's real 8 MB cache, and one deleted folder is all it takes.
///
/// A claim that a suite "could delete a file" is worth nothing until the delete
/// is watched happening, so this watches it — and asserts the fixture was
/// restored at all first, because a page that restored nothing clears nothing
/// and would pass this for free.
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

        let model = DiskViewModel(vm: ModuleViewModel(transport: LocalTransport()), store: store)
        for _ in 0..<200 where store.load() != nil { await Task.yield() }

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
