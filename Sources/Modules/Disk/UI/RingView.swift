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
    /// The layout for a folder, so the unfold can move towards the arcs that
    /// will exist rather than towards a transform of the ones that do.
    var targetLayout: (String) -> [RingSegment]

    @State private var hoverPoint: CGPoint?
    /// The wedge currently opening (or closing), and how far along it is.
    /// Non-nil only while the animation runs; hit-testing is suspended then, so
    /// a second click cannot start a second unfold on top of the first.
    @State private var pivot: RingSegment?
    @State private var unfold: Double = 0
    /// The layout the ring is coming *from*. The drill lands before the
    /// animation starts, so `segments` is already the destination and this is
    /// the snapshot being left behind — which makes the last frame of the
    /// animation the layout itself, not a transform that has to agree with it.
    @State private var leaving: [RingSegment] = []

    private let geometry = RingGeometry(innerRadius: 0.34, thickness: 0.155, gap: 0.012)

    /// How many levels the ring shows. The layout carries one more — see
    /// `DiskViewModel.recomputeSegments` and `RingUnfold.opacity(isSpare:)`:
    /// the spare is what the new outermost ring slides in from during a drill,
    /// and it is drawn only while that is happening.
    static let visibleRings = 3

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
        // The folder's own size, which is what the wedges are drawn against —
        // not the sum of the wedges. `DiskEntry` keeps only the 200 largest
        // children, so summing them omits whatever was folded away and
        // renormalises the gap: a wedge drawn at 30% of the circle was
        // announced at 60%, which is the same disagreement between the spoken
        // share and the drawn one that excluding free space set out to end.
        let total = max(focusBytes, 1)
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
                RingCanvas(segments: segments, leaving: leaving, pivot: pivot, progress: unfold,
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
            // The parent is already on screen; the child is what leaves, and
            // it leaves by narrowing back into the wedge it came out of.
            leaving = targetLayout(path)
            pivot = wedge
            unfold = 0
            onFoldConsumed()
            withAnimation(HelmMotion.emphasis) { unfold = 1 } completion: {
                pivot = nil
                leaving = []
                unfold = 0
            }
        }
    }

    /// Opens a wedge: it widens until it is the whole ring, and only then does
    /// the drill land — so the ring the user ends up looking at is the one they
    /// watched grow, rather than a different ring that faded in.
    /// Opens a wedge: it widens until it is the whole ring while the layout
    /// underneath moves to where it will be, and only then does the drill land.
    /// The ring the user ends up looking at is the one they watched grow — and
    /// now it is that one exactly, arc for arc, rather than a transform of the
    /// old one that the new layout then replaced in a single frame.
    /// Opens a wedge.
    ///
    /// The drill lands *first*, so the ring is already showing the layout it
    /// will settle on, and the animation carries the previous layout out over
    /// the top of it. The other order — transform the old arcs, then swap —
    /// cannot be made seamless: folding into "other" is decided against the
    /// parent's total in one layout and the folder's own total in the other, so
    /// the last transformed frame held arcs the destination did not have, and
    /// every boundary moved in the single frame between them. Measured before
    /// and after: `last frame ring0` and `first frame ring0` in the log.
    private func open(_ hit: RingSegment) {
        leaving = segments
        pivot = hit
        onSelect(hit)
        unfold = 0
        withAnimation(HelmMotion.emphasis) {
            unfold = 1
        } completion: {
            pivot = nil
            leaving = []
            unfold = 0
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
                .foregroundStyle(HelmText.quiet)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
    }

    private var centerLabel: some View {
        VStack(spacing: 3) {
            Text(focusName)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1).truncationMode(.middle)
            Text(Bytes(focusBytes))
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
                .animation(HelmMotion.interface, value: focusBytes)
            if growing {
                Text(DkStr.scanning + "…")
                    .font(.caption2)
                    .foregroundStyle(HelmText.faint)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Geometry

    private func segment(at point: CGPoint, center: CGPoint, side: CGFloat) -> RingSegment? {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = sqrt(dx * dx + dy * dy) / (side / 2)
        let angle = atan2(dy, dx)
        // The spare level is laid out but not drawn, and what cannot be seen
        // cannot be clicked.
        return RingLayout.hitTest(segments: segments.filter { $0.ring < RingView.visibleRings },
                                  geometry: geometry,
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
    /// The layout being left behind. Empty while nothing is opening.
    let leaving: [RingSegment]
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
            for drawn in arcs() {
                context.opacity = drawn.opacity
                context.fill(drawn.path, with: .color(color(drawn.segment)))
                // A hairline of window background between arcs reads as
                // engraved separations rather than touching paint.
                context.stroke(drawn.path, with: .color(Color(nsColor: .windowBackgroundColor)),
                               lineWidth: 1)
            }
        }
    }

    private typealias Drawn = (segment: RingSegment, path: Path, opacity: Double)

    /// At rest the ring is its layout. While a wedge is opening it is two: the
    /// arcs that are leaving, carried out by the widening transform, and the
    /// arcs of the layout being entered, each moving from wherever it is now to
    /// exactly where it will be — so the frame the animation ends on is the
    /// frame that follows it.
    private func arcs() -> [Drawn] {
        guard let pivot, progress > 0, !leaving.isEmpty else {
            return segments.compactMap { segment in
                guard segment.ring < RingView.visibleRings else { return nil }
                let (r0, r1) = geometry.radialRange(ring: segment.ring)
                let path = helmArcPath(center: center, side: side, inner: r0, outer: r1,
                                       start: segment.startAngle, end: segment.endAngle)
                return (segment, path, 1)
            }
        }

        var out: [Drawn] = []
        let staying = Set(segments.map(\.path))
        // Leaving: the wedge that was clicked, its siblings, everything above
        // them — carried out by the widening transform and faded.
        for segment in leaving where !staying.contains(segment.path) {
            guard segment.ring < RingView.visibleRings else { continue }
            let span = pivot.endAngle - pivot.startAngle
            let start = RingUnfold.angle(segment.startAngle, pivotStart: pivot.startAngle,
                                         span: span, progress: progress)
            let end = RingUnfold.angle(segment.endAngle, pivotStart: pivot.startAngle,
                                       span: span, progress: progress)
            guard RingUnfold.isVisible(start: start, end: end) else { continue }
            let opacity = max(0, 1 - progress)
            guard opacity > 0.001 else { continue }
            let (r0, r1) = geometry.radialRange(ring: segment.ring)
            out.append((segment, helmArcPath(center: center, side: side, inner: r0, outer: r1,
                                             start: start, end: end), opacity))
        }

        // Staying: the layout already on screen, each arc coming from wherever
        // it was a moment ago. At full progress every one of them is exactly
        // where the layout puts it, because it is the layout.
        let before = Dictionary(leaving.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for segment in segments where segment.ring < RingView.visibleRings {
            let start: Double, end: Double, ring: Double, opacity: Double
            if let was = before[segment.path], !segment.path.isEmpty {
                start = RingUnfold.toward(was.startAngle, segment.startAngle, progress: progress)
                end = RingUnfold.toward(was.endAngle, segment.endAngle, progress: progress)
                ring = RingUnfold.toward(Double(was.ring), Double(segment.ring), progress: progress)
                opacity = 1
            } else {
                // No counterpart: the level that was never drawn, and whatever
                // a different fold produced. It slides in from one ring further
                // out and fades up rather than appearing.
                start = segment.startAngle
                end = segment.endAngle
                ring = RingUnfold.arrivingRing(segment.ring, progress: progress)
                opacity = min(max(progress, 0), 1)
            }
            guard opacity > 0.001 else { continue }
            let (r0, r1) = geometry.radialRange(ring: ring)
            out.append((segment, helmArcPath(center: center, side: side, inner: r0, outer: r1,
                                             start: start, end: end), opacity))
        }
        return out
    }

}


