import SwiftUI

/// **The page's tabs in the header row: always whole, never folded.** Labelled by their word, a glyph or both
/// (`ToolbarSwitcherStyle`, `HelmHeaderChoices`).
///
/// Under `.flat` a plate of `HelmSurface.barPlate` holds the tabs and the pick is `HelmSurface.barPick`; the pick
/// slides to a pressed tab, inside `HelmMotion.interface` and only where `HelmMotion.moves` says so; a tab the
/// page itself selects (a page switch, an Uninstaller step) moves it without travel. Under `.liquidGlass` the strip
/// is the system's own segmented control (`NSSegmentedControl`, `.extraLarge` = 36 pt), which draws the glass
/// pick and the lens under a held press itself; SwiftUI's `Picker` could not carry the attention dot over its
/// segment, nor name every segment's width. The selection the page owns is written outside the animation, so the
/// page below is not swapped inside it.
public struct HelmHeaderTabs: View {
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

    public init(tabs: [HelmToolbarTab], selection: Binding<String>, enabled: Bool) {
        self.tabs = tabs
        self.selection = selection
        self.enabled = enabled
        _shown = State(initialValue: selection.wrappedValue)
    }

    /// The Kit's Segmented tabs (Figma 8:91), `.flat`: a 36 pt strip, 4 inside it a pill of 28 (radius 14, a
    /// capsule), 9 pt either side of a word, 5 between two tabs.
    private static let plate: CGFloat = 4
    private static let pill = HelmHeaderActions.side - 2 * plate

    public var body: some View {
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
            system
        }
    }

    /// The system's control, with what it cannot say laid over it: for each segment, at its measured place, the
    /// attention dot and the accessibility element (label, value, selected). The overlay takes no press.
    private var system: some View {
        let widths = SystemSegments.widths(tabs, choices.tabLabels)
        return SystemSegments(tabs: tabs, widths: widths, style: choices.tabLabels, shown: shown) { press($0) }
            // The environment's size is what SwiftUI sets on the control, whatever `makeNSView` chose.
            .controlSize(.extraLarge)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        Color.clear.frame(width: widths[index], height: HelmHeaderActions.side)
                            .overlay(alignment: .topTrailing) { dot(tab).offset(x: -6, y: 8) }
                            .accessibilityElement()
                            .accessibilityLabel(tab.title)
                            .accessibilityValue(tab.attentionNote ?? "")
                            .accessibilityAddTraits(tab.id == shown ? .isSelected : [])
                    }
                }
                .allowsHitTesting(false)
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
                Capsule().fill(HelmSurface.barPick).matchedGeometryEffect(id: "pick", in: space)
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
        if appearance == .flat, HelmMotion.moves(reduceMotion: traits.reducedMotion) {
            withAnimation(HelmMotion.interface) { shown = tab.id }
        } else {
            shown = tab.id
        }
        selection.wrappedValue = tab.id
    }
}

/// **The system's segmented control**, every segment's width set from its own label so no word is cut and the
/// dot and the accessibility elements laid over it (`HelmHeaderTabs.system`) stand where the segments are: the
/// widths sum to the control's width (measured: `fittingSize` of explicit widths is their sum, no inset).
private struct SystemSegments: NSViewRepresentable {
    let tabs: [HelmToolbarTab]
    let widths: [CGFloat]
    let style: ToolbarSwitcherStyle
    let shown: String
    let press: (HelmToolbarTab) -> Void

    private static let font = NSFont.systemFont(ofSize: 13)
    /// Either side of a word or glyph, and the glyph's own width. With the glyph a segment is the `.flat` tab's
    /// width (9 either side, 16 for the glyph); without it 12 either side, which for the three of the Log page
    /// is the whole `.flat` strip's width (3 x 18 + 2 x 5 + 8), so `SettingsWindow.minSize` holds under both looks.
    private static let pad = CGFloat(12)
    private static let glyph = CGFloat(16)

    static func widths(_ tabs: [HelmToolbarTab], _ style: ToolbarSwitcherStyle) -> [CGFloat] {
        tabs.map { tab in
            let word = ceil((tab.title as NSString).size(withAttributes: [.font: font]).width)
            switch style {
            case .text: return word + 2 * pad
            case .icons: return 38
            case .iconsAndText: return glyph + 6 + word + 18
            }
        }
    }

    final class Coordinator: NSObject {
        var tabs: [HelmToolbarTab] = []
        var press: (HelmToolbarTab) -> Void = { _ in }
        @objc func picked(_ sender: NSSegmentedControl) {
            if tabs.indices.contains(sender.selectedSegment) { press(tabs[sender.selectedSegment]) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.picked(_:))
        // The overlay speaks for the segments (`HelmHeaderTabs.system`).
        control.setAccessibilityElement(false)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.tabs = tabs
        context.coordinator.press = press
        control.isEnabled = context.environment.isEnabled
        // The row keeps one control across a page switch, so the count follows the tabs of the page now showing.
        control.segmentCount = tabs.count
        for (index, tab) in tabs.enumerated() {
            control.setWidth(widths[index], forSegment: index)
            control.setLabel(style == .icons ? "" : tab.title, forSegment: index)
            let size: CGFloat = style == .icons ? 15 : 13
            control.setImage(style == .text ? nil : NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular)), forSegment: index)
            control.setToolTip(style == .icons ? tab.title : nil, forSegment: index)
        }
        control.selectedSegment = tabs.firstIndex { $0.id == shown } ?? -1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: widths.reduce(0, +), height: HelmHeaderActions.side)
    }
}
