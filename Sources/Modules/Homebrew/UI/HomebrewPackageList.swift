import SwiftUI
import HelmUI
import Module_Homebrew_Engine

struct HomebrewPackageList: View {
    @ObservedObject var hb: HomebrewViewModel

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
    /// or nil when `screen` says to draw the rows themselves. `notes` are the
    /// call site's own three sentences; `.noMatches` is the one every tab
    /// shares.
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

    /// **Not selectable, because there is nothing to select.** One builder for
    /// every note row on the page, the section's included.
    private func noteRow(_ text: String, busy: Bool = false) -> some View {
        HelmBusyLabel(text, busy: busy)
            .foregroundStyle(HelmText.quiet)
            // Separator hidden, as on the rows (`HomebrewPackageRow`).
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    /// **The "Available to install" section's own three sentences, and its
    /// rows.** Shared by both package tabs' `listOrEmpty`, the only place it is
    /// drawn: Health has no such section.
    ///
    /// `marksUpdates` reserves the update mark's slot on Installed so a hit's
    /// name lines up with the installed rows above it.
    @ViewBuilder
    private func availableRows(_ section: AvailableSection, hits: [SearchHit], marksUpdates: Bool) -> some View {
        switch section {
        case .searching: noteRow(HelmWord.searching, busy: true)
        case .nothingFound: noteRow(HbStr.noResults)
        case .unanswerable: noteRow(HbStr.couldNotSearch)
        case .found:
            ForEach(hits) { hit in
                HomebrewPackageRow(name: hit.name, detail: nil, isCask: hit.isCask,
                                  hasUpdate: marksUpdates ? false : nil)
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
            HomebrewPackageRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask,
                               hasUpdate: hasUpdate(pkg.id))
        }
    }

    private func updatesList() -> some View {
        VStack(spacing: 0) {
            HelmSettingRow(HbStr.updateBeforeChecking, note: HbStr.updateBeforeCheckingNote) {
                Toggle(HbStr.updateBeforeChecking,
                       isOn: Binding(get: { hb.refreshesBeforeChecking },
                                     set: { hb.setRefreshesBeforeChecking($0) }))
                    .labelsHidden()
            }
            .helmPageStrip()
            Divider()
            // No bar of its own: «Upgrade all» is a declared action of the page's header
            // row, beside Refresh, on `HomebrewManager`'s `.helmHeaderContent`, visible on
            // this segment only.
            listOrEmpty(hb.outdated, shown: hb.shownOutdated, reading: hb.outdatedReading,
                        nothing: HbStr.upToDate, unanswerable: HbStr.couldNotCheckForUpdates,
                        waiting: HbStr.checkingForUpdates,
                        marksUpdates: false, section: hb.section, hits: hb.shownHits) { pkg in
                // The parser does not refuse `pinned` on a cask entry
                // (`BrewOutdatedParser.swift`), so both badges may be drawn.
                HomebrewPackageRow(name: pkg.name, detail: pkg.versionStep, isCask: pkg.isCask, pinned: pkg.pinned)
            }
        }
    }

    /// Whether an installed package has an update waiting, for the row's dot.
    /// The same reading `InspectorState.of` takes, so the two cannot disagree.
    private func hasUpdate(_ id: String) -> Bool {
        if case .available = PackageStanding.updates(for: id, outdated: hb.outdated,
                                                      loadedOutdated: hb.loadedOutdated) {
            return true
        }
        return false
    }

    /// `T.ID == String`: every list here is keyed by a `BrewKey` id, which is
    /// also what `hb.selection` holds.
    ///
    /// **Four sentences for four states.** A refusal reads differently from a
    /// wait, or the pane spins over a question nothing will answer. `.noMatches`:
    /// rows exist and a query hides all of them, neither an empty answer nor a
    /// refusal.
    ///
    /// `shown` is `items` with the query applied, equal with no query.
    /// `section`/`hits` are the "Available to install" block that may sit under
    /// the rows; nil/`[]` draws nothing.
    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], shown: [T], reading: ListReading,
        nothing: String, unanswerable: String, waiting: String,
        marksUpdates: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // **The section forces the list shape, even over an empty list:** it
        // draws inside the `List`. It is non-nil only once a word has been
        // asked about (`AvailableSection.of`).
        let screen = ListScreen.of(isEmpty: items.isEmpty, shownIsEmpty: shown.isEmpty,
                                   reading: reading)
        let listShape = ListScreen.forcesListShape(section: section, screen: screen)
        // **One call to `packageList`, not two:** two call sites are two views
        // to SwiftUI, and a section appearing would rebuild the table on a
        // keystroke (ARCHITECTURE.md § Design system). `screen` travels into
        // the one call, which reads its own sentence out of it.
        return Group {
            if listShape {
                packageList(shown, screen: screen, notes: (nothing, unanswerable, waiting),
                           marksUpdates: marksUpdates,
                           section: section, hits: hits, row: row)
            } else if screen == .waiting {
                // Says what is being waited on, not a bare spinner.
                HelmBusyState(waiting)
            } else if screen == .unanswerable {
                // Still, like `.nothing`; only the words differ.
                HelmEmptyState(message: unanswerable)
            } else {
                HelmEmptyState(message: nothing)
            }
        }
    }

    /// The one `List` every package tab draws — its own rows or the sentence
    /// its own reading earns, and the "Available to install" section under
    /// them when there is one.
    ///
    /// **`screen` decides the first section's row, not `shown.isEmpty`
    /// alone:** waiting, refused and empty are not «Nothing in this list
    /// matches.».
    private func packageList<T: Identifiable, Row: View>(
        _ shown: [T], screen: ListScreen, notes: (nothing: String, unanswerable: String, waiting: String),
        marksUpdates: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // Selecting is how the inspector is reached. No `.onTapGesture`, no
        // `.listRowBackground`: macOS draws the system selection itself.
        List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
            Section(header: HomebrewColumnHeader(marksUpdates: marksUpdates)) {
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
        // **Striped, and no inset of its own.** Many rows of one shape: the
        // stripe keeps the eye on a row from the name to the version at the
        // far edge. A horizontal padding here would set these rows further in
        // than every other list in the app.
        .helmStripedList(rowPitch: HelmSpace.s8)
    }
}
