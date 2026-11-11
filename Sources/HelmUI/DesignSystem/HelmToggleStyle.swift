import SwiftUI

/// The look of a plain `Toggle` anywhere under a hosting root (`helmRoot()`): the label on the left in
/// the row's own face, the system's switch at the right edge.
///
/// The switch is the system's (`Toggle(configuration).toggleStyle(.switch)`), not a drawing, so focus,
/// VoiceOver, the space key and the inactive-window grey stay the system's. What the style owns is the
/// row: label and switch on one line, the label spread to the free width.
///
/// **Where each value comes from.** Label font `HelmText.rowTitle`, ink `Color.primary`. Between label and
/// switch stand at least 3 × `HelmSpace.s4` (24 pt): the stack's own spacing on each side of the `Spacer` that spreads
/// the label, and the spacer's minimum length. The style adds no look of its own for a window that is not
/// the active one. `\.labelsVisibility` and `\.controlSize` are honoured: a hidden label is not drawn, and
/// the switch takes the size — unless `switchSize` is set, which then wins.
struct HelmToggleStyle: ToggleStyle {
    /// The size the switch is drawn at, where the root's is not wanted: `HelmSettingsSection` passes `.mini`,
    /// the size of the switch a grouped `Form` draws (measured 36 x 16 pt). `nil` leaves the environment's size.
    var switchSize: ControlSize?

    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration, switchSize: switchSize)
    }

    private struct Rendered: View {
        let configuration: ToggleStyleConfiguration
        let switchSize: ControlSize?
        @Environment(\.labelsVisibility) private var labels
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            HStack(spacing: HelmSpace.s4) {
                if labels != .hidden {
                    configuration.label
                        .font(HelmText.rowTitle)
                        .foregroundStyle(.primary)
                    Spacer(minLength: HelmSpace.s4)
                }
                Toggle(configuration)
                    .toggleStyle(.switch)
                    .controlSize(switchSize ?? controlSize)
                    .labelsHidden()
            }
        }
    }
}
