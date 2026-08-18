import SwiftUI

/// The two halves of every reveal in this app: a height that is *measured*, and
/// a block that is clipped to it.
///
/// They were written by hand at every site that needed them
/// (`grep -rn 'helmMeasuredHeight\|helmAccordion' Sources/` counts what that
/// came to), and the copies did not all say the same thing — which is the
/// argument for a token rather than an idiom. Both are here; a site takes one
/// or the other, and `helmAccordion` is built on `helmMeasuredHeight` rather
/// than beside it, so a site that needs both makes one call and there is only
/// ever one writer into the stored height.
///
/// **Why a measured height at all, rather than `if`.** Removing rows from the
/// hierarchy collapses the card's background instantly while the disappearing
/// rows go on drawing over whatever sits below. The content stays mounted, its
/// natural height is measured, and the frame animates between 0 and that
/// number, so the block's edge always contains what is inside it.
///
/// **Why not a fade.** Animating `.opacity` puts the subtree in an offscreen
/// layer, where hierarchical colours resolve differently — dropping that layer
/// at the end of the animation makes them jump. `.compositingGroup()` stops the
/// jump and costs more than it fixes: inside a permanent layer, system
/// materials (dividers, switches, bordered buttons, coloured symbols) stop
/// blending with the card behind them. The height and the clip are the whole
/// reveal, and the content slides out from under the edge with every colour
/// native. The other side of that bargain belongs to the caller: `.clipped()`
/// gives the block a layer of its own *while the height animates*, so a
/// hierarchical style (`.secondary`, `.tertiary`) inside it resolves again when
/// the layer goes away, which reads as a blink at the end of the reveal. Use
/// `Color.primary.opacity(…)` in there.
public extension View {

    /// A height taken from the layout and written **inside a transaction**, so
    /// the thing built from it travels instead of jumping.
    ///
    /// `onGeometryChange` hands its value over *outside* the transaction that
    /// is running, so any height the layout is then built from has to carry its
    /// own — and it has to carry it **where the value lands**, not at the change
    /// that caused it. Measured on the panel's drawer: 102 → 298 pt in one frame
    /// as shipped, one frame with a `withAnimation` around the button that
    /// caused it, and a ten-value ramp with the write itself in a transaction.
    ///
    /// **`.animation(_:value:)` on the frame this feeds does not rescue it.**
    /// Measured against the real view it is indistinguishable from no animation
    /// at all — `DisclosureProbe` holds both variants and the control.
    ///
    /// **`nil` is «nothing has measured this yet», and it is not a change.**
    /// Animating the first measurement plays the view collapsing from whatever
    /// the unmeasured layout happened to be: a scroll view with no height of its
    /// own takes everything it is offered, so that first frame is the whole
    /// surface. Five of the call sites this replaces spelled «not measured» as
    /// `0`, which works only because a real height is never zero — an accident,
    /// and one that already read wrong once: `PanelGrid.roomForGrid` gives
    /// `nil` and `0` different answers on purpose, because a bar nobody draws is
    /// not a bar nobody has measured. The optional says which one is meant.
    ///
    /// - Parameters:
    ///   - height: where the measurement lives. `nil` until the first one lands.
    ///   - animation: how a *later* measurement travels. `disclosure` is the
    ///     token for a measured, clipped height and is right for almost
    ///     everything; the sidebar's rows correct their own heights while the
    ///     list is already reordering on `interface`, and two systems need one
    ///     curve rather than one duration.
    func helmMeasuredHeight(_ height: Binding<CGFloat?>,
                            animation: Animation = HelmMotion.disclosure) -> some View {
        onGeometryChange(for: CGFloat.self, of: \.size.height) { measured in
            guard measured > 0, height.wrappedValue != measured else { return }
            if height.wrappedValue == nil {
                height.wrappedValue = measured
            } else {
                withAnimation(animation) { height.wrappedValue = measured }
            }
        }
    }

    /// A block that is always there and is sometimes zero points tall.
    ///
    /// The measurement above, then the gate: the natural height is measured
    /// whatever the block is doing, and the frame interpolates between 0 and
    /// that number. Between 0 and a *number* — SwiftUI cannot animate to `nil`,
    /// which left one card and its content out of step for a release.
    ///
    /// **The transaction comes from the caller**, and it has to: `open` is the
    /// caller's own value, and the flip has to be spelled
    /// `withAnimation(HelmMotion.disclosure) { open = … }` where it happens.
    /// A value published by an engine is not a press, so the pattern for one is
    /// a drawn flag of the view's own — `@State`, seeded at `init` because the
    /// first value is not a change either, written only inside `.onChange`'s
    /// own `withAnimation`. `.animation(_:value:)` on this block carries
    /// neither the transition nor the layout change; measured on the Keep Awake
    /// tile, one distinct frame under the modifier against eleven for the same
    /// swap moved into `withAnimation`.
    ///
    /// **The accessibility gate is not a parameter.** `.clipped()` hides a view
    /// from the eye and not from the accessibility tree: VoiceOver read both of
    /// Keep Awake's collapsed rows aloud before `.accessibilityHidden` was
    /// added, and a modifier a caller can forget it on ships a focusable
    /// invisible bar to every call site. It travels with the clip, always, and
    /// so does hit testing — a collapsed row that still answers the pointer is
    /// the same defect for the hand.
    ///
    /// Alignment is `.top` and not an argument: a block growing from its middle
    /// is not something this app does, and the clip is taken from an edge the
    /// content slides out from under.
    func helmAccordion(open: Bool, height: Binding<CGFloat?>,
                       animation: Animation = HelmMotion.disclosure) -> some View {
        helmMeasuredHeight(height, animation: animation)
            .frame(height: open ? (height.wrappedValue ?? 0) : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
    }
}
