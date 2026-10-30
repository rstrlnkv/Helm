import SwiftUI
import HelmUI
import Module_Homebrew_Engine

struct HomebrewPackageList: View {
    @ObservedObject var hb: HomebrewViewModel
    let singleColumn: Bool

    // **Two arms, two views.** A switch of segment is a cut (`HomebrewManager`'s
    // transaction line) because the installed list and the updates list are
    // different views, not one view called with different rows.
    var body: some View {
        switch hb.segment {
        case .installed: installedList(singleColumn: singleColumn)
        case .updates: updatesList(singleColumn: singleColumn)
        // The manager mounts `HomebrewHealthPage` for this segment before it
        // asks for a list.
        case .health: EmptyView()
        }
    }

    /// The sentence a package list's own section draws instead of its rows,
    /// or nil when `screen` says to draw the rows themselves — apart from
    /// `packageList`'s `body`: which reading says which sentence is a
    /// decision. `notes` are the
    /// three sentences each call site already carries (`installedList`'s
    /// "No packages installed.", `updatesList`'s "Everything is up to date.",
    /// and the two refusals beside them); `.noMatches` earns the one sentence
    /// every tab shares, since a query hiding every row says the same thing
    /// on both.
    static func ownListNote(_ screen: ListScreen,
                            notes: (nothing: String, unanswerable: String, waiting: String))
        -> (text: String, busy: Bool)? {
        switch screen {
        case .rows: return nil
        case .noMatches: return (HbStr.noMatches, false)
        case .nothing: return (notes.nothing, false)
        case .unanswerable: return (notes.unanswerable, false)
        case .waiting: return (notes.waiting, true)
        }
    }

    /// **Not selectable, because there is nothing to select.** A note is
    /// the sentence standing in for rows there are none of, and a row that
    /// highlights and then describes nothing in the inspector is a row that
    /// looks broken. Shared by both package tabs' empty rows and by the
    /// "Available to install" section's own three sentences — one builder,
    /// so a note row cannot drift into three shapes across the page.
    private func noteRow(_ text: String, busy: Bool = false) -> some View {
        HelmBusyLabel(text, busy: busy)
            .foregroundStyle(HelmText.quiet)
            .helmListRow()
        .selectionDisabled()
    }

    /// **The "Available to install" section's own three sentences, and its
    /// rows.** Shared by both package tabs' `listOrEmpty`, the only place it is
    /// drawn: Состояние has no such section.
    ///
    /// `marksUpdates` reserves the update mark's slot on Установленные so a
    /// hit's name lines up with the installed rows above it — `HomebrewPackageRow`'s own
    /// reason for taking `false` rather than nil there.
    @ViewBuilder
    private func availableRows(_ section: AvailableSection, hits: [SearchHit],
                               singleColumn: Bool, marksUpdates: Bool) -> some View {
        switch section {
        case .searching: noteRow(HbStr.searching, busy: true)
        case .nothingFound: noteRow(HbStr.noResults)
        case .unanswerable: noteRow(HbStr.couldNotSearch)
        case .found:
            ForEach(hits) { hit in
                HomebrewPackageRow(name: hit.name, detail: nil, isCask: hit.isCask, singleColumn: singleColumn,
                                  hasUpdate: marksUpdates ? false : nil,
                                  desc: singleColumn ? hb.description(name: hit.name, isCask: hit.isCask) ?? " " : nil)
            }
        }
    }

