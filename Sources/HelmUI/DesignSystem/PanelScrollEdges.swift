import SwiftUI

/// **Which edges of a scrolled list have something hidden past them.**
///
/// The menu-bar panel's grid scrolls between two pinned bars, and a widget cut
/// off by the clip with nothing to say it goes on reads as a short tile. The
/// edge is marked only where content really continues, so a grid that fits
/// draws no mark at all.
///
/// A value rather than the offset, for the reason `PageHeaderOverContent`
/// gives, and `0.5` of slack on both sides, for the same reason.
struct PanelScrollEdges: Equatable, Sendable {
    /// Content is scrolled up past the top edge.
    let above: Bool
    /// Content continues below the bottom edge.
    let below: Bool

    static let none = PanelScrollEdges(above: false, below: false)

    init(above: Bool, below: Bool) {
        self.above = above
        self.below = below
    }

    /// - Parameters:
    ///   - offset: the content offset, which is `-insetTop` at rest at the top.
    ///   - viewport: the height of the scroll view itself.
    init(offset: CGFloat, insetTop: CGFloat, insetBottom: CGFloat,
                contentHeight: CGFloat, viewport: CGFloat) {
        let lowest = contentHeight + insetBottom - viewport
        above = offset + insetTop > 0.5
        below = lowest - offset > 0.5
    }

    init(_ geometry: ScrollGeometry) {
        self.init(offset: geometry.contentOffset.y,
                  insetTop: geometry.contentInsets.top,
                  insetBottom: geometry.contentInsets.bottom,
                  contentHeight: geometry.contentSize.height,
                  viewport: geometry.containerSize.height)
    }
}

extension View {
    /// Marks the edges of a panel scroll view that have content past them: the
    /// content fades out over the last `HelmSpace.s5` before the clip.
    ///
    /// **A fade, not glass**: the panel is already Liquid Glass, and a band of
    /// glass over the list would be glass on glass. A fade is what the system's
    /// soft scroll edge does. **No rule at either edge**: two lines across a
    /// panel of cards read as bands cutting it into thirds.
    public func helmPanelScrollEdges() -> some View {
        modifier(PanelScrollEdgeMarks())
    }
}

private struct PanelScrollEdgeMarks: ViewModifier {
    @State private var edges = PanelScrollEdges.none

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PanelScrollEdges.self) { geometry in
                PanelScrollEdges(geometry)
            } action: { _, now in
                withAnimation(HelmMotion.interface) { edges = now }
            }
            // Opacities rather than a mask that comes and goes: SwiftUI
            // interpolates a gradient's stops, never a mask appearing.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(edges.above ? 0 : 1), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: HelmSpace.s5)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(edges.below ? 0 : 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: HelmSpace.s5)
                }
            }
    }
}
