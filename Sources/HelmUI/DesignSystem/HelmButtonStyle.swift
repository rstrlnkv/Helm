import SwiftUI

/// The look of a plain `Button` anywhere under a hosting root (`helmRoot()`): a rounded well, the label
/// in the primary ink, a stronger well under the pointer (`Color.primary` at 10 % against 5 % at rest, so
/// darker in light and lighter in dark) and a stronger one again while pressed (12 %).
///
/// A `ButtonStyle` and not a `PrimitiveButtonStyle`, so the system keeps the press, the keyboard
/// shortcut and the button trait. `ButtonStyleConfiguration` carries only the label, `isPressed` and the
/// role: a button that is the window's default action (`.keyboardShortcut(.defaultAction)`) loses the
/// system's accent under this style, which is why such a button names `.borderedProminent` itself.
///
/// **Where each value comes from.**
/// - Well at rest `HelmSurface.wellFill`, under the pointer `HelmSurface.barPick`, pressed
///   `HelmSurface.panelSelection`; the corner `HelmRadius.ctl`.
/// - Padding `HelmSpace.s5` across and `HelmSpace.s3` down, `HelmSpace.s4` down at `.large`
///   (`HelmEmptyState` sets it).
/// - Ink `Color.primary`; `.destructive` role `HelmSignal.danger(increased:)` from `\.helmTraits`;
///   disabled `HelmText.faint`.
/// - A window that is not the active one gets no look of its own from this style: the inactive look stays the system's.
/// - `\.helmShownInteraction` can force the hover or the pressed well for a screen that shows them (`HelmShowcase`).
/// - The well follows the pointer with `HelmMotion.hover(entering:)`, which already answers Reduce Motion.
///
/// **The capsule variant.** `helmCapsuleButtons()` on a container turns every plain `Button` inside it into the
/// same well with a capsule for its shape and its content shape; nothing else about the style changes. The one
/// pages that ask are Keep Awake's and Layout's heroes, for the rows of buttons under them; `HelmShowcase` draws it on
/// its buttons board. Every other plain `Button` keeps the `HelmRadius.ctl` corner.
///
/// **The chosen well.** `helmChosen(_:)` marks the chosen button of a row of positional choices: its well is
/// `HelmSurface.chosenWash` of the accent, opaque and blended inside the appearance, the ink stays primary (white on
/// the solid accent is below the 4.5:1 floor), and the pointer and the press add nothing to it. A choice whose
/// options differ in kind is `HelmPillChoice`.
///
/// The font is the caller's: a label that sets none gets the system's.
struct HelmButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Rendered(configuration: configuration) }

    private struct Rendered: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var controlSize
        @Environment(\.helmTraits) private var traits
        @Environment(\.helmShownInteraction) private var shown
        @Environment(\.helmCapsuleButtons) private var capsule
        @Environment(\.helmChosen) private var chosen

        /// Stored, not built per call: the reason is on `HelmSurface.chosenWash`.
        private static let chosenWell = HelmSurface.chosenWash(.accentColor)

        var body: some View {
            configuration.label
                .foregroundStyle(ink)
                .padding(.horizontal, HelmSpace.s5)
                .padding(.vertical, controlSize == .large ? HelmSpace.s4 : HelmSpace.s3)
                .background(wellShape.fill(well))
                .contentShape(wellShape)
                .onHover { entering in
                    withAnimation(HelmMotion.hover(entering: entering)) { hover = entering }
                }
        }

        private var wellShape: AnyShape {
            capsule ? AnyShape(Capsule(style: .continuous))
                    : AnyShape(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous))
        }

        private var well: Color {
            if chosen { return Self.chosenWell }
            guard enabled else { return HelmSurface.wellFill }
            let pressed = configuration.isPressed || shown == .pressed
            let lit = hover || shown == .hover
            return pressed ? HelmSurface.panelSelection : lit ? HelmSurface.barPick : HelmSurface.wellFill
        }

        private var ink: Color {
            guard enabled else { return HelmText.faint }
            return configuration.role == .destructive ? HelmSignal.danger(increased: traits.increasedContrast) : .primary
        }
    }
}

private extension EnvironmentValues {
    @Entry var helmCapsuleButtons = false
    @Entry var helmChosen = false
}

public extension View {
    /// Plain buttons inside this view are capsules instead of rounded wells — `HelmButtonStyle` → the capsule variant.
    func helmCapsuleButtons() -> some View { environment(\.helmCapsuleButtons, true) }

    /// This button is the chosen one of its row: the accent wash for its well — `HelmButtonStyle` → the chosen well.
    func helmChosen(_ chosen: Bool) -> some View { environment(\.helmChosen, chosen) }
}
