import SwiftUI

extension View {
    /// **The header row in the card, over this page.** One row for every page of the settings window, drawn
    /// at the root of the detail pane so it keeps its identity across a page switch: the page's name and
    /// status on the left, on the right what the page declared through `helmWindowToolbar` — tabs, actions,
    /// search (`HelmPageToolbarKey`). The page scrolls under it, as it does under `helmPageHeader`, and
    /// the pane reserves the row's height as a top inset.
    ///
    /// The declaration is read with `overlayPreferenceValue`: the value carries closures cut from the page's
    /// state at its last body, and a copy kept in `@State` behind an `==` would hold the old ones
    /// (`LogView`'s Copy captures `page.lines`).
    ///
    /// The empty part of the row drags the window, since there is no title bar under it any more.
    ///
    /// **The row has no right-click menu of its own**: it lies in the window's title bar zone, where a SwiftUI
    /// `.contextMenu` is never reached; the window pops one up (`HeaderBarMenu`) over the band
    /// `HelmCardHeaderBand.height` names.
    public func helmCardHeader(symbol: String, tint: Color, title: String, status: HelmHeaderStatus?) -> some View {
        modifier(CardHeader(symbol: symbol, tint: tint, title: title, status: status))
    }
}

/// The header row's height, for the window that decides which presses are the row's.
@MainActor public enum HelmCardHeaderBand {
    public static let height = CardHeader.height
}

private struct CardHeader: ViewModifier {
    let symbol: String
    let tint: Color
    let title: String
    let status: HelmHeaderStatus?

    @State private var scrolled = false
    @State private var standsOnStillContent = false
    @Environment(\.helmWindowAppearsActive) private var windowAppearsActive
    @Environment(\.helmTabsSink) private var tabsSink
    @Environment(\.helmBarAppearance) private var look
    @Environment(\.helmHeaderChoices) private var choices
    @Environment(\.helmTraits) private var traits
    /// This row's token for the tabs' sink (`HelmTabsSink`); a rebuilt pane root makes a new row and a new one, and
    /// so does each leaving of Glass: the relay's dismantle retires the token for good, so the relay and the slot
    /// that mount when Glass returns must not carry it.
    @State private var owner = UUID()

    /// The Kit's 36 pt controls (`HelmHeaderActions.side`) with `HelmSpace.s4` above and below (`HelmPageHeader`).
    static let height = HelmSpace.s4 * 2 + HelmHeaderActions.side
    /// The Kit's `Toolbar` (Figma 309:216): the plate 14 from the card's left edge, the controls 10 from its right.
    static let leadingInset = CGFloat(14)
    static let trailingInset = CGFloat(10)
    /// Where the toolbar centres an item (window y 26) against the row's centre (y 30: `ShellGeometry.inset` 4 + 26).
    static let raise = CGFloat(4)

    /// Where the tabs go: only under Glass, where the window has a toolbar to take them.
    private var tabsTarget: HelmTabsTarget? {
        look == .liquidGlass ? tabsSink.map { HelmTabsTarget(owner: owner, sink: $0) } : nil
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: look) { _, now in if now != .liquidGlass { owner = UUID() } }
            .onPreferenceChange(HelmPageScrolledKey.self) { scrolled = $0 }
            .onPreferenceChange(HelmPageStandsOnStillContentKey.self) { standsOnStillContent = $0 }
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: Self.height) }
            .overlayPreferenceValue(HelmPageToolbarKey.self, alignment: .top) { controls in
                HelmPageHeader(symbol: symbol, tint: tint, title: title, bleeds: true,
                               overContent: true, scrolled: scrolled,
                               standsOnStillContent: standsOnStillContent, status: status,
                               dimmed: !windowAppearsActive, leadingInset: Self.leadingInset,
                               trailingInset: Self.trailingInset, raise: tabsTarget == nil ? 0 : Self.raise) {
                    HelmHeaderControls(content: controls, page: title, tabs: tabsTarget,
                                       style: choices.tabLabels)
                }
                .frame(height: Self.height)
                .background {
                    if let target = tabsTarget {
                        HelmTabsRelay(target: target, content: controls, style: choices.tabLabels,
                                      increasedContrast: traits.increasedContrast)
                    }
                }
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
            }
    }
}

