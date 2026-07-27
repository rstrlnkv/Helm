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
    /// False at the scan root, where the middle of the ring leads nowhere —
    /// the toolbar's Back button is honestly disabled in the same state.
    var canGoBack: Bool
    /// The name the rest of the screen shows for a path: macOS's own folders
    /// are named the way Finder names them, and the list already does this.
    var displayName: (RingSegment) -> String
    /// Path of the child just left, when arriving from below; the ring folds
    /// back into its wedge instead of cross-fading.
    var foldingBackFrom: String?
    var onFoldConsumed: () -> Void

    @State private var hoverPoint: CGPoint?
    /// The wedge currently opening (or closing), and how far along it is.
    /// Non-nil only while the animation runs; hit-testing is suspended then, so
    /// a second click cannot start a second unfold on top of the first.
    @State private var pivot: RingSegment?
    @State private var unfold: Double = 0

    private let geometry = RingGeometry(innerRadius: 0.34, thickness: 0.155, gap: 0.012)

    /// The elements the drawing implies, in the order the eye reads it: where
    /// you are, then what is in it.
    ///
    /// Three things this has to get right, all of which it got wrong first:
    /// the centre has to name the folder, or every "N% of this folder" below
    /// it is a share of something never mentioned; the denominator must be the
    /// used bytes, not the used bytes plus free space, or the spoken share
    /// disagrees with the bar drawn beside it on the same row; and the names
    /// must be the names on screen — the list and the tooltip both localize
    /// macOS's own folders, so raw `name` said "Movies" while the screen said
    /// «Фильмы».
    @ViewBuilder private var ringElements: some View {
        let inner = segments.filter { $0.ring == 0 }
        // Free space is not part of the folder, so it is not part of its total.
        let total = max(inner.filter { !$0.isFreeSpace }.reduce(0) { $0 + $1.bytes }, 1)
        VStack {
            // First, not last: a VoiceOver user walks this list in order, and
            // the way out should not sit behind twenty wedges.
            Color.clear
                .accessibilityElement()
                .accessibilityLabel(centreLabel)
                .accessibilityAddTraits(canGoBack ? [.isButton] : [])
                .accessibilityAction { if canGoBack { onBack() } }
            // `path` is empty for both free space and the folded bucket, so it
            // cannot be the identity: two elements would collide and one would
            // be dropped.
            ForEach(inner, id: \.startAngle) { segment in
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel(label(for: segment, total: total))
                    .accessibilityAddTraits(canOpen(segment) ? [.isButton] : [])
                    .accessibilityAction { if canOpen(segment) { open(segment) } }
            }
        }
    }

    private func canOpen(_ segment: RingSegment) -> Bool {
        segment.isDirectory && !segment.isOther && !segment.isFreeSpace
    }

    private var centreLabel: String {
        let where_ = "\(focusName), \(Bytes(focusBytes))"
        return growing ? "\(where_), \(DkStr.scanning)" : where_
    }

    private func label(for segment: RingSegment, total: Int) -> String {
        if segment.isFreeSpace { return "\(Bytes(segment.bytes)) \(DkStr.free)" }
        let name = segment.isOther ? DkStr.otherItems : displayName(segment)
        let share = Int((Double(segment.bytes) / Double(total) * 100).rounded())
        return DkStr.ringShare(name, Bytes(segment.bytes), share)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                RingCanvas(segments: segments, pivot: pivot, progress: unfold,
                           geometry: geometry, center: center, side: side,
                           color: color(for:))
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
                guard pivot == nil else { return }   // an unfold is already running
                guard let hit = segment(at: point, center: center, side: side) else {
                    onBack()          // the hole in the middle goes up a level
                    return
                }
                guard hit.isDirectory, !hit.isOther, !hit.isFreeSpace else { return }
                open(hit)
            }
            // A Canvas is one opaque rectangle to VoiceOver: the ring said
            // nothing at all, and drilling in was a double-click with no
            // keyboard equivalent. `accessibilityChildren` supplies the
            // elements the drawing implies — one per wedge, each carrying its
            // share and its way in.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(DkStr.ringMap)
            .accessibilityChildren { ringElements }
        }
        .animation(HelmMotion.interface, value: segments.count)
        // Arriving back at the parent: run the same transform backwards, so the
        // ring narrows into the wedge it came out of.
        .onChange(of: foldingBackFrom) { _, path in
            guard let path, let wedge = segments.first(where: { $0.path == path }) else { return }
            pivot = wedge
            unfold = 1
            onFoldConsumed()
            withAnimation(HelmMotion.emphasis) { unfold = 0 } completion: { pivot = nil }
        }
    }

    /// Opens a wedge: it widens until it is the whole ring, and only then does
    /// the drill land — so the ring the user ends up looking at is the one they
    /// watched grow, rather than a different ring that faded in.
    private func open(_ hit: RingSegment) {
        pivot = hit
        withAnimation(HelmMotion.emphasis) {
            unfold = 1
        } completion: {
            onSelect(hit)
            unfold = 0
            pivot = nil
        }
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
            Text(Bytes(segment.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(HelmSurface.floatingEdge))
        .fixedSize()
    }

    private var centerLabel: some View {
        VStack(spacing: 3) {
            Text(focusName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Text(Bytes(focusBytes))
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

/// One wedge of the sunburst, as a path. Free rather than a method: the ring
/// and its animatable canvas both draw with it.
func helmArcPath(center: CGPoint, side: CGFloat, inner: Double, outer: Double,
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

/// The arcs themselves.
///
/// `Animatable` on a `View`: a `Canvas` redraws when its inputs change, but
/// nothing interpolates a plain `Double` for it. Declaring `animatableData`
/// makes SwiftUI drive `progress` frame by frame and re-render the body each
/// time, which is what turns the transform in `RingUnfold` into motion.
private struct RingCanvas: View, @MainActor Animatable {
    let segments: [RingSegment]
    let pivot: RingSegment?
    var progress: Double
    let geometry: RingGeometry
    let center: CGPoint
    let side: CGFloat
    let color: (RingSegment) -> Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            for segment in segments {
                guard let arc = arc(for: segment) else { continue }
                context.opacity = arc.opacity
                context.fill(arc.path, with: .color(color(segment)))
                // A hairline of window background between arcs reads as
                // engraved separations rather than touching paint.
                context.stroke(arc.path, with: .color(Color(nsColor: .windowBackgroundColor)),
                               lineWidth: 1)
            }
        }
    }

    private func arc(for segment: RingSegment) -> (path: Path, opacity: Double)? {
        guard let pivot, progress > 0 else {
            let (r0, r1) = geometry.radialRange(ring: segment.ring)
            return (helmArcPath(center: center, side: side, inner: r0, outer: r1,
                            start: segment.startAngle, end: segment.endAngle), 1)
        }
        let span = pivot.endAngle - pivot.startAngle
        let start = RingUnfold.angle(segment.startAngle, pivotStart: pivot.startAngle,
                                     span: span, progress: progress)
        let end = RingUnfold.angle(segment.endAngle, pivotStart: pivot.startAngle,
                                   span: span, progress: progress)
        guard RingUnfold.isVisible(start: start, end: end) else { return nil }

        let isPivot = segment.path == pivot.path
        let isDescendant = !pivot.path.isEmpty && segment.path.hasPrefix(pivot.path + "/")
        let opacity = RingUnfold.opacity(isPivot: isPivot, isDescendant: isDescendant,
                                         progress: progress)
        guard opacity > 0.001 else { return nil }

        let ring = RingUnfold.ring(segment.ring, isDescendant: isDescendant, progress: progress)
        let (r0, r1) = geometry.radialRange(ring: ring)
        return (helmArcPath(center: center, side: side, inner: r0, outer: r1,
                        start: start, end: end), opacity)
    }
}
