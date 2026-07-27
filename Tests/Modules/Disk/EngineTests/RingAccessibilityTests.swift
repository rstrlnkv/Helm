import XCTest
@testable import Module_Disk_Engine

/// What the ring has to be for `RingView.ringElements` to describe it.
///
/// A `Canvas` is one opaque rectangle to VoiceOver, so the ring supplies its
/// own accessibility children: one per wedge of ring 0, built with
/// `ForEach(segments.filter { $0.ring == 0 }, id: \.path)` and labelled
/// `DkStr.ringShare(name, size, percent)` where
/// `percent = bytes / (sum of every ring-0 wedge) * 100`.
///
/// The view cannot be unit-tested, but every fact it depends on comes from
/// `RingLayout.layout` — so the preconditions that make the labels correct are
/// testable here, and this is where they are pinned.
final class RingAccessibilityTests: XCTestCase {

    private func node(_ name: String, _ bytes: Int, children: [DiskNode] = []) -> DiskNode {
        DiskNode(name: name, path: "/\(name)", bytes: bytes,
                 isDirectory: !children.isEmpty, children: children)
    }

    private func ringZero(_ segments: [RingSegment]) -> [RingSegment] {
        segments.filter { $0.ring == 0 }
    }

    /// The exact expression in RingView.swift:35-38, so the pin moves when the
    /// view's arithmetic moves.
    private func announcedShare(of segment: RingSegment, in segments: [RingSegment]) -> Int {
        let total = max(ringZero(segments).reduce(0) { $0 + $1.bytes }, 1)
        return Int((Double(segment.bytes) / Double(total) * 100).rounded())
    }