/// Tabs, then actions and search, in that order; each only where the page declared it. The tabs are the row's
/// own part (`HeaderRole.tabs`, centred by `HeaderRowLayout`), the actions and the search two runs on the right, which the
/// layout packs `HelmHeaderActions.gap` apart.
private struct HelmHeaderControls: View {
    let content: HelmPageToolbarContent?
    /// The page's name: the search slot's identity, so what it holds open does not leak to the next page. Never the tabs'.
    let page: String
    /// Set where the tabs are the window's toolbar item: the row keeps a placeholder for them (`HelmTabsSlot`).
    let tabs: HelmTabsTarget?
    let style: ToolbarSwitcherStyle

    var body: some View {
        if let content {
            if !content.tabs.isEmpty, let selected = content.selectedTab {
                Group {
                    if let tabs {
                        HelmTabsSlot(target: tabs, tabs: content.tabs, style: style)
                    } else {
                        HelmHeaderTabs(tabs: content.tabs, selection: selected, enabled: content.tabsEnabled)
                    }
                }
                .layoutValue(key: HeaderRoleKey.self, value: .tabs)
            }
            if !content.actions.isEmpty {
                HelmHeaderActions(actions: content.actions)
            }
            if let search = content.search {
                HelmHeaderSearch(search: search).id(page)
            }
        }
    }
}

/// What a part of the header row is, for `HeaderRowLayout`. A part that says nothing is a run on the right.
enum HeaderRole { case name, tabs, run }

struct HeaderRoleKey: LayoutValueKey {
    static let defaultValue = HeaderRole.run
}

/// **The row's parts: the name's side, the tab strip, and the runs (the actions, then the search) — the strip centred on
/// the card's row, giving way to either neighbour.** `shift` is how far the card's centre lies right of this
/// layout's own (the row's insets are not equal, `CardHeader`), so the strip's centre is the card's, not the padded
/// area's. It never overlaps: it keeps `nameGap` after the name's side and `HelmHeaderActions.gap` before the runs.
/// **The run's width is the room of every declared action, hidden or not** (`HelmHeaderActions`), so on Homebrew
/// the strip sits ~40 pt left of centre where an action is hidden on that tab; ignoring the hidden slot would make
/// the strip jump between that page's tabs.
///
/// **At the narrowest the row is what the old stack made**: name, `nameGap` (36: 12, the old stack's spacer's least 12, 12), strip,
/// `gap`, run — the sum `SettingsWindow.minSize` is measured against — because both limits close on the strip there.
struct HeaderRowLayout: Layout {
    let shift: CGFloat
    static let nameGap = CGFloat(36)

    private struct Parts {
        let name: CGSize
        let tabs: CGSize?
        let runs: [CGSize]
    }

    private func parts(_ subviews: Subviews) -> Parts {
        func size(_ role: HeaderRole) -> [CGSize] {
            subviews.filter { $0[HeaderRoleKey.self] == role }.map { $0.sizeThatFits(.unspecified) }
        }
        return Parts(name: size(.name).first ?? .zero, tabs: size(.tabs).first, runs: size(.run))
    }

    /// The runs packed against the right edge, each `gap` from the next: their total width.
    private func runWidth(_ runs: [CGSize]) -> CGFloat {
        runs.reduce(0) { $0 + $1.width } + HelmHeaderActions.gap * CGFloat(max(0, runs.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = parts(subviews)
        let strip = (p.tabs?.width ?? 0) + (p.tabs != nil && !p.runs.isEmpty ? HelmHeaderActions.gap : 0)
        let beside = strip + runWidth(p.runs)
        let least = p.name.width + (beside > 0 ? Self.nameGap : 0) + beside
        let height = ([p.name.height, p.tabs?.height ?? 0] + p.runs.map(\.height)).max() ?? 0
        return CGSize(width: proposal.width.map { max($0, least) } ?? least, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = parts(subviews)
        let anchor = UnitPoint.leading
        func put(_ subview: LayoutSubview, _ x: CGFloat) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: anchor, proposal: .unspecified)
        }
        var right = bounds.maxX
        for subview in subviews.reversed() where subview[HeaderRoleKey.self] == .run {
            right -= subview.sizeThatFits(.unspecified).width
            put(subview, right)
            right -= HelmHeaderActions.gap
        }
        let hasRun = !p.runs.isEmpty
        for subview in subviews where subview[HeaderRoleKey.self] == .name { put(subview, bounds.minX) }
        guard let strip = p.tabs, let tabs = subviews.first(where: { $0[HeaderRoleKey.self] == .tabs }) else { return }
        let latest = (hasRun ? right : bounds.maxX) - strip.width
        let earliest = bounds.minX + p.name.width + Self.nameGap
        let centred = bounds.midX + shift - strip.width / 2
        put(tabs, max(earliest, min(centred, latest)))
    }
}
