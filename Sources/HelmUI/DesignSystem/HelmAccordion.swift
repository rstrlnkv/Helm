import SwiftUI

/// The two halves of every reveal in this app: a height that is *measured*, and
/// a block that is clipped to it. `helmAccordion` is built on
/// `helmMeasuredHeight`, so a site that needs both makes one call and there is
/// one writer into the stored height.
///
/// **A measured height, not `if`.** Removing rows collapses the card's
/// background at once while the leaving rows draw over what sits below. The
/// content stays mounted and the frame animates between 0 and its measured
/// height, so the block's edge always contains what is inside it.
///
/// **Not a fade.** Animating `.opacity` puts the subtree in an offscreen layer,
/// where hierarchical colours resolve differently and jump when the layer goes.
/// `.compositingGroup()` stops the jump but keeps the layer, and inside it
/// system materials stop blending with the card. The caller's half: `.clipped()`
/// gives the block a layer while the height animates, so a hierarchical style
/// (`.secondary`, `.tertiary`) inside it blinks at the end. Use
/// `Color.primary.opacity(…)` in there.
extension View {

    /// A height taken from the layout and written **inside a transaction**, so
    /// the thing built from it travels instead of jumping.
    ///
    /// `onGeometryChange` hands its value over outside any running transaction,
    /// so the write carries its own, where the value lands rather than where
    /// the change began. `.animation(_:value:)` on the frame this feeds does not
    /// rescue it.
    ///
    /// **`nil` is «nothing has measured this yet», and it is not a change.**
    /// Animating the first measurement plays the view collapsing from whatever
    /// the unmeasured layout was, often the whole surface. Not `0`: that a real
    /// height is never zero is an accident, and `PanelGrid.roomForGrid` gives
    /// `nil` and `0` different answers on purpose.
    ///
    /// - Parameters:
    ///   - height: where the measurement lives. `nil` until the first one lands.
    ///   - animation: how a *later* measurement travels. `disclosure` is the
    ///     token for a measured, clipped height and is right for almost
    ///     everything; the sidebar's rows correct their own heights while the
    ///     list is already reordering on `interface`, and two systems need one
    ///     curve rather than one duration.
    public func helmMeasuredHeight(_ height: Binding<CGFloat?>,
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

    /// A block that is always there and is sometimes zero points tall: the
    /// measurement above, then a frame between 0 and that number. SwiftUI
    /// cannot animate to `nil`.
    ///
    /// **The transaction comes from the caller**: the flip of `open` is spelled
    /// `withAnimation(HelmMotion.disclosure) { open = … }` where it happens. For
    /// a value an engine publishes, the view keeps a drawn flag in `@State`,
    /// seeded at `init` since the first value is not a change, and written only
    /// inside `.onChange`'s own `withAnimation`. `.animation(_:value:)` on this
    /// block carries neither the transition nor the layout change.
    ///
    /// **The accessibility gate is not a parameter.** `.clipped()` hides a view
    /// from the eye, not from VoiceOver, so hiding travels with the clip, always,
    /// and so does hit testing: a collapsed row that answers the pointer is the
    /// same defect for the hand.
    ///
    /// Content of more than one line needs `.fixedSize(horizontal: false, vertical: true)`
    /// to be measured whole, as `ShowcaseMotionBoard` does. Alignment is `.top`
    /// and not an argument: the content slides out from under an edge.
    public func helmAccordion(open: Bool, height: Binding<CGFloat?>,
                       animation: Animation = HelmMotion.disclosure) -> some View {
        helmMeasuredHeight(height, animation: animation)
            .frame(height: open ? (height.wrappedValue ?? 0) : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
    }
}
