import SwiftUI
import HelmUI
import Module_Disk_Engine

/// The sunburst. Drawn on Canvas because a few hundred arcs as SwiftUI shapes
/// would be a few hundred views; geometry and hit-testing both come from
/// RingLayout, so a segment reacts exactly where it is painted.
struct RingView: View {
    let segments: [RingSegment]
    let focusName: String
    let focusBytes: Int
    /// True while the scan is still feeding the ring.
    let growing: Bool
    @Binding var hovered: String?
    var onSelect: (RingSegment) -> Void
    var onBack: () -> Void

    @State private var hoverPoint: CGPoint?

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
                        // A hairline of window background between arcs reads as
                        // engraved separations rather than touching paint.
                        context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)),
                                       lineWidth: 1)
                    }
                }
                centerLabel
                    .frame(width: side * geometry.innerRadius * 1.7)

                if let point = hoverPoint, let tip = tooltipSegment {
                    tooltip(for: tip)
                        .position(x: point.x, y: point.y - 26)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverPoint = point
                    hovered = segment(at: point, center: center, side: side)?.path
                case .ended:
                    hoverPoint = nil
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
        .animation(HelmMotion.interface, value: segments.count)
    }

    /// The segment under the cursor; free space and the folded bucket get
    /// their own labels so the tooltip never shows a bare "…".
    private var tooltipSegment: RingSegment? {
        guard let hovered else { return nil }
        return segments.first { $0.path == hovered && !$0.path.isEmpty }
            ?? segments.first { $0.isFreeSpace && hovered.isEmpty }
    }

    private func tooltip(for segment: RingSegment) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color(for: segment)).frame(width: 7, height: 7)
            Text(segment.isOther ? DkStr.otherItems
                                 : (DiskViewModel.folderName(for: segment.path) ?? segment.name))
                .font(.caption)
                .lineLimit(1)
            Text(ByteCountFormatter.string(fromByteCount: Int64(segment.bytes), countStyle: .file))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(HelmSurface.cardStroke))
        .fixedSize()
    }

    private var centerLabel: some View {
        VStack(spacing: 3) {
            Text(focusName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: Int64(focusBytes), countStyle: .file))
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
                .animation(HelmMotion.interface, value: focusBytes)
            if growing {
                Text(DkStr.scanning + "…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

    /// Depth fades toward the rim, hover lifts; free space, folded slivers and
    /// unreadable folders stay deliberately quiet so real data reads first.
    private func color(for segment: RingSegment) -> Color {
        if segment.isFreeSpace { return Color.primary.opacity(0.06) }
        if segment.noAccess { return Color.orange.opacity(0.22) }
        if segment.isOther { return Color.primary.opacity(0.10) }

        let base = DiskPalette.base(for: segment.path)
        let isHovered = hovered == segment.path
        let recede = 1.0 - Double(segment.ring) * 0.14
        return base.opacity(isHovered ? 1.0 : recede)
    }
}
