import SwiftUI

/// **The page's tabs in the header row: always whole, text only, never folded.**
///
/// Under `.flat` a plate of `HelmSurface.barPlate` holds the tabs and the pick is `HelmSurface.barPick`;
/// under `.liquidGlass` the group is one glass container and the pick is a clear capsule with an outline. The pick slides to
/// a pressed tab, inside `HelmMotion.interface` and only where `HelmMotion.travels` says so; a tab the page
/// itself selects (a page switch, an Uninstaller step) moves it without travel. The selection the page
/// owns is written outside the animation, so the page below is not swapped inside it.
struct HelmHeaderTabs: View {
    let tabs: [HelmToolbarTab]
    let selection: Binding<String>
    let enabled: Bool

    /// What the pick is under, which is `selection` followed one step behind a press.
    @State private var shown: String
    @Namespace private var space
    @Environment(\.helmBarAppearance) private var appearance

    init(tabs: [HelmToolbarTab], selection: Binding<String>, enabled: Bool) {
        self.tabs = tabs
        self.selection = selection
        self.enabled = enabled
        _shown = State(initialValue: selection.wrappedValue)
    }

    private static let height: CGFloat = 28

    var body: some View {
        group
            .opacity(enabled ? 1 : 0.4)
            .disabled(!enabled)
            .onChange(of: selection.wrappedValue) { _, now in shown = now }
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var group: some View {
        switch appearance {
        case .flat:
            strip.padding(2).background(HelmSurface.barPlate, in: Capsule())
        case .liquidGlass:
            GlassEffectContainer(spacing: 0) {
                strip.padding(2).glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                Button { press(tab) } label: { label(tab) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(tab.attentionNote ?? "")
                    .accessibilityAddTraits(tab.id == shown ? .isSelected : [])
            }
        }
    }

    private func label(_ tab: HelmToolbarTab) -> some View {
        HStack(spacing: 5) {
            // Never cut: a tab keeps its whole word, and `SettingsWindow.minSize` is measured with it. The
            // selected tab reads by its ink as well as by its pick, as `HelmToolbarSwitcher`'s cell does
            // (`.labelColor` over `.secondaryLabelColor`); one weight for both, so a pick does not change a width.
            Text(tab.title).font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
                .foregroundStyle(tab.id == shown ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
            if tab.needsAttention {
                Circle().fill(HelmSignal.warning).frame(width: 6, height: 6).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height - 4)
        .background {
            if tab.id == shown {
                Capsule().fill(appearance == .flat ? AnyShapeStyle(HelmSurface.barPick) : AnyShapeStyle(.clear))
                    .matchedGeometryEffect(id: "pick", in: space)
                    .overlay { if appearance == .liquidGlass { Capsule().strokeBorder(Color.primary.opacity(0.12)) } }
            }
        }
        .contentShape(Capsule())
    }

    private func press(_ tab: HelmToolbarTab) {
        if HelmMotion.travels(reduceMotion: HelmMotion.reduceMotion) {
            withAnimation(HelmMotion.interface) { shown = tab.id }
        } else {
            shown = tab.id
        }
        selection.wrappedValue = tab.id
    }
}
