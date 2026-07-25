import SwiftUI
import Module_Disk_Engine

/// The sunburst. Drawn on Canvas because a few hundred arcs as SwiftUI shapes
/// would be a few hundred views; geometry and hit-testing both come from
/// RingLayout, so a segment reacts exactly where it is painted.
struct RingView: View {
    let segments: [RingSegment]
    let focusName: String
    let focusBytes: Int
    @Binding var hovered: String?
    var onSelect: (RingSegment) -> Void
    var onBack: () -> Void

    private let geometry = RingGeometry(innerRadius: 0.34, thickness: 0.155, gap: 0.012)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                Canvas { context, _ in
                    for segment in segments {
                        let (r0, r1) = geometry.radialRange(ring: segment.ring)
                        let path = arcPath(center: center, side: side,
                                           inner: r0, outer: r1,
                                           start: segment.startAngle, end: segment.endAngle)
                        context.fill(path, with: .color(color(for: segment)))
                    }
                }
                centerLabel
                    .frame(width: side * geometry.innerRadius * 1.7)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = segment(at: point, center: center, side: side)?.path
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { point in
                guard let hit = segment(at: point, center: center, side: side) else {
                    onBack()          // the hole in the middle goes up a level
                    return
                }
                guard hit.isDirectory, !hit.isOther, !hit.isFreeSpace else { return }
                onSelect(hit)
            }
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(focusName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: Int64(focusBytes), countStyle: .file))
                .font(.system(size: 18, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Geometry

    private func segment(at point: CGPoint, center: CGPoint, side: CGFloat) -> RingSegment? {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = sqrt(dx * dx + dy * dy) / (side / 2)
        let angle = atan2(dy, dx)
        return RingLayout.hitTest(segments: segments, geometry: geometry,
                                  angle: angle, radius: radius)
    }

    private func arcPath(center: CGPoint, side: CGFloat, inner: Double, outer: Double,
                         start: Double, end: Double) -> Path {
        let half = side / 2
        var path = Path()
        path.addArc(center: center, radius: half * outer,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addArc(center: center, radius: half * inner,
                    startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }

    // MARK: - Colour

    /// A fixed, tuned palette rather than a hue derived from the path: hashed
    /// hues produced a harlequin ring where neighbouring wedges clashed and
    /// nothing read as related. These eight sit in one family, so size
    /// differences carry the meaning and colour only separates neighbours.
    private static let palette: [Color] = [
        Color(hue: 0.58, saturation: 0.52, brightness: 0.82),   // teal
        Color(hue: 0.62, saturation: 0.45, brightness: 0.74),   // slate blue
        Color(hue: 0.53, saturation: 0.42, brightness: 0.72),   // sea
        Color(hue: 0.68, saturation: 0.38, brightness: 0.76),   // periwinkle
        Color(hue: 0.47, saturation: 0.40, brightness: 0.70),   // moss
        Color(hue: 0.72, saturation: 0.34, brightness: 0.72),   // lilac
        Color(hue: 0.09, saturation: 0.45, brightness: 0.80),   // sand
        Color(hue: 0.02, saturation: 0.42, brightness: 0.76),   // clay
    ]

    /// Depth fades toward the rim, hover lifts; free space, folded slivers and
    /// unreadable folders stay deliberately quiet so real data reads first.
    private func color(for segment: RingSegment) -> Color {
        if segment.isFreeSpace { return Color.primary.opacity(0.06) }
        if segment.noAccess { return Color.orange.opacity(0.22) }
        if segment.isOther { return Color.primary.opacity(0.10) }

        let base = Self.palette[paletteIndex(for: segment)]
        let isHovered = hovered == segment.path
        // Outer rings sit back so the first ring stays the subject.
        let recede = 1.0 - Double(segment.ring) * 0.14
        return base.opacity(isHovered ? 1.0 : recede)
    }

    /// Stable per-path index so a folder keeps its colour across redraws and
    /// drill-downs — the chart has to look like the same chart after a click.
    private func paletteIndex(for segment: RingSegment) -> Int {
        var hash: UInt64 = 5381
        for byte in segment.path.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % UInt64(Self.palette.count))
    }
}
