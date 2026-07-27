import XCTest
@testable import Module_Disk_Engine

/// What the ring has to be for `RingView.ringElements` to describe it.
///
/// A `Canvas` is one opaque rectangle to VoiceOver, so the ring supplies its
/// own accessibility children: one per wedge of ring 0, each labelled
/// "name, size, N% of this folder". The view cannot be unit-tested, but every
/// fact those labels stand on comes from `RingLayout.layout` — and three of
/// them were wrong on the first attempt, each in a way the layout could have
/// warned about. This is where the warnings live now.
final class RingAccessibilityTests: XCTestCase {

    private func node(_ name: String, _ bytes: Int, children: [DiskNode] = []) -> DiskNode {
        DiskNode(name: name, path: "/\(name)", bytes: bytes,
                 isDirectory: !children.isEmpty, children: children)
    }

    private func ringZero(_ segments: [RingSegment]) -> [RingSegment] {
        segments.filter { $0.ring == 0 }
    }

    /// A root with free space and enough slivers to fold: what the module shows
    /// the moment it opens, since free space is drawn only at the volume root.
    private func volumeRoot() -> [RingSegment] {
        let root = node("root", 1000, children: [
            node("big", 989), node("sliver", 10), node("crumb", 1),
        ])
        return RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 1000)
    }

    // MARK: - Identity

    /// The trap: `path` is not an identity.
    ///
    /// The free-space sector (RingLayout.swift:65) and the folded "other"
    /// bucket (RingLayout.swift:102) are both built with `path: ""`, and both
    /// are on ring 0 of the volume root — the first screen of the module. A
    /// `ForEach(…, id: \.path)` over that is two children under one id, which
    /// SwiftUI resolves by dropping one: the wedge that vanishes from VoiceOver
    /// is whichever it likes. `startAngle` is the identity that holds, because
    /// the layout hands out a distinct arc to every wedge by construction.
    func testRingZeroNeedsAnIdentityThatIsNotThePath() {
        let ring = ringZero(volumeRoot())
        XCTAssertGreaterThan(ring.count, 2, "the fixture must fold and must have free space")
        XCTAssertLessThan(Set(ring.map(\.path)).count, ring.count,
                          "paths look unique here; they are not in the app: "
                          + "\(ring.map { "\($0.name)=\($0.path)" })")
        XCTAssertEqual(Set(ring.map(\.startAngle)).count, ring.count,
                       "the identity the view relies on collided")
    }

    /// The same guarantee where it is hardest to hold: every wedge of a wide,
    /// deep, folding ring has its own arc, and they run in reading order.
    func testEveryWedgeHasItsOwnArcInReadingOrder() {
        let many = (0..<300).map { node("child\($0)", 1_000 + $0 * 5_000) }
        let segments = RingLayout.layout(focus: node("root", many.reduce(0) { $0 + $1.bytes },
                                                     children: many),
                                         depthLevels: 3, freeBytes: 4_000_000)
        let ring = ringZero(segments)
        XCTAssertGreaterThan(ring.count, 3)
        XCTAssertEqual(Set(ring.map(\.startAngle)).count, ring.count)
        XCTAssertEqual(ring.map(\.startAngle), ring.map(\.startAngle).sorted(),
                       "the elements are announced in a different order from the drawing")
        // Every ring, not only the first: hit-testing shares these arcs.
        XCTAssertEqual(Set(segments.map { "\($0.ring):\($0.startAngle)" }).count,
                       segments.count)
    }

    /// Free space carries no name to read out, so a label must be built from
    /// `isFreeSpace` and never from `name` — otherwise VoiceOver announces
    /// ", 1 KB, 50% of this folder": a wedge with no subject.
    func testFreeSpaceIsIdentifiableWithoutHavingAName() {
        let free = ringZero(volumeRoot()).first { $0.isFreeSpace }
        XCTAssertNotNil(free)
        XCTAssertTrue(free!.name.isEmpty, "if this ever gains a name, say so in the label")
        XCTAssertFalse(free!.isDirectory, "free space must never look openable")
        // The folded bucket has a name, and it is a single character of
        // punctuation — also not something to read out.
        let other = ringZero(volumeRoot()).first { $0.isOther }
        XCTAssertEqual(other?.name, "…")
        XCTAssertFalse(other?.isDirectory ?? true, "the fold must never look openable")
    }

    // MARK: - The denominator behind "% of this folder"

    /// The wedges that belong to the folder account for the folder exactly, so
    /// "N% of this folder" can sum to 100. The total of *every* ring-0 wedge is
    /// a different number, because free space is on ring 0 too — dividing by
    /// that one announces a folder that is 99% of its parent as 49%.
    func testTheFolderIsTheSumOfItsOwnWedgesAndNotOfTheRing() {
        let segments = volumeRoot()
        let ring = ringZero(segments)
        let folder = ring.filter { !$0.isFreeSpace }.reduce(0) { $0 + $1.bytes }
        XCTAssertEqual(folder, 1000, "the folder's own wedges lost or invented bytes")
        XCTAssertEqual(ring.reduce(0) { $0 + $1.bytes }, 2000,
                       "free space is inside any total taken over the whole ring")
    }

    /// The denominator is the folder, and the folder is not always the sum of
    /// the wedges.
    ///
    /// The transported tree keeps only the 200 largest children of a node
    /// (Model.swift:60), so a wide folder arrives holding more bytes than its
    /// listed children account for. `RingLayout` divides by the folder, which
    /// is why "a" gets 30% of the circle here and the remainder is left
    /// unpainted. Any percentage taken over the wedges instead — even with
    /// free space correctly excluded — renormalizes that away and announces
    /// 60% for a wedge drawn at 30%, which is the spoken share disagreeing
    /// with the drawing all over again.
    func testAWedgesShareIsOfTheFolderNotOfTheOtherWedges() {
        let focus = node("root", 1_000, children: [node("a", 300), node("b", 200)])
        let ring = ringZero(RingLayout.layout(focus: focus, depthLevels: 1, freeBytes: 0))
        let listed = ring.reduce(0) { $0 + $1.bytes }
        XCTAssertEqual(listed, 500, "the fixture must hold back part of the folder")

        let a = ring.first { $0.name == "a" }!
        XCTAssertEqual(a.span / (2 * .pi), 0.30, accuracy: 0.001,
                       "the drawing divides by the folder")
        XCTAssertEqual(Double(a.bytes) / Double(listed), 0.60, accuracy: 0.001,
                       "…and dividing by the wedges would say twice that")
    }

    /// Said once as an invariant, for every wedge of a folding ring: what a
    /// wedge is announced as has to be what it is drawn as.
    func testTheShareOfTheFolderIsTheShareOfTheCircle() {
        let focus = node("root", 1_000, children: [
            node("a", 500), node("b", 300), node("c", 100), node("d", 2),
        ])
        let segments = RingLayout.layout(focus: focus, depthLevels: 1, freeBytes: 1_000)
        // Free space takes half the circle here, so the folder's arc is π.
        let folderArc = Double.pi
        for wedge in ringZero(segments) where !wedge.isFreeSpace {
            XCTAssertEqual(wedge.span / folderArc,
                           Double(wedge.bytes) / Double(focus.bytes), accuracy: 0.0001,
                           "\(wedge.name) is drawn at a different share from its bytes")
        }
    }

    /// Nothing is dropped on the way into the fold: a folder's wedges still add
    /// up when most of its children are too small to draw.
    func testTheFoldedBucketCarriesEveryByteItSwallowed() {
        let many = (0..<500).map { node("child\($0)", 1_000) }
        let segments = RingLayout.layout(focus: node("root", 500_000, children: many),
                                         depthLevels: 1, freeBytes: 0)
        XCTAssertEqual(ringZero(segments).reduce(0) { $0 + $1.bytes }, 500_000)
    }

    /// Hundreds of children do not become hundreds of accessibility elements:
    /// anything under 2° folds, so the count stays inside what a VoiceOver
    /// rotor can be walked through.
    func testHundredsOfChildrenStayAHandfulOfElements() {
        let many = (0..<500).map { node("child\($0)", 1_000) }
        let segments = RingLayout.layout(focus: node("root", 500_000, children: many),
                                         depthLevels: 1, freeBytes: 0)
        let ring = ringZero(segments)
        XCTAssertLessThanOrEqual(ring.count, 181,
                                 "a full circle holds at most 180 wedges of 2°, plus the fold")
        XCTAssertFalse(ring.isEmpty)
    }

    // MARK: - Inputs that could have divided by zero, and do not

    /// No children and no bytes: the layout refuses before any arithmetic, so
    /// no percentage is ever computed against a zero total.
    func testAnEmptyFocusProducesNoElementsToLabel() {
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0), depthLevels: 3,
                                        freeBytes: 0).isEmpty)
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0, children: [node("a", 0)]),
                                        depthLevels: 3, freeBytes: 0).isEmpty)
        // Free space alone is not a ring: with no data there is nothing to
        // divide by, and the layout says so rather than drawing a whole circle
        // of something the folder does not contain.
        XCTAssertTrue(RingLayout.layout(focus: node("root", 0), depthLevels: 3,
                                        freeBytes: 5_000).isEmpty)
    }

    /// One wedge and nothing else: the folder is the wedge, whole.
    func testASingleWedgeIsTheWholeFolder() {
        let ring = ringZero(RingLayout.layout(focus: node("root", 100, children: [node("a", 100)]),
                                              depthLevels: 1, freeBytes: 0))
        XCTAssertEqual(ring.count, 1)
        XCTAssertEqual(ring[0].bytes, 100)
    }

    /// A zero-byte child never becomes a wedge: its span is below the fold
    /// threshold and it adds nothing to the folded bucket, so no element is
    /// ever announced as "0% of this folder" and no zero reaches a divisor.
    func testAZeroByteChildNeverBecomesAnElement() {
        let ring = ringZero(RingLayout.layout(
            focus: node("root", 100, children: [node("a", 100), node("empty", 0)]),
            depthLevels: 1, freeBytes: 0))
        XCTAssertEqual(ring.map(\.name), ["a"])
        XCTAssertTrue(ring.allSatisfy { $0.bytes > 0 })
    }

    /// Negative free space — a volume that reports more used than it has, which
    /// `statfs` does under pressure — must not open a wedge that runs backwards.
    func testNegativeFreeSpaceDrawsNoSector() {
        let segments = RingLayout.layout(focus: node("root", 100, children: [node("a", 100)]),
                                         depthLevels: 1, freeBytes: -5_000)
        XCTAssertNil(segments.first { $0.isFreeSpace })
        XCTAssertTrue(segments.allSatisfy { $0.endAngle >= $0.startAngle },
                      "a wedge that ends before it starts is a hit-test that never matches")
    }
}