    /// The window toolbar's own search field filters this list as it is
    /// typed into (`HomebrewViewModel.shownInstalled`), and the "Available to
    /// install" section appears under it when the filter finds nothing and
    /// the pause has run its course, or after Return.
    private func installedList(singleColumn: Bool) -> some View {
        listOrEmpty(hb.installed, shown: hb.shownInstalled, reading: hb.installedReading,
                    nothing: HbStr.noneInstalled, unanswerable: HbStr.couldNotList,
                    waiting: HbStr.packagesLoading,
                    columns: ListColumns(leading: HbStr.columnPackage, trailing: HbStr.tileVersion,
                                         marksUpdates: true),
                    singleColumn: singleColumn, section: hb.section, hits: hb.shownHits) { pkg in
            HomebrewPackageRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask, singleColumn: singleColumn,
                               hasUpdate: hasUpdate(pkg.id),
                               desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList(singleColumn: Bool) -> some View {
        VStack(spacing: 0) {
            // No bar of its own: «Обновить всё» is in the window's
            // own toolbar beside Refresh, declared on `HomebrewManager`'s
            // `.helmWindowToolbar` — visible on this very segment, hidden
            // everywhere else.
            listOrEmpty(hb.outdated, shown: hb.shownOutdated, reading: hb.outdatedReading,
                        nothing: HbStr.upToDate, unanswerable: HbStr.couldNotCheckForUpdates,
                        waiting: HbStr.checkingForUpdates,
                        columns: ListColumns(leading: HbStr.columnPackage, trailing: HbStr.tileVersion,
                                             marksUpdates: false),
                        singleColumn: singleColumn, section: hb.section, hits: hb.shownHits) { pkg in
                // A pinned formula and a cask can both carry a badge here — the
                // parser does not refuse a `pinned` flag on a cask entry, even
                // though `brew pin` only ever sets one on a formula
                // (`BrewOutdatedParser.swift`) — so both may be drawn without
                // choosing between them.
                HomebrewPackageRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask,
                                   singleColumn: singleColumn, pinned: pkg.pinned,
                                   desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
            }
        }
    }

    /// Whether an installed package has an update waiting, for the row's dot.
    /// The same reading `InspectorState.of` takes for the same package, so the
    /// row and the inspector cannot disagree about one fact.
    private func hasUpdate(_ id: String) -> Bool {
        if case .available = PackageStanding.updates(for: id, outdated: hb.outdated,
                                                      loadedOutdated: hb.loadedOutdated) {
            return true
        }
        return false
    }

    /// `T.ID == String`: every list here is keyed by a `BrewKey` id, which is
    /// also what `hb.selection` holds — no `String(describing:)` conversion
    /// needed at the boundary.
    ///
    /// **Four sentences for four states, and the fourth is new.** This took
    /// one `empty:` that went nil while a query was out, which is two states
    /// in one optional and no room at all for a third: a `brew` that refused
    /// left the flag behind it down for ever, so the pane drew the spinner and
    /// «Reading the package list…» over a question nothing was going to
    /// answer, with no timeout anywhere in the UI. `.noMatches` is the fourth,
    /// added with the field that filters every tab: rows exist and a query
    /// hides all of them, which is neither an empty answer nor a refusal.
    ///
    /// `shown` is `items` with the query applied — the two are equal when
    /// there is no query, which is what keeps every existing reading of the
    /// three original states unchanged. `section`/`hits` are the "Available
    /// to install" block that may sit under the rows; nil/`[]` draws nothing.
    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], shown: [T], reading: ListReading,
        nothing: String, unanswerable: String, waiting: String,
        columns: ListColumns, singleColumn: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // **The section forces the list shape, even over a list that is
        // itself completely empty.** `ListScreen.of` alone would still read a
        // genuinely empty `installed` as `.nothing` whatever the query says —
        // this Mac's own zero-package fixture drew the same «No packages
        // installed.» sentence whether a search was answering, waiting or
        // refusing, before the section moved inside the `List` this branch
        // draws now. A section is only ever non-nil once a needle has
        // actually been asked about (`AvailableSection.of`), so this cannot
        // force the list shape over an untyped field.
        let screen = ListScreen.of(isEmpty: items.isEmpty, shownIsEmpty: shown.isEmpty,
                                   reading: reading)
        let listShape = ListScreen.forcesListShape(section: section, screen: screen)
        // **One call to `packageList`, not two.** Once inside this `if` and
        // once in its `else`, SwiftUI reads them as two
        // different views at two different positions in the tree — moving
        // between "no section" and "a section just appeared" tore the table
        // down and rebuilt it, on every keystroke that flipped which branch
        // was taken, which is exactly the identity ARCHITECTURE.md § Design system says
        // SwiftUI never interpolates across. `screen` travels into the one call
        // site instead, and `packageList` reads the sentence for its own
        // reading out of it — the note this list draws for a waiting or
        // refused query does not disappear the moment the section takes
        // over the shape.
        return Group {
            if listShape {
                packageList(shown, screen: screen, notes: (nothing, unanswerable, waiting),
                           columns: columns, singleColumn: singleColumn,
                           section: section, hits: hits, row: row)
            } else if screen == .waiting {
                // `HelmBusyState()` is the bare spinner its own doc comment
                // names as one of the three shapes it exists to end; the
                // caller still has to say what is being waited on.
                HelmBusyState(waiting)
            } else if screen == .unanswerable {
                // The same still drawing as `.nothing` and a different
                // sentence: nothing is on its way, so nothing moves, and what
                // separates the two is the only thing that can — the words.
                HelmEmptyState(message: unanswerable)
            } else {
                HelmEmptyState(message: nothing)
            }
        }
    }

