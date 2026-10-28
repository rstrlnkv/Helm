import SwiftUI

/// A choice whose options differ in kind, not in position: a capsule per option, a material capsule under the
/// group, a hairline rim (the drawing of `sizeControl`, a private member of `EditChrome` in `Sources/HelmApp/PanelChrome.swift`, inside a settings page).
///
/// A segmented control could not carry what the update channel row is for. The channels differ in kind, and the
/// system draws every segment in the accent whichever is chosen — so the control that asks «how rough a build do
/// you want» said it in one colour. Here each option is inked by its own `chosenFill`.
///
/// Not the knocked-out white on a saturated capsule the panel's size chips use: that was measured and it does not
/// hold up (white on the accent is 4.02:1 in both appearances, on the warning orange 2.23:1 in dark, against the
/// 4.5:1 floor). So the tint colours the fill and nothing else, as `HelmBadge` does, and the lettering stays the
/// text colour, whatever the option. Pass `HelmSurface.chosenWash(_:)` as the fill.
///
/// Buttons rather than a tap gesture on a shape, so Full Keyboard Access reaches them and each carries its own
/// label and selected trait.
public struct HelmPillChoice<Option: Hashable>: View {
    public struct Item {
        let option: Option
        let label: String
        let chosenFill: Color
        let help: String?

        public init(_ option: Option, label: String, chosenFill: Color, help: String? = nil) {
            self.option = option
            self.label = label
            self.chosenFill = chosenFill
            self.help = help
        }
    }

    private let title: String
    @Binding private var selection: Option
    private let items: [Item]

    public init(_ title: String, selection: Binding<Option>, items: [Item]) {
        self.title = title
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let chosen = selection == item.option
                Button { selection = item.option } label: {
                    Text(item.label)
                        // One weight in both states: a semibold chosen label is wider than a regular one, so
                        // the pill beside it would move every time the choice did. The fill carries the state.
                        .font(HelmText.rowTitle)
                        .foregroundStyle(chosen ? Color.primary : HelmText.quiet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        // A capsule inside a capsule, concentric at any type size.
                        .background(Capsule().fill(chosen ? item.chosenFill : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.help ?? "")
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(HelmSurface.hairline))
        .animation(HelmMotion.interface, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
