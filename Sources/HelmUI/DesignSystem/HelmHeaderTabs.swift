import SwiftUI

/// **The numbers of a tab, which the Flat strip draws and the toolbar's strip is measured from** (`HelmTabsMetrics`):
/// one name each, so the two cannot drift. The look's own: padding either side of a segment, the gap before a dot and
/// between a glyph and its word, the plate round the tabs and the gap between two, the type sizes, a glyph-only tab's
/// width, the dot, and the dimming of a disabled strip.
public enum HelmTabNumbers {
    static let segmentPadding = CGFloat(9)
    /// The plate's padding round the tabs and the gap between two tabs (the Kit's Segmented tabs, Figma 8:91): the
    /// Flat strip is `plate + tabs + gaps + plate` and the toolbar's strip is cut from the same sum.
    public static let plate = CGFloat(4)
    public static let gap = CGFloat(5)
    static let dotGap = CGFloat(5)
    static let glyphGap = CGFloat(6)
    public static let wordSize = CGFloat(13)
    public static let iconSize = CGFloat(15)
    static let iconWidth = CGFloat(20)
    static let dot = CGFloat(6)
    public static let dimmed = 0.4
}

/// **The page's tabs in the header row: always whole, never folded.** Labelled by their word, a glyph or both
/// (`HeaderTabLabels`, `HelmHeaderChoices`).
///
/// Under `.flat` a plate of `HelmSurface.barPlate` holds the tabs and the pick is `HelmSurface.barPick`. Under
/// `.liquidGlass` this strip is one `GlassEffectContainer` with a glass capsule for the track and one for the pick,
/// tinted as the system's toolbar control draws it. The settings window shows a real toolbar item instead, so this
/// glass strip is for a view with no `helmTabsSink` (Architecture/ThePageHeader.md § Glass tabs). The pick slides to
/// a pressed tab only where `HelmMotion.moves` says so; a tab the page selects itself moves it without travel. The
/// page's selection is written outside the animation, so the page below is not swapped inside it.
public struct HelmHeaderTabs: View {
    let tabs: [HelmHeaderTab]
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

    public init(tabs: [HelmHeaderTab], selection: Binding<String>, enabled: Bool) {
        self.tabs = tabs
        self.selection = selection
        self.enabled = enabled
        _shown = State(initialValue: selection.wrappedValue)
    }

    /// The Kit's Segmented tabs (Figma 8:91): a 36 pt strip, `HelmTabNumbers.plate` inside it a pill of 28 (radius 14, a
    /// capsule), 9 pt either side of a word, `HelmTabNumbers.gap` between two tabs. The same numbers under both looks.
    private static let pill = HelmHeaderActions.side - 2 * HelmTabNumbers.plate

    public var body: some View {
        group
            .opacity(enabled ? 1 : HelmTabNumbers.dimmed)
            .disabled(!enabled)
            .onChange(of: selection.wrappedValue) { _, now in shown = now }
            .accessibilityElement(children: .contain)
    }

    private var group: some View {
        strip.padding(HelmTabNumbers.plate).helmBarCapsule(appearance, spacing: 0)
    }

    private var strip: some View {
        HStack(spacing: HelmTabNumbers.gap) {
            ForEach(tabs, id: \.id) { tab in
                Button { press(tab) } label: { label(tab) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(tab.attentionNote ?? "")
                    .accessibilityAddTraits(tab.id == shown ? .isSelected : [])
            }
        }
    }

    private func label(_ tab: HelmHeaderTab) -> some View {
        let style = choices.tabLabels
        let ink = tab.id == shown ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor)
        return HStack(spacing: HelmTabNumbers.dotGap) {
            switch style {
            case .text:
                word(tab, ink)
                dot(tab)
            case .icons:
                // The Kit's glyph: SF Symbol, Regular, 15. The dot sits on the glyph, since there is no word
                // to stand beside; the word is the tooltip and, as ever, the accessibility label.
                Image(systemName: tab.symbol).font(.system(size: HelmTabNumbers.iconSize)).foregroundStyle(ink)
                    .frame(width: HelmTabNumbers.iconWidth)
                    .overlay(alignment: .topTrailing) { dot(tab).offset(x: 3, y: -1) }
                    .help(tab.title)
            case .iconsAndText:
                HStack(spacing: HelmTabNumbers.glyphGap) {
                    Image(systemName: tab.symbol).font(.system(size: HelmTabNumbers.wordSize)).foregroundStyle(ink)
                    word(tab, ink)
                }
                dot(tab)
            }
        }
        .padding(.horizontal, HelmTabNumbers.segmentPadding)
        .frame(height: Self.pill)
        .background {
            if tab.id == shown {
                switch appearance {
                case .flat:
                    Capsule().fill(HelmSurface.barPick).matchedGeometryEffect(id: "pick", in: space)
                case .liquidGlass:
                    Capsule().fill(.clear)
                        .glassEffect(.regular.tint(Color(nsColor: .labelColor).opacity(0.14)).interactive(), in: Capsule())
                        .glassEffectID("pick", in: space)
                }
            }
        }
        .contentShape(Capsule())
    }

    /// Never cut: a tab keeps its whole word, and `SettingsWindow.minSize` is measured with it. The selected tab
    /// reads by its ink as well as by its pick, (`.labelColor` over `.secondaryLabelColor`); the Kit's one weight,
    /// Regular, for every state, so a pick does not change a width.
    private func word(_ tab: HelmHeaderTab, _ ink: Color) -> some View {
        Text(tab.title).font(.system(size: HelmTabNumbers.wordSize)).lineLimit(1).fixedSize().foregroundStyle(ink)
    }

    @ViewBuilder
    private func dot(_ tab: HelmHeaderTab) -> some View {
        if tab.needsAttention {
            Circle().fill(HelmSignal.warning(increased: traits.increasedContrast)).frame(width: HelmTabNumbers.dot, height: HelmTabNumbers.dot).accessibilityHidden(true)
        }
    }

    private func press(_ tab: HelmHeaderTab) {
        if HelmMotion.moves(reduceMotion: traits.reducedMotion) {
            withAnimation(HelmMotion.interface) { shown = tab.id }
        } else {
            shown = tab.id
        }
        selection.wrappedValue = tab.id
    }
}
