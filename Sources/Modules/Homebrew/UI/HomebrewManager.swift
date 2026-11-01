import SwiftUI
import HelmUI

struct HomebrewManager: View {
    @ObservedObject var hb: HomebrewViewModel

    /// Counts as a quiet status line rather than a panel of dials.
    private var statusLine: String {
        // **Three readings, three sentences.** A count that has not arrived is
        // not a count of zero — the list reloads after every operation, and for
        // that second the line read "0 packages · 0 updates · 0 casks" over a
        // machine with 53 of them. And a count that *cannot* arrive is not a
        // count on its way: `loadedInstalled` is `installedReading == .answered`
        // and so false for `.waiting` and `.unanswerable` alike, which would
        // put «Reading the package list…» in the bar under a master already
        // saying Homebrew had not answered.
        // `ListScreen.of` makes the same three-way distinction for the list
        // itself; this is the bar's half of it.
        switch hb.installedReading {
        case .notAsked, .waiting: return HbStr.packagesLoading
        case .unanswerable: return HbStr.couldNotCount
        case .answered: break
        }
        // The same rule for updates, which this guard fixed only half of the
        // first time: `loadIfNeeded` deliberately never asks `brew outdated`,
        // so on first open the line said «Updates: 0» about a question with no
        // answer — for as long as nobody visited the Updates tab.
        guard hb.loadedOutdated else {
            return HbStr.packagesStatusNoUpdates(hb.installed.count,
                                                 hb.installed.filter(\.isCask).count)
        }
        return HbStr.packagesStatus(hb.installed.count,
                             hb.outdated.count,
                             hb.installed.filter(\.isCask).count)
    }

    /// The height a bordered button gives the other list screens' bars, for the
    /// caption here to match. Off the space ladder on purpose.
    private static let statusBarContent: CGFloat = 25