    /// A root with free space and enough slivers to fold: what the module shows
    /// the moment it opens, since free space is drawn only at the volume root.
    private func volumeRoot() -> [RingSegment] {
        let root = node("root", 1000, children: [
            node("big", 990), node("sliver", 10), node("crumb", 1),
        ])
        return RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 1000)
    }

    // MARK: - Identity

    /// BUG (pinned): `ForEach(..., id: \.path)` needs ring-0 paths to be unique,
    /// and two of them are always the empty string — the free-space sector
    /// (RingLayout.swift:65) and the folded "other" bucket (RingLayout.swift:102)
    /// are both built with `path: ""`. Both are present on the volume root,
    /// which is the first screen of the module, so SwiftUI is handed two
    /// children under the id "" and one of the two wedges is undefined to
    /// VoiceOver.
    func testEveryRingZeroWedgeHasItsOwnIdentity() {
        XCTExpectFailure("free space and the folded bucket both carry path \"\"")
        let ring = ringZero(volumeRoot())
        XCTAssertGreaterThan(ring.count, 2, "the fixture must fold and must have free space")
        XCTAssertEqual(Set(ring.map(\.path)).count, ring.count,
                       "duplicate ForEach id among ring 0: "
                       + "\(ring.map { "\($0.name)=\($0.path)" })")
    }

    /// BUG (pinned): the label is `DkStr.ringShare(segment.name, …)` and the
    /// free-space sector's name is the empty string, so VoiceOver announces
    /// ", 1 KB, 50% of this folder" — a wedge with no subject. The folded
    /// bucket announces the literal "…".
    func testEveryRingZeroWedgeHasSomethingToAnnounce() {
        XCTExpectFailure("the free-space sector is built with name \"\"")
        for segment in ringZero(volumeRoot()) {
            XCTAssertFalse(segment.name.isEmpty,
                           "a wedge with no name to read out: path=\(segment.path) "
                           + "free=\(segment.isFreeSpace) other=\(segment.isOther)")
        }
    }

    // MARK: - The number against the words

    /// BUG (pinned): the label says "N% of this folder", but the denominator is
    /// every ring-0 wedge — free space included. Here "big" is 99% of the
    /// folder and is announced as 50%, because the volume is half empty. On a
    /// mostly-empty disk every folder is announced at a fraction of its real
    /// share, and the numbers no longer sum to 100.
    func testTheAnnouncedShareIsTheShareOfTheFolder() {
        XCTExpectFailure("free space is inside the denominator; the wording says folder")
        let segments = volumeRoot()
        let big = ringZero(segments).first { $0.name == "big" }!
        XCTAssertEqual(announcedShare(of: big, in: segments), 99, accuracy: 1,
                       "99% of the folder announced as "
                       + "\(announcedShare(of: big, in: segments))%")
    }

    /// The same defect stated as an invariant: the wedges that make up the
    /// folder must account for the whole folder.
    func testTheFolderWedgesAccountForTheWholeFolder() {
        XCTExpectFailure("free space dilutes every other wedge's share")
        let segments = volumeRoot()
        let sum = ringZero(segments).filter { !$0.isFreeSpace }
            .reduce(0) { $0 + announcedShare(of: $1, in: segments) }
        XCTAssertEqual(sum, 100, accuracy: 2, "the folder's own wedges sum to \(sum)%")
    }

    // MARK: - Inputs that could have divided by zero, and do not

    /// No children and no bytes: the layout refuses before any arithmetic, so
    /// the view's `max(total, 1)` is never the thing standing between it and a
    /// NaN percentage.
    func testAnEmptyFocusProducesNoElementsToLabel() {
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0), depthLevels: 3,
                                        freeBytes: 0).isEmpty)
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0, children: [node("a", 0)]),
                                        depthLevels: 3, freeBytes: 0).isEmpty)
        // Free space alone is not a ring: without data there is nothing to
        // divide by, and the layout says so rather than drawing a whole circle.
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0), depthLevels: 3,
                                        freeBytes: 5_000).isEmpty)
    }

    /// One wedge and nothing else: the share is the whole folder, exactly.
    func testASingleWedgeIsAnnouncedAsTheWholeFolder() {
        let segments = RingLayout.layout(focus: node("root", 100, children: [node("a", 100)]),
                                         depthLevels: 1, freeBytes: 0)
        let ring = ringZero(segments)
        XCTAssertEqual(ring.count, 1)
        XCTAssertEqual(announcedShare(of: ring[0], in: segments), 100)
    }

    /// A zero-byte child never becomes a wedge: its span is below the fold
    /// threshold and it adds nothing to the folded bucket, so no element is
    /// ever labelled "0% of this folder" and no zero reaches the divisor.
    func testAZeroByteChildNeverBecomesAnElement() {
        let segments = RingLayout.layout(
            focus: node("root", 100, children: [node("a", 100), node("empty", 0)]),
            depthLevels: 1, freeBytes: 0)
        let ring = ringZero(segments)
        XCTAssertEqual(ring.map(\.name), ["a"])
        XCTAssertTrue(ring.allSatisfy { $0.bytes > 0 })
    }

    /// Hundreds of children do not become hundreds of accessibility elements:
    /// anything under 2° folds, so the element count stays inside what a
    /// VoiceOver rotor can be walked through.
    func testHundredsOfChildrenStayAHandfulOfElements() {
        let many = (0..<500).map { node("child\($0)", 1_000) }
        let segments = RingLayout.layout(focus: node("root", 500_000, children: many),
                                         depthLevels: 1, freeBytes: 0)
        let ring = ringZero(segments)
        XCTAssertLessThanOrEqual(ring.count, 181,
                                 "a full circle holds at most 180 wedges of 2°, plus the fold")
        XCTAssertFalse(ring.isEmpty)
        // Everything folded into one bucket: the total is still the folder.
        XCTAssertEqual(ring.reduce(0) { $0 + $1.bytes }, 500_000)
    }

    /// Equal-sized children are all announced with the same share, and the
    /// shares of a folder without free space do sum to 100 — which is what
    /// makes the free-space case above a defect rather than a rounding quirk.
    func testWithoutFreeSpaceTheSharesSumToTheFolder() {
        let segments = RingLayout.layout(
            focus: node("root", 400, children: [node("a", 100), node("b", 100),
                                                node("c", 100), node("d", 100)]),
            depthLevels: 1, freeBytes: 0)
        let ring = ringZero(segments)
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(ring.reduce(0) { $0 + announcedShare(of: $1, in: segments) }, 100)
    }
}

private func XCTAssertEqual(_ lhs: Int, _ rhs: Int, accuracy: Int,
                            _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy, message(), file: file, line: line)
}
