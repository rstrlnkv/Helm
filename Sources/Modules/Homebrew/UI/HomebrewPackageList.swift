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
        case .installed: installedList()
        case .updates: updatesList()
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
    /// drawn: Health has no such section.
    ///
    /// `marksUpdates` reserves the update mark's slot on Installed so a
    /// hit's name lines up with the installed rows above it — `HomebrewPackageRow`'s own
    /// reason for taking `false` rather than nil there.
    @ViewBuilder
    private func availableRows(_ section: AvailableSection, hits: [SearchHit], marksUpdates: Bool) -> some View {
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

    /// The header row's search field filters this list as it is
    /// typed into (`HomebrewViewModel.shownInstalled`), and the "Available to
    /// install" section appears under it when the filter finds nothing and
    /// the pause has run its course, or after Return.
    private func installedList() -> some View {
        listOrEmpty(hb.installed, shown: hb.shownInstalled, reading: hb.installedReading,
                    nothing: HbStr.noneInstalled, unanswerable: HbStr.couldNotList,
                    waiting: HbStr.packagesLoading,
                    marksUpdates: true, section: hb.section, hits: hb.shownHits) { pkg in
            HomebrewPackageRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask, singleColumn: singleColumn,
                               hasUpdate: hasUpdate(pkg.id),
                               desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList() -> some View {
        VStack(spacing: 0) {
            // No bar of its own: «Upgrade all» is a declared action of the page's header
            // row, beside Refresh, on `HomebrewManager`'s `.helmWindowToolbar`, visible on
            // this segment only.
            listOrEmpty(hb.outdated, shown: hb.shownOutdated, reading: hb.outdatedReading,
                        nothing: HbStr.upToDate, unanswerable: HbStr.couldNotCheckForUpdates,
                        waiting: HbStr.checkingForUpdates,
                        marksUpdates: false, section: hb.section, hits: hb.shownHits) { pkg in
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
    /// **Four sentences for four states.** A refusal reads differently from a
    /// wait, or the pane spins over a question nothing will answer. `.noMatches`:
    /// rows exist and a query hides all of them, neither an empty answer nor a
    /// refusal.
    ///
    /// `shown` is `items` with the query applied — the two are equal when
    /// there is no query, which is what keeps every existing reading of the
    /// three original states unchanged. `section`/`hits` are the "Available
    /// to install" block that may sit under the rows; nil/`[]` draws nothing.
    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], shown: [T], reading: ListReading,
        nothing: String, unanswerable: String, waiting: String,
        marksUpdates: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // **The section forces the list shape, even over a list that is
        // itself completely empty.** A genuinely empty `installed` reads `.nothing`
        // whatever the query says; the section has to draw inside the `List` for its
        // waiting and refused sentences to be seen. A section is only ever non-nil once a needle has
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
                           marksUpdates: marksUpdates,
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
        marksUpdates: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // A `List` with no selection has no focusable rows, and selecting is
        // how the inspector is reached. No
        // `.onTapGesture`, no `.listRowBackground`: macOS draws the system
        // selection itself.
        List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
            Section(header: HomebrewColumnHeader(marksUpdates: marksUpdates, singleColumn: singleColumn)) {
                if let note = Self.ownListNote(screen, notes: notes) {
                    noteRow(note.text, busy: note.busy)
                } else {
                    ForEach(shown) { item in row(item) }
                }
            }
            if let section {
                Section(header: HelmSectionTitle(HbStr.availableToInstall)) {
                    availableRows(section, hits: hits, marksUpdates: marksUpdates)
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