    var body: some View {
        VStack(spacing: 0) {
            // The split is asked of the pane, not of the window: `HomebrewSplit`
            // carries the measured threshold, and a `private var` inside `body`
            // would be out of a test's reach (`HomebrewSplit.swift`'s own reason).
            //
            // **The width decides the container, `HomebrewInspector` decides the
            // content.** Above the threshold the list and the subject sit side
            // by side; below it, selecting a row replaces the list with that
            // same view at full width, with `backBar` above it to return —
            // `packageDetail` is the one builder, called from
            // both places, so a wide inspector and a narrow screen cannot
            // drift into offering two different things for one of them.
            GeometryReader { proxy in
                let split = HomebrewSplit(availableWidth: proxy.size.width)
                if hb.segment == .health {
                    // **Not a master and a subject, at any width.** Health
                    // is one page whose findings open where they stand
                    // (`HomebrewHealthPage`), so the split is not asked and
                    // no selection exists to put a back bar over.
                    listArea(singleColumn: false)
                } else if split.showsInspector {
                    // **No stack spacing — the list meets the divider.** An equal
                    // `HelmSpace.s5` either side of `Divider()` leaves the master
                    // column 12 pt short of the line it is supposed to run to, and
                    // only the list's own side of that gap is to close. So the
                    // stack itself carries none, `HomebrewSplit.masterWidth`
                    // hands the master column the 12 pt the gap would spend, and
                    // the 12 pt on the inspector's side is `HomebrewInspector`'s
                    // own leading padding below.
                    HStack(spacing: 0) {
                        listArea(singleColumn: split.singleColumn)
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
                } else if hb.selected != nil {
                    // Selection already lives in `HomebrewViewModel`, per
                    // segment, so a non-nil `selected` is the whole of what
                    // puts this screen up — nothing new to hold here, and
                    // widening past the threshold with a package selected
                    // lands on that same package beside the list rather than
                    // on nothing, because both branches read the one selection.
                    VStack(spacing: 0) {
                        backBar
                        Divider()
                        HomebrewInspector(hb: hb)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    // No selection and no room for a second column: the list
                    // alone, with the description back on the row — the one
                    // thing the package view was carrying for it.
                    listArea(singleColumn: split.singleColumn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Counts belong in a quiet bottom bar, like the other list screens;
            // the toolbar is for what you can do, not for what there is.
            Divider()
            HStack {
                Text(statusLine)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                Spacer()
            }
            // A caption is shorter than a button: without this the bar was
            // 38 pt where the other two list screens are 49, and the content
            // jumped when switching between them.
            .frame(minHeight: Self.statusBarContent)
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
        }
        // **A press on a row moves; a switch of segment cuts.** Below
        // `HomebrewSplit`'s threshold a press on a row swaps the whole pane for
        // the package, and that swap runs on one token, the same one the other
        // list screens use.
        //
        // `hb.selected == nil` and not `hb.selected`: what the narrow branch
        // turns on is whether *anything* is selected, so this is the value that
        // swaps the pane. Keyed on the selection itself, moving between two
        // packages beside the list would animate a pane that is not swapping.
        //
        // **Switching segment carries no curve** («вкладки везде переключаются
        // резко»): the two lists are different views, so an animation is a
        // crossfade, and the two columns put a package's name 19 pt apart, which
        // draws every name twice for a few frames. `selected` is per segment, so a switch can also
        // flip `selected == nil`; the transaction line below is *inner* to the
        // curve line, where the nearer modifier wins, and so a switch of segment
        // reaches the pane as a cut even when it changes what is selected.
        .transaction(value: hb.segment) { $0.animation = nil }
        .animation(HelmMotion.interface, value: hb.selected == nil)
        // **The page's controls, in the header row of the window's card**, through the contract every module
        // page shares (`HelmWindowToolbar.swift` in `HelmUI`).
        //
        // **Upgrade all leaves the actions off Updates rather than being dimmed on every segment**
        // (`isVisible`). The row reserves the full width of every
        // declared action (`HelmHeaderActions`), so Refresh, always visible, stays exactly still while
        // Upgrade All comes and goes.
        .helmWindowToolbar(HelmPageToolbarContent(
            tabs: HomebrewViewModel.Segment.allCases.map {
                HelmToolbarTab(id: $0.rawValue, title: $0.label)
            },
            selectedTab: Binding(
                get: { hb.segment.rawValue },
                set: { hb.segment = HomebrewViewModel.Segment(rawValue: $0) ?? hb.segment }),
            actions: [
                HelmToolbarAction(id: "upgradeAll", title: HbStr.upgradeAll,
                                  symbol: "arrow.down.to.line",
                                  isEnabled: !hb.running && !hb.outdated.isEmpty,
                                  isVisible: hb.segment == .updates) {
                    hb.upgradeAll()
                },
                HelmToolbarAction(id: "refresh", title: HbStr.refreshList,
                                  symbol: "arrow.clockwise", isEnabled: !hb.running) {
                    Task { await refresh(hb.segment) }
                }
            ],
            // **On every tab, and the view model owns the query**, not this
            // page's `@State`: typing filters whichever list is on screen, and
            // `HomebrewViewModel.queryMoved` starts the pause toward an
            // automatic `brew search` when that filter finds nothing. Return
            // is `searchNow()`, which asks at once, with no pause and no
            // minimum length, unless that word is already answered or still
            // out — a refusal earns nothing kept, so Return asks again then.
            search: HelmToolbarSearch(
                prompt: HbStr.searchPlaceholder,
                text: Binding(get: { hb.query }, set: { hb.query = $0 })) {
                hb.searchNow()
            }
        ), token: HomebrewDescriptor.id.rawValue)
        // On the page rather than on the picker: a toolbar item's view is
        // hosted by the window's toolbar and its lifetime is the toolbar's,
        // so a change handler hung on it is not something this page can
        // count on being mounted when the segment moves.
        .onChange(of: hb.segment) { _, segment in
            Task { await refresh(segment) }
        }
    }

    @ViewBuilder
    private func listArea(singleColumn: Bool) -> some View {
        switch hb.segment {
        case .installed, .updates: HomebrewPackageList(hb: hb, singleColumn: singleColumn)
        // No columns and no inspector: the tab is one page (`HomebrewHealthPage`),
        // which `HomebrewManager` mounts before it asks the split anything.
        case .health: HomebrewHealthPage(hb: hb)
        }
    }

    /// The narrow screen's way out of `packageDetail`, back to the list —
    /// `select(nil)` is the whole of it, the same setter the list's own
    /// deselect already calls, so there is nothing new to hold for this. Same
    /// shape as Disk's own `BreadcrumbBar` back control — a bordered glyph
    /// button, `.help` for a sighted press and `.accessibilityLabel` for
    /// VoiceOver, which is what a control with no word needs to be read at all.
    private var backBar: some View {
        HStack(spacing: HelmSpace.s3) {
            Button {
                hb.select(nil)
            } label: {
                Image(systemName: "chevron.backward")
            }
            .help(HbStr.back)
            .accessibilityLabel(HbStr.back)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// Which list a segment is showing, and therefore which one Refresh
    /// reloads. Search is not a case here: a `brew search` in
    /// flight is not "cached" the way a package list is, and Refresh does not
    /// reach it; `searchNow()` on the toolbar's own field is the
    /// door to asking brew again.
    private func refresh(_ segment: HomebrewViewModel.Segment) async {
        switch segment {
        case .installed: await hb.refreshInstalled()
        case .updates: await hb.refreshOutdated()
        // Both halves of this segment, and `brew config` first on purpose: it
        // is one fast local run where `brew doctor` is the slowest query in the
        // module, so asking it first puts the Configuration heading on screen
        // while the Checkup one is still saying what it is waiting for.
        case .health:
            await hb.refreshConfig()
            await hb.refreshDoctor()
        }
    }
}
