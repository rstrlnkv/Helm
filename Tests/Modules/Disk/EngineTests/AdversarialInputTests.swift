import XCTest
@testable import Module_Disk_Engine

/// The inputs a tester reaches for first: nothing, one, enormous, negative,
/// duplicated, and named in a way that breaks string handling. Every crash
/// this module has shipped came from a value someone assumed could not occur —
/// a negative device id, a path joined onto "/", a folder with no bytes.
final class AdversarialInputTests: XCTestCase {
    private func node(_ name: String, _ bytes: Int, _ children: [DiskNode] = []) -> DiskNode {
        DiskNode(name: name, path: "/" + name, bytes: bytes,
                 isDirectory: !children.isEmpty, children: children)
    }

    // MARK: - Ring layout

    func testEveryChildIsZeroBytes() {
        let root = node("root", 0, [node("a", 0), node("b", 0)])
        // No division by a zero total, and nothing to draw.
        XCTAssertTrue(RingLayout.layout(focus: root, depthLevels: 3, freeBytes: 0).isEmpty)
    }

    func testOneChildFillsTheCircleExactly() {
        let root = node("root", 100, [node("only", 100)])
        let segment = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0).first
        XCTAssertEqual((segment?.endAngle ?? 0) - (segment?.startAngle ?? 0),
                       2 * .pi, accuracy: 0.0001)
    }

    func testAThousandChildrenStayBounded() {
        let children = (0..<1000).map { node("c\($0)", $0 + 1) }
        let segments = RingLayout.layout(focus: node("root", 500_500, children),
                                         depthLevels: 3, freeBytes: 0)
        // Folding must keep the ring drawable; the exact count is the layout's
        // business, but a thousand slivers is not a ring.
        XCTAssertLessThan(segments.count, 200)
        XCTAssertTrue(segments.allSatisfy { $0.endAngle > $0.startAngle })
    }

    /// Angles must never overlap: a hit test would then return whichever
    /// segment happened to be first.
    func testSegmentsOnOneRingNeverOverlap() {
        let root = node("root", 60, [node("a", 30), node("b", 20), node("c", 10)])
        let ring0 = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
            .filter { $0.ring == 0 }
            .sorted { $0.startAngle < $1.startAngle }
        for (previous, next) in zip(ring0, ring0.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.endAngle, next.startAngle + 0.0001)
        }
    }

    func testFreeSpaceLargerThanTheDisk() {
        // A nonsense free-space figure must not produce a segment past a turn.
        let segments = RingLayout.layout(focus: node("root", 10, [node("a", 10)]),
                                         depthLevels: 1, freeBytes: .max / 2)
        for segment in segments {
            XCTAssertLessThanOrEqual(segment.endAngle - segment.startAngle, 2 * .pi + 0.0001)
        }
    }

    // MARK: - Tree building

    func testTheSameFileTwiceIsCountedOnce() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        builder.addFile(path: "/r/a.bin", bytes: 100, fileID: 7)
        builder.addFile(path: "/r/hardlink.bin", bytes: 100, fileID: 7)
        XCTAssertEqual(builder.build().bytes, 100)
    }

    func testNamesThatBreakPathHandling() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        for name in ["with space.bin", "с кириллицей.bin", "emoji 🙂.bin",
                     "dots...bin", "…", "tab\tname.bin"] {
            builder.addFile(path: "/r/" + name, bytes: 10, fileID: UInt64(abs(name.hashValue)))
        }
        let root = builder.build()
        XCTAssertEqual(root.bytes, 60)
        XCTAssertTrue(root.children.allSatisfy { $0.path.hasPrefix("/r/") })
    }

    /// A file directly at the volume root, where the parent is "/" itself.
    func testFileAtTheVolumeRoot() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1)
        builder.addFile(path: "/lonely.bin", bytes: 42, fileID: 1)
        let root = builder.build()
        XCTAssertEqual(root.bytes, 42)
        XCTAssertEqual(root.children.first?.path, "/lonely.bin")
    }

    func testDeeplyNestedPath() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        let deep = "/r/" + (0..<60).map { "d\($0)" }.joined(separator: "/") + "/file.bin"
        builder.addFile(path: deep, bytes: 5, fileID: 1)
        XCTAssertEqual(builder.build().bytes, 5)
    }

    // MARK: - Safety

    func testTheSafetyListCannotBeSidesteppedByATrailingSlash() {
        XCTAssertFalse(DiskSafety.isRemovable("/System/"))
        XCTAssertFalse(DiskSafety.isRemovable("/System"))
    }

    func testRelativeAndEmptyPathsAreNeverRemovable() {
        XCTAssertFalse(DiskSafety.isRemovable(""))
        XCTAssertFalse(DiskSafety.isRemovable("relative/path"))
    }

    // MARK: - Pruning

    func testPruningEveryChildLeavesTheRootStanding() {
        let tree = DiskEntry(name: "r", path: "/r", bytes: 30, isDirectory: true, noAccess: false,
                             children: [
                                DiskEntry(name: "a", path: "/r/a", bytes: 20, isDirectory: false,
                                          noAccess: false, children: []),
                                DiskEntry(name: "b", path: "/r/b", bytes: 10, isDirectory: false,
                                          noAccess: false, children: []),
                             ])
        let pruned = DiskTreePrune.removing(paths: ["/r/a", "/r/b"], from: tree)
        XCTAssertTrue(pruned.children.isEmpty)
        XCTAssertEqual(pruned.bytes, 0)
    }

    /// Removing the same path twice must not subtract its bytes twice.
    func testDuplicatePathsInOneRemoval() {
        let tree = DiskEntry(name: "r", path: "/r", bytes: 30, isDirectory: true, noAccess: false,
                             children: [DiskEntry(name: "a", path: "/r/a", bytes: 20,
                                                  isDirectory: false, noAccess: false,
                                                  children: [])])
        let pruned = DiskTreePrune.removing(paths: ["/r/a", "/r/a"], from: tree)
        XCTAssertEqual(pruned.bytes, 10)
    }

    // MARK: - Focus

    private var freshRoot: DiskEntry {
        DiskEntry(name: "r", path: "/r", bytes: 1, isDirectory: true, noAccess: false, children: [])
    }

    func testFocusSurvivesAFolderVanishingMidScan() {
        let fresh = freshRoot
        // The user had drilled into /r/gone, which the final tree does not have.
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/gone", "/r/gone/deeper"], in: fresh)
        XCTAssertEqual(resolved.map(\.path), ["/r"])
    }

    func testFocusOnAnEmptyPathListFallsBackToTheRoot() {
        XCTAssertEqual(DiskFocus.resolve(paths: [], in: freshRoot).map(\.path), ["/r"])
    }
}
