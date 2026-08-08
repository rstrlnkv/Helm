import XCTest
import HelmTestSupport
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Getting out of a scan.
///
/// The module reopens on whatever it measured last, which is right when that is
/// the volume you care about and a trap when it is not: a scan of the wrong
/// folder — or one somebody's harness left behind — came back at every launch,
/// and the only control on the screen was "Scan again", which measures the same
/// place forever. `newScan` is the way out, and it has to forget the saved scan
/// as well as clear the screen, or the next launch restores it.
@MainActor
final class ScanResetTests: XCTestCase {

    private var root: URL!
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("reset")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"),
                                                withIntermediateDirectories: true)
        storeDirectory = scratchDirectory("reset-store")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: storeDirectory)
    }

    func testStartingOverForgetsTheScanOnDiskAsWellAsOnScreen() async throws {
        let store = ScanStore(directory: storeDirectory)
        store.save(saved())
        let model = DiskViewModel(vm: ModuleViewModel(transport: LocalTransport()), store: store)
        for _ in 0..<200 where model.result == nil { await Task.yield() }
        XCTAssertNotNil(model.result, "the fixture has to be restored for this to prove anything")

        model.newScan()

        XCTAssertNil(model.result, "the screen still holds the scan")
        XCTAssertTrue(model.segments.isEmpty)
        XCTAssertNil(store.load(), "the next launch would restore it again")
    }

    private func saved() -> ScanResult {
        let child = DiskEntry(name: "a", path: root.appendingPathComponent("a").path,
                              bytes: 1000, isDirectory: true, noAccess: false, children: [])
        return ScanResult(root: DiskEntry(name: root.lastPathComponent, path: root.path,
                                          bytes: 1000, isDirectory: true, noAccess: false,
                                          children: [child]),
                          freeBytes: 0, filesScanned: 1, seconds: 1)
    }
}
