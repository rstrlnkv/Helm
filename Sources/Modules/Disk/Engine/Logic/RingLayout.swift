import Foundation
import HelmRuntime

/// One drawable arc of the sunburst.
public struct RingSegment: Sendable, Equatable {
    public let name: String
    public let path: String
    public let bytes: Int
    /// Radians; 12 o'clock is -π/2, clockwise positive.
    public let startAngle: Double
    public let endAngle: Double
    /// 0 = innermost data ring (children of the focus).
    public let ring: Int
    public let isDirectory: Bool
    public let isOther: Bool
    public let isFreeSpace: Bool
    public let noAccess: Bool

    public var span: Double { endAngle - startAngle }
}

/// Radii in unit space (0…1 of half the ring view's side).
public struct RingGeometry: Sendable, Equatable {
    public let innerRadius: Double
    public let thickness: Double
    public let gap: Double

    public init(innerRadius: Double, thickness: Double, gap: Double) {
        self.innerRadius = innerRadius
        self.thickness = thickness
        self.gap = gap
    }

    /// [start, end) radius of a ring index.
    public func radialRange(ring: Int) -> (Double, Double) {
        radialRange(ring: Double(ring))
    }

    /// Fractional rings exist only part-way through an unfold, while a wedge's
    /// children slide inward to the ring they will occupy once it lands.
    public func radialRange(ring: Double) -> (Double, Double) {
        let start = innerRadius + ring * (thickness + gap)
        return (start, start + thickness)
    }
}

/// Pure sunburst math: focus node → arcs. Drawing and hit-testing share it,
/// so a segment is clickable exactly where it is painted.
public enum RingLayout {
    /// Segments narrower than this fold into an "other" arc per parent.
    static let minimumVisibleAngle = 2.0 * .pi / 360.0 * 2.0   // 2°

    /// `path` locates `focus`; every segment's path is composed down from it,
    /// because `DiskNode` holds only the name. These strings are not decoration —
    /// `RingSegment.path` is what a click puts in the basket and what
    /// `RemovableScope` is later asked to judge, so a segment's path has to be
    /// the same string the scan was handed. `DerivedPathTests` pins that.
    public static func layout(focus: DiskNode, path: String,
                              depthLevels: Int, freeBytes: Int) -> [RingSegment] {
        let dataBytes = focus.bytes
        let total = dataBytes + max(freeBytes, 0)
        guard total > 0, dataBytes > 0 else { return [] }

        let dataSpan = 2 * .pi * Double(dataBytes) / Double(total)
        var out: [RingSegment] = []
        appendLevel(children: focus.children, parentPath: path, parentStart: -.pi / 2,
                    parentSpan: dataSpan, parentBytes: dataBytes,
                    ring: 0, remainingLevels: depthLevels, into: &out)

        if freeBytes > 0 {
            let start = -.pi / 2 + dataSpan
            out.append(RingSegment(name: "", path: "", bytes: freeBytes,
                                   startAngle: start, endAngle: 3 * .pi / 2,
                                   ring: 0, isDirectory: false, isOther: false,
                                   isFreeSpace: true, noAccess: false))
        }
        return out
    }

    private static func appendLevel(children: [DiskNode], parentPath: String,
                                    parentStart: Double,
                                    parentSpan: Double, parentBytes: Int,
                                    ring: Int, remainingLevels: Int,
                                    into out: inout [RingSegment]) {
        guard remainingLevels > 0, parentBytes > 0, !children.isEmpty else { return }
        let sorted = children.sorted { $0.bytes > $1.bytes }
        var cursor = parentStart
        var foldedBytes = 0

        for child in sorted {
            let span = parentSpan * Double(child.bytes) / Double(parentBytes)
            if span < minimumVisibleAngle {
                foldedBytes += child.bytes
                continue
            }
            let childPath = ScanPath.child(of: parentPath, name: child.name)
            out.append(RingSegment(name: child.name, path: childPath, bytes: child.bytes,
                                   startAngle: cursor, endAngle: cursor + span,
                                   ring: ring, isDirectory: child.isDirectory,
                                   isOther: false, isFreeSpace: false,
                                   noAccess: child.noAccess))
            appendLevel(children: child.children, parentPath: childPath, parentStart: cursor,
                        parentSpan: span, parentBytes: child.bytes,
                        ring: ring + 1, remainingLevels: remainingLevels - 1,
                        into: &out)
            cursor += span
        }

        if foldedBytes > 0 {
            let span = parentSpan * Double(foldedBytes) / Double(parentBytes)
            out.append(RingSegment(name: "…", path: "", bytes: foldedBytes,
                                   startAngle: cursor, endAngle: cursor + span,
                                   ring: ring, isDirectory: false, isOther: true,
                                   isFreeSpace: false, noAccess: false))
        }
    }

    // MARK: - Hit testing

    public static func hitTest(segments: [RingSegment], geometry: RingGeometry,
                               angle: Double, radius: Double) -> RingSegment? {
        // Normalize into the ring's angular domain [-π/2, 3π/2).
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < -.pi / 2 { a += 2 * .pi }
        if a >= 3 * .pi / 2 { a -= 2 * .pi }

        return segments.first { segment in
            let (r0, r1) = geometry.radialRange(ring: segment.ring)
            return radius >= r0 && radius < r1
                && a >= segment.startAngle && a < segment.endAngle
        }
    }
}
