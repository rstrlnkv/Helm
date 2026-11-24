import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What the ring is told about two rows the list already tells apart.
///
/// `DiskViewModel.node(from:)` must carry the entry's `noAccess` and `isFolded`
/// into `RingLayout`, so an unreadable folder gets its own wedge and the `…`
/// bucket the quiet "other" one. The mapping is private, so this reads the
/// segments the model hands the ring; the drawn wedge is proved by a shot.
@MainActor
final class TheRingKnowsAnUnreadableFolderAndTheBucketTests: XCTestCase {

    private func entry(_ name: String, bytes: Int, directory: Bool = true,
                       noAccess: Bool = false, folded: Bool = false) -> DiskEntry {
        DiskEntry(name: name, path: "/Volumes/Big/" + name, bytes: bytes,
                  isDirectory: directory, noAccess: noAccess, children: [], isFolded: folded)
    }

    private func segments() -> [RingSegment] {
        let root = DiskEntry(name: "Big", path: "/Volumes/Big", bytes: 900, isDirectory: true,
                             noAccess: false,
                             children: [entry("Readable", bytes: 400),
                                        entry("Locked", bytes: 300, noAccess: true),
                                        entry("…", bytes: 200, directory: false, folded: true)])
        let dvm = DiskViewModel(work: AnsweringWork(volumes: []),
                                store: ScanStore(directory: scratchDirectory("disk-ring-flags")))
        dvm.result = ScanResult(root: root, freeBytes: 0, filesScanned: 3, seconds: 0)
        dvm.focusPath = [root]
        dvm.recomputeSegments()
        return dvm.segments.filter { $0.ring == 0 }
    }

    func testAnUnreadableFolderReachesTheRingAsNoAccess() throws {
        let locked = try XCTUnwrap(segments().first { $0.name == "Locked" })
        XCTAssertTrue(locked.noAccess, "the orange wedge is never drawn: the flag was dropped on the way to the layout")
        let readable = try XCTUnwrap(segments().first { $0.name == "Readable" })
        XCTAssertFalse(readable.noAccess, "control: a readable folder is not marked")
    }

    func testTheFoldedBucketReachesTheRingAsTheOtherWedge() throws {
        let bucket = try XCTUnwrap(segments().first { $0.name == "…" })
        XCTAssertTrue(bucket.isOther, "the bucket is drawn as an ordinary wedge named …")
        let readable = try XCTUnwrap(segments().first { $0.name == "Readable" })
        XCTAssertFalse(readable.isOther, "control: a real folder is not the bucket")
    }
}
