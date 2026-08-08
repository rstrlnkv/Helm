import XCTest
import HelmTestSupport
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The ring draws three levels and lays out four.
///
/// The fourth is the one a drill promotes into view. Laying out only what is
/// drawn is the version that popped, and it is also the version that looks
/// correct in every screenshot — which is why this is a test and not a comment.
@MainActor
final class RingSpareLayoutTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        // Real directories: the view model refuses to restore a scan of a
        // folder that has since been deleted, and it is right to.
        root = scratchDirectory("ring-spare")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b/c/d"),
                                                withIntermediateDirectories: true)
    }

    func testTheLayoutCarriesOneLevelMoreThanTheRingDraws() async throws {
        let store = ScanStore(directory: scratchDirectory("ring-spare-store"))
        store.save(fourDeep())

        let model = DiskViewModel(vm: ModuleViewModel(transport: LocalTransport()), store: store)
        for _ in 0..<200 where model.segments.isEmpty { await Task.yield() }

        let rings = Set(model.segments.map(\.ring))
        XCTAssertFalse(rings.isEmpty, "nothing was restored, so this test proves nothing")
        XCTAssertTrue(rings.contains(RingView.visibleRings),
                      "no spare level: the ring that arrives on a drill has nowhere to slide in "
                      + "from. Rings laid out: \(rings.sorted())")
        XCTAssertFalse(rings.contains(RingView.visibleRings + 1),
                       "one spare, not a tree's worth: everything deeper is work nobody sees")
    }

    // MARK: - Fixture

    /// Four levels below the root, each a single child, so every level has to
    /// appear in the layout for the assertion to mean anything.
    private func fourDeep() -> ScanResult {
        func entry(_ path: URL, _ children: [DiskEntry]) -> DiskEntry {
            DiskEntry(name: path.lastPathComponent, path: path.path, bytes: 1000,
                      isDirectory: true, noAccess: false, children: children)
        }
        let d = entry(root.appendingPathComponent("a/b/c/d"), [])
        let c = entry(root.appendingPathComponent("a/b/c"), [d])
        let b = entry(root.appendingPathComponent("a/b"), [c])
        let a = entry(root.appendingPathComponent("a"), [b])
        return ScanResult(root: entry(root, [a]), freeBytes: 0, filesScanned: 4, seconds: 1)
    }
}
