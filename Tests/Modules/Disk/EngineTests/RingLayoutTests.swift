import XCTest
@testable import Module_Disk_Engine

final class RingLayoutTests: XCTestCase {
    private func node(_ name: String, _ bytes: Int, children: [DiskNode] = []) -> DiskNode {
        DiskNode(name: name, path: "/\(name)", bytes: bytes, isDirectory: !children.isEmpty || bytes == 0,
                 children: children)
    }

    // MARK: - Proportions

    func testSegmentsAreProportionalToBytes() {
        let root = node("root", 100, children: [node("a", 75), node("b", 25)])
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
        XCTAssertEqual(segments.count, 2)
        let a = segments.first { $0.name == "a" }!
        let b = segments.first { $0.name == "b" }!
        XCTAssertEqual(a.endAngle - a.startAngle, 0.75 * 2 * .pi, accuracy: 0.001)
        XCTAssertEqual(b.endAngle - b.startAngle, 0.25 * 2 * .pi, accuracy: 0.001)
        // Contiguous, starting at 12 o'clock (−π/2).
        XCTAssertEqual(a.startAngle, -.pi / 2, accuracy: 0.001)
        XCTAssertEqual(b.startAngle, a.endAngle, accuracy: 0.001)
    }

    /// The ring shows layers: children on ring 0, grandchildren on ring 1,
    /// each grandchild constrained to its parent's angular span.
    func testChildrenNestWithinParentSpan() {
        let root = node("root", 100, children: [
            node("a", 80, children: [node("a1", 60), node("a2", 20)]),
            node("b", 20),
        ])
        let segments = RingLayout.layout(focus: root, depthLevels: 2, freeBytes: 0)
        let a = segments.first { $0.name == "a" }!
        let a1 = segments.first { $0.name == "a1" }!
        let a2 = segments.first { $0.name == "a2" }!
        XCTAssertEqual(a.ring, 0)
        XCTAssertEqual(a1.ring, 1)
        XCTAssertGreaterThanOrEqual(a1.startAngle, a.startAngle - 0.001)
        XCTAssertLessThanOrEqual(a2.endAngle, a.endAngle + 0.001)
        // a1:a2 = 3:1 inside a's span
        XCTAssertEqual((a1.endAngle - a1.startAngle) / (a2.endAngle - a2.startAngle),
                       3.0, accuracy: 0.01)
    }

    // MARK: - Folding

    /// Slivers below the minimum visible angle merge into one "other" segment
    /// so the ring stays legible and hit-testable.
    func testTinyEntriesFoldIntoOther() {
        var children = [node("big", 1000)]
        for i in 0..<50 { children.append(node("tiny\(i)", 1)) }
        let root = node("root", 1050, children: children)
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
        XCTAssertLessThan(segments.count, 52)
        let other = segments.first { $0.isOther }
        XCTAssertNotNil(other)
        // Other's bytes = everything folded.
        XCTAssertEqual(other!.bytes, 50)
    }

    func testNoOtherSegmentWhenEverythingIsVisible() {
        let root = node("root", 100, children: [node("a", 60), node("b", 40)])
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
        XCTAssertFalse(segments.contains { $0.isOther })
    }

    // MARK: - Free space

    /// Only the volume root shows free space, as a dim sector after the data.
    func testFreeSpaceSectorAppendedAtRoot() {
        let root = node("root", 100, children: [node("a", 100)])
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 100)
        let free = segments.first { $0.isFreeSpace }
        XCTAssertNotNil(free)
        // Half the circle: 100 data + 100 free.
        XCTAssertEqual(free!.endAngle - free!.startAngle, .pi, accuracy: 0.001)
        let a = segments.first { $0.name == "a" }!
        XCTAssertEqual(a.endAngle - a.startAngle, .pi, accuracy: 0.001)
    }

    // MARK: - Hit testing

    func testHitTestMapsPointToSegment() {
        let root = node("root", 100, children: [node("a", 50), node("b", 50)])
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
        // Ring 0 occupies [innerRadius, innerRadius+thickness) in unit space.
        let geometry = RingGeometry(innerRadius: 0.30, thickness: 0.20, gap: 0.02)
        // 3 o'clock (angle 0) at ring-0 radius: that's inside "b"
        // (a spans -π/2..π/2? no: a is first: -π/2..π/2, so angle 0 is a).
        let hitA = RingLayout.hitTest(segments: segments, geometry: geometry,
                                      angle: 0, radius: 0.35)
        XCTAssertEqual(hitA?.name, "a")
        let hitB = RingLayout.hitTest(segments: segments, geometry: geometry,
                                      angle: .pi, radius: 0.35)
        XCTAssertEqual(hitB?.name, "b")
        // Center hole hits nothing.
        XCTAssertNil(RingLayout.hitTest(segments: segments, geometry: geometry,
                                        angle: 0, radius: 0.1))
    }

    /// Angles wrap: a point described as -3π/2 is the same as π/2.
    func testHitTestNormalizesAngle() {
        let root = node("root", 100, children: [node("a", 100)])
        let segments = RingLayout.layout(focus: root, depthLevels: 1, freeBytes: 0)
        let geometry = RingGeometry(innerRadius: 0.30, thickness: 0.20, gap: 0.02)
        XCTAssertEqual(RingLayout.hitTest(segments: segments, geometry: geometry,
                                          angle: -3 * .pi / 2, radius: 0.35)?.name, "a")
    }

    func testEmptyFocusYieldsNoSegments() {
        let root = node("empty", 0)
        XCTAssertTrue(RingLayout.layout(focus: root, depthLevels: 2, freeBytes: 0).isEmpty)
    }
}
