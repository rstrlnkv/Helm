import SwiftUI

/// **Which edges of a scrolled list have something hidden past them.**
///
/// The menu-bar panel's grid scrolls between two pinned bars, and a widget
/// cut off by the scroll view's clip used to stop at a hard line with nothing
/// to say it went on: the tab strip, the grid and the footer read as one flat
/// sheet, and a clipped tile read as a short one. The edge is marked only
/// where content really continues, so a grid that fits draws no mark at all.
///
/// A value rather than the offset, for the reason `PageHeaderOverContent`
/// gives: `onScrollGeometryChange` wakes its action when the projection
/// changes, so projecting two booleans fires on the crossings and not on every
/// frame of a scroll.
///
/// `0.5` of slack on both sides: a rubber-band bounce and a fractional inset
/// put a few hundredths on the offset at rest, and an edge lit by rounding is
/// lit for ever.
public struct PanelScrollEdges: Equatable, Sendable {
    /// Content is scrolled up past the top edge.
    public let above: Bool
    /// Content continues below the bottom edge.
    public let below: Bool

    public static let none = PanelScrollEdges(above: false, below: false)

    public init(above: Bool, below: Bool) {
        self.above = above
        self.below = below
    }

    /// - Parameters:
    ///   - offset: the content offset, which is `-insetTop` at rest at the top.
    ///   - viewport: the height of the scroll view itself.
    public init(offset: CGFloat, insetTop: CGFloat, insetBottom: CGFloat,
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

public extension View {
    /// Marks the edges of a panel scroll view that have content past them: the
    /// content fades out over the last `HelmSpace.s5` before the clip.
    ///
    /// **A fade, not glass.** The panel is already Liquid Glass, and a second
    /// glass or material band over the list is the glass-on-glass the panel's
    /// tabs were redrawn to get rid of. A fade is what the system's own soft
    /// scroll edge does, with nothing drawn on top.
    ///
    /// **No rule at either edge.** A hairline under the tab strip and another
    /// over the footer were drawn and taken out again (2026-09-17): two lines
    /// across a panel of cards read as bands cutting it into thirds.
    func helmPanelScrollEdges() -> some View {
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
            // interpolates one gradient between two stops, and never a mask
            // that was not there into one that is.
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