    /// The one `List` every package tab draws — its own rows or the sentence
    /// its own reading earns, and the "Available to install" section under
    /// them when there is one. The only call site `listOrEmpty` has, for the
    /// reason stated there: two would be two views to SwiftUI.
    ///
    /// **`screen` decides the first section's row, not `shown.isEmpty`
    /// alone.** A bare emptiness check read every non-row state — still
    /// waiting on `brew`, a refused query, an honestly empty answer — as the
    /// same «Nothing in this list matches.», which is the module's own
    /// "refused list is not an empty one" rule broken a second time, this
    /// time by the section rather than by a missing reading.
    private func packageList<T: Identifiable, Row: View>(
        _ shown: [T], screen: ListScreen, notes: (nothing: String, unanswerable: String, waiting: String),
        columns: ListColumns, singleColumn: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // A `List` with no selection has no focusable rows at all — arrow
        // keys did nothing. Selecting is also how the inspector is reached,
        // so this is the row's only door into the app now. No
        // `.onTapGesture`, no `.listRowBackground`: macOS draws the system
        // selection itself.
        List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
            Section(header: HomebrewColumnHeader(columns: columns, singleColumn: singleColumn)) {
                if let note = Self.ownListNote(screen, notes: notes) {
                    noteRow(note.text, busy: note.busy)
                } else {
                    ForEach(shown) { item in row(item) }
                }
            }
            if let section {
                Section(header: HelmSectionTitle(HbStr.availableToInstall)) {
                    availableRows(section, hits: hits, singleColumn: singleColumn,
                                 marksUpdates: columns.marksUpdates)
                }
            }
        }
        // **Striped, and no inset of its own.** These two lists are rows of
        // one shape and a great many of them, which is what a stripe is for: it
        // keeps the eye on a row while it crosses from a name to a version at
        // the far edge, and it puts the page with the other striped lists —
        // Uninstaller, Orphans and Leftovers stop at
        // `helmStripedList(rowPitch:)`; Disk, Autopilot and Duplicates stay
        // plain. The Health tab is not one of them: its rows are
        // paragraphs, one to three of them, with nothing to cross
        // (`HomebrewHealthPage`). No `.padding(.horizontal, HelmSpace.s5)`
        // here: it would put this page's rows 12 pt further in than the rows
        // of every other list in the app.
        .helmStripedList(rowPitch: HelmSpace.s8)
    }
}

/// What a package list's heading names, and whether the rows under it keep
/// the update mark's slot — the three facts `HomebrewColumnHeader` needs and nothing
/// else, so each call site spells them in one place.
struct ListColumns {
    let leading: String
    let trailing: String?
    let marksUpdates: Bool
}
