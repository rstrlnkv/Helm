import SwiftUI
import HelmUI

struct HomebrewManager: View {
    @ObservedObject var hb: HomebrewViewModel

    /// Counts as a quiet status line rather than a panel of dials.
    private var statusLine: String {
        // **Three readings, three sentences:** a count that has not arrived is
        // not zero, and one that cannot arrive is not on its way. The bar's
        // half of `ListScreen.of`.
        switch hb.installedReading {
        case .notAsked, .waiting: return HbStr.packagesLoading
        case .unanswerable: return HbStr.couldNotCount
        case .answered: break
        }
        // The same for updates: `loadIfNeeded` never asks `brew outdated`.
        let casks = hb.installed.filter(\.isCask).count
        guard hb.loadedOutdated else {
            return HbStr.packagesStatusNoUpdates(hb.installed.count, casks)
        }
        return HbStr.packagesStatus(hb.installed.count, hb.outdated.count, casks)
    }

    /// The height a bordered button gives the other list screens' bars, for the
    /// caption here to match. Off the space ladder on purpose.
    private static let statusBarContent: CGFloat = 25

    var body: some View {
        VStack(spacing: 0) {
            // The split is asked of the pane, not of the window
            // (`HomebrewSplit`). The inspector is always beside the list.
            GeometryReader { proxy in
                let split = HomebrewSplit(availableWidth: proxy.size.width)
                if hb.segment == .health {
                    // Health is one page: the split is not asked.
                    listArea
                } else {
                    // **No stack spacing — the list meets the divider.** The
                    // gap is on the inspector's side alone, its leading padding
                    // below; `HomebrewSplit.masterWidth` gives the master its share.
                    HStack(spacing: 0) {
                        listArea
                            // `minWidth` and the compressibility it buys: a fixed `width:` here
                // would move the floor `HomebrewSplit` carries.
                            .frame(minWidth: HomebrewSplit.masterMinimum, idealWidth: split.masterWidth,
                                   maxWidth: split.masterWidth)
                        Divider()
                        HomebrewInspector(hb: hb)
                            .frame(minWidth: HomebrewSplit.inspectorMinimum, maxWidth: .infinity, maxHeight: .infinity,
                                  alignment: .topLeading)
                            // The gap between the divider and this column, kept
                            // here rather than in the stack, so it stays on the
                            // inspector's side alone.
                            .padding(.leading, HelmSpace.s5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Counts belong in a quiet bottom bar, like the other list screens;
            // the toolbar is for what you can do, not for what there is.
            Divider()
            HStack {
                Text(statusLine)
                    .helmQuietDetail()
                Spacer()
            }
            // A caption is shorter than a button: this keeps the bar as tall as
            // the other list screens' bars.
            .frame(minHeight: Self.statusBarContent)
            .helmPageStrip()
        }
        // **A press on a row moves; a switch of segment cuts.** A press on a row
        // moves the inspector, on the token the other list screens use.
        //
        // `hb.selected == nil` and not `hb.selected`: moving between two
        // packages must not animate a pane that is not changing.
        //
        // **Switching segment carries no curve:** the two lists are different
        // views, and a crossfade draws every name twice. The transaction line
        // is inner to the curve line, and the nearer modifier wins, so a
        // switch is a cut even when it changes `selected == nil`.
        .transaction(value: hb.segment) { $0.animation = nil }
        .animation(HelmMotion.interface, value: hb.selected == nil)
        // **The page's controls, in the header row of the window's card**, through the contract every module
        // page shares (`HelmHeaderContent.swift` in `HelmUI`).
        //
        // **Upgrade all is hidden off Updates, not dimmed** (`isVisible`). The
        // row reserves every declared action's width (`HelmHeaderActions`), so
        // Refresh stays still.
        .helmHeaderContent(HelmHeaderContent(
            tabs: HomebrewViewModel.Segment.allCases.map {
                HelmHeaderTab(id: $0.rawValue, title: $0.label, symbol: $0.symbol)
            },
            selectedTab: Binding(
                get: { hb.segment.rawValue },
                set: { hb.segment = HomebrewViewModel.Segment(rawValue: $0) ?? hb.segment }),
            actions: [
                HelmHeaderAction(id: "upgradeAll", title: HbStr.upgradeAll,
                                  symbol: "arrow.down.to.line",
                                  isEnabled: !hb.running && !hb.outdated.isEmpty,
                                  isVisible: hb.segment == .updates) {
                    hb.upgradeAll()
                },
                HelmHeaderAction(id: "refresh", title: HbStr.refreshList,
                                  symbol: "arrow.clockwise", isEnabled: !hb.running) {
                    Task { await refresh(hb.segment) }
                }
            ],
            // On every tab; the view model owns the query
            // (Architecture/Homebrew.md § Searching for a package).
            search: HelmHeaderQuery(
                prompt: HbStr.searchPlaceholder,
                text: Binding(get: { hb.query }, set: { hb.query = $0 })) {
                hb.searchNow()
            }
        ))
        // On the page rather than on the picker, whose lifetime is the
        // toolbar's.
        .onChange(of: hb.segment) { _, segment in
            Task { await refresh(segment) }
        }
    }

    @ViewBuilder
    private var listArea: some View {
        switch hb.segment {
        case .installed, .updates: HomebrewPackageList(hb: hb)
        case .health: HomebrewHealthPage(hb: hb)
        }
    }

    /// Which list a segment is showing, and therefore which one Refresh
    /// reloads. Refresh does not reach a search; Return does (`searchNow()`).
    private func refresh(_ segment: HomebrewViewModel.Segment) async {
        switch segment {
        case .installed: await hb.refreshInstalled()
        case .updates: await hb.refreshOutdated()
        // `brew config` first: it is fast, so the configuration is on screen
        // while `brew doctor`, the slowest query, is still out.
        case .health:
            await hb.refreshConfig()
            await hb.refreshDoctor()
        }
    }
}
