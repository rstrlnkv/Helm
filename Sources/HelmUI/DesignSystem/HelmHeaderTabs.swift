import SwiftUI

/// **The page's tabs in the header row: always whole, never folded.** Labelled by their word, a glyph or both
/// (`ToolbarSwitcherStyle`, `HelmHeaderChoices`).
///
/// Under `.flat` a plate of `HelmSurface.barPlate` holds the tabs and the pick is `HelmSurface.barPick`;
/// under `.liquidGlass` the group is one glass container and the pick is a clear capsule with an outline. The pick slides to
/// a pressed tab, inside `HelmMotion.interface` and only where `HelmMotion.moves` says so; a tab the page
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
    @Environment(\.helmTraits) private var traits
    /// How a tab is labelled (`HelmHeaderChoices`), read from the environment and never made an identity, so a
    /// change of label keeps the pick where it is and sliding.
    @Environment(\.helmHeaderChoices) private var choices

    init(tabs: [HelmToolbarTab], selection: Binding<String>, enabled: Bool) {
        self.tabs = tabs
        self.selection = selection
        self.enabled = enabled
        _shown = State(initialValue: selection.wrappedValue)
    }

    /// The Kit's Segmented tabs (Figma 8:91): a 36 pt strip, 4 inside it a pill of 28 (radius 14, a capsule), 9 pt
    /// either side of a word, 5 between two tabs. The same numbers under both looks.
    private static let plate: CGFloat = 4
    private static let pill = HelmHeaderActions.side - 2 * plate

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
            strip.padding(Self.plate).background(HelmSurface.barPlate, in: Capsule())
        case .liquidGlass:
            GlassEffectContainer(spacing: 0) {
                strip.padding(Self.plate).glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }

    private var strip: some View {
        HStack(spacing: 5) {
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
        let style = choices.tabLabels
        let ink = tab.id == shown ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor)
        return HStack(spacing: 5) {
            switch style {
            case .text:
                word(tab, ink)
                dot(tab)
            case .icons:
                // The Kit's glyph: SF Symbol, Regular, 15. The dot sits on the glyph, since there is no word
                // to stand beside; the word is the tooltip and, as ever, the accessibility label.
                Image(systemName: tab.symbol).font(.system(size: 15)).foregroundStyle(ink)
                    .frame(width: 20)
                    .overlay(alignment: .topTrailing) { dot(tab).offset(x: 3, y: -1) }
                    .help(tab.title)
            case .iconsAndText:
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol).font(.system(size: 13)).foregroundStyle(ink)
                    word(tab, ink)
                }
                dot(tab)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Self.pill)
        .background {
            if tab.id == shown {
                Capsule().fill(appearance == .flat ? AnyShapeStyle(HelmSurface.barPick) : AnyShapeStyle(.clear))
                    .matchedGeometryEffect(id: "pick", in: space)
                    .overlay { if appearance == .liquidGlass { Capsule().strokeBorder(Color.primary.opacity(0.12)) } }
            }
        }
        .contentShape(Capsule())
    }

    /// Never cut: a tab keeps its whole word, and `SettingsWindow.minSize` is measured with it. The selected tab
    /// reads by its ink as well as by its pick, (`.labelColor` over `.secondaryLabelColor`); the Kit's one weight,
    /// Regular, for every state, so a pick does not change a width.
    private func word(_ tab: HelmToolbarTab, _ ink: Color) -> some View {
        Text(tab.title).font(.system(size: 13)).lineLimit(1).fixedSize().foregroundStyle(ink)
    }

    @ViewBuilder
    private func dot(_ tab: HelmToolbarTab) -> some View {
        if tab.needsAttention {
            Circle().fill(HelmSignal.warning(increased: traits.increasedContrast)).frame(width: 6, height: 6).accessibilityHidden(true)
        }
    }

    private func press(_ tab: HelmToolbarTab) {
        if HelmMotion.moves(reduceMotion: traits.reducedMotion) {
            withAnimation(HelmMotion.interface) { shown = tab.id }
        } else {
            shown = tab.id
        }
        selection.wrappedValue = tab.id
    }
}
