import AppKit
import SwiftUI
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// The copy on disk, not the bundle id — the same identity `UninstallGroup.id`
/// carries, and for the same reason one step earlier: `WorkspaceAppLister` reads
/// four folders and deduplicates by *path* precisely because a Setapp copy and a
/// direct download share an id, and a `ForEach` given one identity for two rows
/// is what SwiftUI answers with «undefined results».
extension InstalledApp: Identifiable { public var id: String { path } }

/// Two steps, AppCleaner-style: tick the apps to remove, then review the files
/// found for each of them before anything goes to the Trash. A running app is
/// never removed silently — it is quit first, and only if the user says so.
struct UninstallerSettingsPage: View {
    @ObservedObject private var uvm: UninstallerViewModel

    /// What survives a sidebar click is exactly what the person cannot retype:
    /// the permission is re-probed on every appearance and a search term costs a
    /// second. Everything else — what is ticked, which step, the scan, the
    /// failure report — is on the view model. See `UninstallerViewModel.step`.
    @State private var diskAccess: PermissionState = .granted
    @State private var search = ""

    /// Installed apps, or leftovers from apps that are already gone — a
    /// string-backed id rather than an index, the way `HelmToolbarTab.id`
    /// wants it: an index would silently mis-read if the two tabs ever
    /// reordered.
    private enum Tab: String { case apps, orphans }
    @State private var tab: Tab = .apps

    init(vm: ModuleViewModel) {
        uvm = UninstallerViewModel.shared(vm: vm)
    }

    /// The list and its loading flag live in the view model, which outlives
    /// this page — see `UninstallerViewModel.apps`.
    private var apps: [InstalledApp] { uvm.apps }
    private var loading: Bool { uvm.loadingApps }
    private var step: UninstallStep { uvm.step }
    private var groups: [UninstallGroup] { uvm.groups }
    private var checked: Set<String> { uvm.checked }
    private var failures: [TrashFailureInfo] { uvm.failures }

    /// Sorted first, narrowed after: the search never reorders. The order itself
    /// is `AppSort`'s, on the view model — nothing here decides it.
    private var filtered: [InstalledApp] {
        let ordered = uvm.sortedApps
        guard !search.isEmpty else { return ordered }
        return ordered.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var runningNames: [String] {
        if case .needsQuit(let names) = UninstallPlan.readiness(groups, forceQuit: false) { return names }
        return []
    }

    var body: some View {
        pageBody
            // The band stands on a stack of bands — the search row, the
            // permission note, a step's own chrome — and never on a scroll
            // view, so it is lit from the first frame. The Objects tab is the
            // one place that over-reports, knowingly:
            // `HelmPageHeader.standsOnStillContent` says why it is kept.
            .helmPageStandsOnStillContent()
            .helmTracksFullDiskAccess($diskAccess)
            .task {
                await uvm.refreshTrashWatch()
                await uvm.refreshSortOrder()
                await uvm.loadAppsIfNeeded()
            }
    }

    /// **The page's switcher and Refresh, in the window's own `NSToolbar`**
    /// (`SettingsToolbar`), through the contract every module page shares
    /// (`HelmWindowToolbar.swift` in `HelmUI`) — the switcher as Helm's own
    /// capsule centred over this page, Refresh in the toolbar's one action
    /// capsule at the trailing edge.
    ///
    /// They were one row of the page with the search field between them, and
    /// before that a SwiftUI `ToolbarContent` bridged into the window's own
    /// bar (`pageToolbar`, retired 2026-09-24 along with `.helmSearchable`
    /// once this page moved onto the app-owned bar the way Homebrew already
    /// had). The switcher still carries no width of its own — it sizes itself
    /// from what it shows — and Refresh is still only on the Apps tab: Orphans
    /// has its own scan and its own Rescan button, so a Refresh here spun an
    /// icon and changed nothing the user could see.
    ///
    /// **Dims rather than disables per tab.** `tabsEnabled: step != .review`
    /// dims the whole switcher, its folded menu and its overflow menu while a
    /// removal is being reviewed, when switching tabs would abandon it —
    /// per-tab disabling was never asked for, and `HelmPageToolbarContent`
    /// has no way to disable one tab and not the other.
    private var toolbarContent: HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: Tab.apps.rawValue, title: UnStr.tabApps, symbol: "square.grid.2x2"),
                HelmToolbarTab(id: Tab.orphans.rawValue, title: UnStr.tabOrphans,
                              symbol: "doc.badge.ellipsis"),
            ],
            selectedTab: Binding(get: { tab.rawValue }, set: { tab = Tab(rawValue: $0) ?? tab }),
            tabsEnabled: step != .review,
            actions: [
                // Nothing to order on the review or the failure report, and
                // nothing to order on the Leftovers tab. The choice is the
                // engine's to remember; a press answers at once.
                HelmToolbarAction(id: "sort", title: UnStr.sortBy, symbol: "arrow.up.arrow.down",
                                  isEnabled: step == .pick && failures.isEmpty,
                                  isVisible: tab == .apps,
                                  menu: AppSortOrder.allCases.map { order in
                    HelmToolbarMenuItem(id: order.rawValue, title: UnStr.sortName(order),
                                        isOn: uvm.effectiveSortOrder == order,
                                        isEnabled: order != .dateLastOpened || uvm.dateOrderAvailable) {
                        Task { await uvm.setSortOrder(order) }
                    }
                }),
                HelmToolbarAction(id: "refresh", title: UnStr.refreshList, symbol: "arrow.clockwise",
                                  isEnabled: !loading, isVisible: tab == .apps, isBusy: loading) {
                    Task { await refreshApps() }
                },
            ],
            // No `onSubmit`: the term filters the Apps list live, on every
            // keystroke, exactly as it did through `.helmSearchable` before.
            search: HelmToolbarSearch(prompt: UnStr.searchApps, text: $search))
    }

    private var pageBody: some View {
        // The module had no motion at all: three steps and two lists, and
        // moving between them — or losing the app you just removed — happened
        // in a single frame. One token on the three things that change, the
        // same one the other list screens use.
        VStack(spacing: 0) {
            // The switcher, Refresh and the search control are all the
            // window's own toolbar's (`toolbarContent`, `.helmWindowToolbar`
            // below) — nothing is drawn in the page for any of them.
            //
            // Page level: the user used to tick apps, sit through a scan and
            // only then learn the removal would be refused.
            if let note = permissionNote {
                HelmPermissionNote(need: .fullDiskAccess, text: note)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }

            if tab == .apps {
                if !failures.isEmpty {
                    failureReport
                } else {
                    switch step {
                    case .pick: pickStep
                    case .review: reviewStep
                    }
                }
            } else {
                OrphansView(uvm: uvm)
            }
        }
        // **Declared unconditionally, on every tab and every step, and not
        // only under `tab == .apps && step == .pick`.** This field lives in
        // the window's own `NSToolbar` now, and that toolbar lays its items
        // out itself: adding or dropping one shifts every other item sharing
        // it, Refresh included. Measured on a real screen recording
        // (2026-09-21, `un-leave`, against the earlier SwiftUI-bridged bar):
        // Refresh's glyph moved 175 pt inside a single frame — 41.7-50 ms at
        // this clip's dropped-frame rate — right when this condition flipped
        // leaving Приложения, while the very same tab change then sat
        // under a page-wide `.animation(value: tab)` (removed since: it
        // cross-faded the two tabs) and still snapped, because that transaction is SwiftUI's and the
        // toolbar's own relayout is AppKit's, which no curve in this file
        // reaches (ARCHITECTURE.md § The bar's zones: the tabs
        // and the actions both live in `NSToolbar`'s own layout, not
        // SwiftUI's, for the identical reason). Keeping the
        // field declared keeps the toolbar's item count constant, which is
        // the only thing that keeps its relayout from running at all —
        // `filtered` still only narrows the Apps tab's list at `step ==
        // .pick`, exactly as it did before.
        .helmWindowToolbar(toolbarContent, token: UninstallerDescriptor.id.rawValue)
        .animation(HelmMotion.interface, value: step)
    }

    /// The one note about the one permission, or nil when there is nothing to say.
    ///
    /// **Two readings stand behind it, and only one of them is a probe.**
    /// `diskAccess` is `PermissionCheck`'s answer, taken on every appearance; the
    /// other is a `contentsOfDirectory` on the Trash that the engine really
    /// attempted and was refused (`TrashWatch.cannotReadTrash`). A refused read is
    /// the stronger evidence of the two — reading `~/.Trash` is exactly what this
    /// grant covers — so the note stands over it as well, and the switch on the
    /// Leftovers tab stops being a control that says on with nothing behind it.
    ///
    /// One note for one permission. There used to be a second under the Trash
    /// switch with its own Grant button — same grant, same pane, two rows a person
    /// has to work out are the same thing. What the switch adds is a consequence,
    /// not a notice, so it lands in this sentence instead.
    ///
    /// Internal rather than private, for the reason `statusLine` gives: which of
    /// these two sentences stands over which state is the whole of a fix, and a
    /// `body` is not somewhere a test can reach.
    var permissionNote: String? {
        guard diskAccess == .denied || uvm.trashWatch == .cannotReadTrash else { return nil }
        return uvm.trashWatch.isOn ? UnStr.accessNeededWithWatch : UnStr.removalNeedsAccess
    }

    /// Counts read as a quiet status line instead of a panel of dials — or
    /// nothing at all, when the body above has already said why there is no
    /// count.
    ///
    /// The count comes from the model — `loading ? nil : apps.count` here said «0
    /// apps» about a list the engine never answered, which is a sentence about
    /// somebody's Mac that Helm did not check.
    ///
    /// **And then it said «Counting apps…» about it, under a body reporting a
    /// failure.** `UnStr.appsCount`'s optional folds two unknowns into one
    /// sentence: a reply on its way and a reply that never came. So the count
    /// is derived from `appsEmpty` — the value the body itself draws — and not
    /// from a second reading of the same flags; `AppsEmpty.Status` is where
    /// that is decided and tested, and the switch here is exhaustive so a
    /// fourth answer cannot arrive as a `default`.
    ///
    /// Internal rather than private: which of `UnStr.appsCount`'s two sentences
    /// stands over a list the engine never answered is the whole of that fix, and a
    /// `body` is not somewhere a test can reach.
    var statusLine: String? {
        let count: Int?
        switch AppsEmpty.status(appsEmpty, loading: loading, apps: apps.count) {
        case .silent: return nil
        case .counting: count = nil
        case .counted(let known): count = known
        }
        guard !checked.isEmpty else { return UnStr.appsCount(count) }
        return UnStr.appsCountSelected(count, checked.count, sizeText)
    }

    private func refreshApps() async { await uvm.reloadApps() }

    private var sizeText: String {
        let bytes: Int
        if step == .review {
            bytes = uvm.reviewBytes ?? 0
        } else {
            bytes = apps.filter { checked.contains($0.bundleID) }.reduce(0) { $0 + $1.sizeBytes }
        }
        guard bytes > 0 else { return "—" }
        return Bytes(bytes)
    }

    // MARK: - Step 1: pick apps

    /// Why the list has no rows — and nil when it has some, which is what the
    /// body branches on.
    ///
    /// **Not `filtered.isEmpty`.** The three ways this tab comes up empty want
    /// three different sentences, and it drew the same empty inset `List` for all
    /// of them: `AppsEmpty` holds the rule and says why there are three. The
    /// «answered» half is the view model's own flag, the one the footer's count
    /// reads, so the body cannot contradict the line under it.
    ///
    /// Internal rather than private, for the reason `statusLine` gives: which of
    /// these three sentences stands over which state is the whole of the fix, and
    /// a `body` is not somewhere a test can reach.
    var appsEmpty: AppsEmpty.Reason? {
        AppsEmpty.reason(answered: uvm.listAnswered, apps: apps.count, shown: filtered.count)
    }

    private var pickStep: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if let nothing = appsEmpty {
                emptyState(nothing)
            } else {
                List {
                    ForEach(filtered) { app in
                        appRow(app)
                            .listRowSeparator(.hidden)
                    }
                }
                .helmStripedList(rowPitch: HelmSpace.s8)
            }
            Divider()
            // The same line the review step draws, and for the same reason: it was
            // a `lineLimit(1)` passenger in the row below, between a status line
            // and two buttons. Measured at 845 pt against 646, which is the detail
            // pane at `contentMinSize`: English unchanged, German −30 %, Russian
            // −39 %, and the row did not grow — so what a partly-failed removal
            // lost was the tail of its own sentence, the half saying how many items
            // stayed behind.
            report
            HStack(spacing: HelmSpace.s5) {
                Button(UnStr.selectNone) { uvm.clearChecked() }
                    .disabled(checked.isEmpty)
                // Nothing at all when there is nothing to count: the body above
                // has said why, and a second sentence down here can only agree
                // with it or contradict it.
                if let statusLine {
                    Text(statusLine)
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
                Spacer()
                Button {
                    Task { await uvm.prepareReview() }
                } label: {
                    if uvm.scanning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(UnStr.scanning)
                        }
                    } else {
                        Text(UnStr.reviewCount(checked.count))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(checked.isEmpty || uvm.scanning)
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        }
    }

    /// The sentence over an empty list, and a verb only where there is one to
    /// give.
    ///
    /// The split is `AppsEmpty.invites`, which is also the split
    /// `HelmEmptyState`'s two initialisers draw along: a list nobody answered is
    /// a dead end and gets the plate and the button, while «no applications» and
    /// «nothing matches this search» are statements — one asking to repeat a
    /// question just answered, the other to reload the Mac when the search field
    /// that hid the rows is a few points above the message.
    @ViewBuilder private func emptyState(_ nothing: AppsEmpty.Reason) -> some View {
        if AppsEmpty.invites(nothing) {
            // The toolbar's own icon for the toolbar's own act: the button and
            // the round arrow above it ask for the same thing.
            HelmEmptyState(symbol: "arrow.clockwise", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.emptyMessage(nothing)) {
                Button(UnStr.refreshList) { Task { await refreshApps() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)
            }
        } else {
            HelmEmptyState(message: UnStr.emptyMessage(nothing))
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        // The checkbox is its own control centred against the row, so it lines
        // up with the icon and the name instead of hanging above them.
        let system = SystemApp.isSystem(bundleID: app.bundleID)
        return HStack(spacing: HelmSpace.s5) {
            if system {
                // Marked the way Disk marks a row it cannot remove: no
                // checkbox, and a word saying why. Safari sat here tickable at
                // 0 bytes, and macOS refuses it — after the scan and the click.
                // The space keeps the icons in one column.
                HelmCheckboxSlot()
            } else {
                // Named, though the label stays hidden: `.labelsHidden()` hides a
                // label visually and keeps it for VoiceOver, but an empty string
                // leaves nothing to keep — a list of 250 rows read as "checkbox,
                // unchecked" 250 times.
                Toggle(app.name, isOn: Binding(
                    get: { uvm.isChecked(app.bundleID) },
                    set: { on in uvm.setChecked(app.bundleID, on) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            Image(nsImage: AppInfo.icon(forFile: app.path))
                .resizable().frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                // **Two lines in every row, whatever the row is.** The System
                // mark used to be a third line, so the rows that had it stood
                // taller than the rows that did not and the list went down the
                // page in steps. It is a pill beside the name now — the house's
                // one pill — which is where the eye is already looking for what
                // a row *is*, and it costs the row no height at all.
                HStack(spacing: 6) {
                    Text(app.name).lineLimit(1)
                    if system { HelmBadge(UnStr.systemApp) }
                }
                Text(app.path)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet).lineLimit(1)
                    .truncationMode(.middle)
            }
            // A name, a path and the System caption are one thing to read, in
            // the order they are drawn — three stops per row down a list that
            // holds hundreds, and the name arrived without the caption that
            // qualifies it. The checkbox stays its own, being a thing to
            // operate rather than to read.
            .accessibilityElement(children: .combine)
            Spacer()
            VStack(alignment: .trailing, spacing: HelmSpace.s1) {
                // Nothing until measured: `sizeBytes` is zero in a list that has
                // not been measured, and «0 bytes» is a claim nobody made. A bundle
                // measured as nothing reads as the dash the total already uses.
                // The place is kept either way — the sizes land seconds after the
                // list, and a line that appeared above the date slid every date on
                // screen down half a line at once. Hidden, so it draws and reads
                // as nothing while it holds the line.
                if let size = uvm.measuredSizes[app.path] {
                    Text(size > 0 ? Bytes(size) : "—")
                        .helmFigure().foregroundStyle(HelmText.quiet)
                } else {
                    Text(verbatim: "—").helmFigure().hidden()
                }
                openedLine(app)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { uvm.toggleChecked(app.bundleID) }
    }

    /// When the app was last opened, on every row in every order — the fact the
    /// date order sorts by, so it can be checked by eye. Blank while Spotlight
    /// is being asked and for an app the read did not reach, «no record» for one
    /// Spotlight has no date for, and absent altogether when Spotlight answered
    /// for no app at all: every row would say «no record».
    ///
    /// Written out in full — «hace 7 meses», «il y a 2 ans» — because the short
    /// form of es and fr is one letter for a month and for a year («7 m», «2 a»),
    /// unreadable in exactly the spans this line exists to show.
    ///
    /// Blank is a held place, not a missing line: the line's height stays, so the
    /// size above it does not move when the date arrives.
    @ViewBuilder private func openedLine(_ app: InstalledApp) -> some View {
        if let line = openedText(app) {
            Text(line).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
        } else {
            Text(verbatim: "—").font(HelmText.rowDetail).hidden()
        }
    }

    private func openedText(_ app: InstalledApp) -> String? {
        guard uvm.dateOrderAvailable, !uvm.lastOpenedUnread.contains(app.path) else { return nil }
        guard let date = uvm.lastOpened?[app.path] else { return UnStr.noRecordOfOpening }
        return HelmDates.age(date, style: .full).map(UnStr.opened)
    }

    // MARK: - Step 2: review the files, grouped per app

    private var reviewStep: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups, id: \.id) { group in
                    Section {
                        // `reviewRows` puts the bundle first, and it is the one
                        // path every removal takes — see `UninstallPlan.paths`.
                        ForEach(UninstallPlan.reviewRows(group)) { row in
                            switch row {
                            case .bundle(let app): bundleRow(app)
                            case .leftover(let leftover): leftoverRow(leftover)
                            }
                        }
                        .listRowSeparator(.hidden)
                        if group.leftovers.isEmpty {
                            Text(UnStr.noLeftoversForApp)
                                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .helmStripedList(rowPitch: HelmSpace.s8)

            Divider()

            if !runningNames.isEmpty {
                HStack(alignment: .top, spacing: HelmSpace.s5) {
                    // The sentence beside it already says an app is still
                    // running; read aloud, the triangle adds "warning" and no
                    // information.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UnStr.runningWarning(runningNames.joined(separator: ", ")))
                            .font(HelmText.rowTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(UnStr.forceQuitAndRemove, isOn: $uvm.forceQuit)
                            .font(HelmText.rowTitle)
                    }
                    Spacer()
                }
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
            }

            report

            HStack(spacing: HelmSpace.s5) {
                Button(UnStr.back) { uvm.backToPick() }
                Spacer()
                // A total that is not known is not drawn: the sizes are still
                // being measured, or a bundle measured as nothing promises none.
                if let bytes = uvm.reviewBytes, bytes > 0 {
                    Text(UnStr.toTrash(Bytes(bytes))).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
                let ready = UninstallPlan.readiness(groups, forceQuit: uvm.forceQuit) == .ready
                Button {
                    Task { await uvm.removeSelection() }
                } label: {
                    if uvm.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(UnStr.removing)
                        }
                    } else {
                        Text(UnStr.moveToTrash)
                    }
                }
                .buttonStyle(.borderedProminent)
                // **Not `!ready`.** That reads `group.running`, which is what the
                // scan saw when the review was built: an app the person has quit
                // since then left this button dead for good, and the only way out
                // was Back → Review, which pays for a fresh scan of every ticked
                // app. The live question is asked in the engine at the moment of
                // removal now, and a batch it refuses says so above this row. The
                // `.help` stays — it is the one part that says *why*, and it is
                // advice rather than a claim about the button.
                .disabled(uvm.busy)
                .help(ready ? "" : UnStr.blockedByRunning)
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        }
    }

    /// What the last press said, drawn on the screen the person is still on.
    ///
    /// A full-width line of its own rather than a `lineLimit(1)` passenger in the
    /// bar below: every sentence that can stand here is two clauses long, and the
    /// clause that says what happened to the rest is the one that gets truncated.
    ///
    /// **One line for both steps.** It was written for the review step and the
    /// picker kept a truncating copy of its own — two spellings of one act, and the
    /// measured defect was in the copy. Whichever step is up, the last press reads
    /// the same way.
    @ViewBuilder private var report: some View {
        if uvm.replyLost || uvm.resultBanner != nil {
            Group {
                // Ahead of the banner, which is nil in this state: a reply that
                // never came says so rather than nothing. Drawn exactly as a
                // success is — no triangle, no list, no Grant button — because
                // nothing was refused and nothing here is anybody's to fix.
                if uvm.replyLost {
                    HelmRemovalOutcome.unanswered
                } else if let banner = uvm.resultBanner {
                    Text(banner)
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.top, HelmSpace.s5)
        }
    }

    /// The app itself, first in its group and with no checkbox: `paths` always
    /// takes it, so a box to untick would be an offer the plan does not honour.
    private func bundleRow(_ app: InstalledApp) -> some View {
        HStack(spacing: HelmSpace.s5) {
            // Where the leftover rows put their checkbox, so the paths line up.
            HelmCheckboxSlot()
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(app.path)
                    .lineLimit(1).truncationMode(.middle)
                Text(UnStr.theAppItself)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            sizeFigure(of: app)
        }
    }

    /// What stayed behind, why, and what to do about it.
    private var failureReport: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(failures, id: \.path) { failure in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                                HStack(spacing: 8) {
                                    // The line under it names the reason in
                                    // words; the triangle only repeats it.
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(HelmSignal.warning)
                                        .accessibilityHidden(true)
                                    Text((failure.path as NSString).lastPathComponent)
                                        .lineLimit(1)
                                }
                                Text(failure.path)
                                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(UnStr.failureReason(failure.reason))
                                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning)
                                if !failure.message.isEmpty {
                                    // macOS's own words: the classification is a
                                    // summary, this is the evidence behind it.
                                    Text(failure.message)
                                        .font(.caption2).foregroundStyle(HelmText.faint)
                                        .lineLimit(2)
                                }
                            }
                            // Name, path, reason and what macOS said are one
                            // report; the button that acts on it stays its own.
                            .accessibilityElement(children: .combine)
                            Spacer()
                            Button(HelmA11y.showInFinder) { HelmReveal.inFinder(failure.path) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, HelmSpace.s1)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(UnStr.couldNotRemove(failures.count))
                }
            }
            .helmStripedList(rowPitch: HelmSpace.s8)

            Divider()
            HStack(spacing: HelmSpace.s5) {
                if failures.contains(where: { $0.reason == .needsFullDiskAccess }) {
                    Button(UnStr.openDiskAccess) { PermissionCheck.openFullDiskAccessSettings() }
                }
                if failures.contains(where: { $0.reason == .activeSystemExtension }) {
                    Button(UnStr.openExtensions) { PermissionCheck.openExtensionSettings() }
                }
                Spacer()
                Button(UnStr.done) { uvm.dismissFailures() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        }
    }

    /// The size of an app in the review, read from the measurement as it stands
    /// and not from the snapshot the review was built from: that carries the
    /// list's zero for as long as the sizes have not landed, and «0 bytes» is a
    /// claim nobody made. Nothing is drawn until it is measured, and it appears
    /// when it lands.
    @ViewBuilder private func sizeFigure(of app: InstalledApp) -> some View {
        if let size = uvm.measuredSizes[app.path] {
            Text(size > 0 ? Bytes(size) : "—")
                .helmFigure().foregroundStyle(HelmText.quiet)
        }
    }

    private func groupHeader(_ group: UninstallGroup) -> some View {
        HStack(spacing: 8) {
            // The icon reads as an unticked checkbox beside a column of them,
            // and says nothing a screen reader needs — the name follows it.
            Image(nsImage: AppInfo.icon(forFile: group.app.path))
                .resizable().frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(group.app.name).font(HelmText.sectionHeading)
            if group.running {
                HelmBadge(UnStr.runningBadge, tint: .orange)
            }
            Spacer()
            sizeFigure(of: group.app)
        }
        // A name, a "Running" badge and a size: one heading, read in order.
        .accessibilityElement(children: .combine)
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: HelmSpace.s5) {
            Toggle((leftover.path as NSString).lastPathComponent, isOn: Binding(
                get: { uvm.isSelected(leftover: leftover.path) },
                set: { on in uvm.setSelected(leftover: leftover.path, on) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: 6) {
                    Text((leftover.path as NSString).lastPathComponent).lineLimit(1)
                    // Says why the box is empty: this one was found by the app's
                    // name, and names collide.
                    if leftover.matchedByName {
                        HelmBadge(UnStr.matchedByName)
                    }
                }
                Text(leftover.path)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .lineLimit(1).truncationMode(.middle)
            }
            // The name, the badge that qualifies it and the path are one thing
            // to read; the checkbox stays its own stop.
            .accessibilityElement(children: .combine)
            Spacer()
            Text(Bytes(leftover.sizeBytes))
                .helmFigure().foregroundStyle(HelmText.quiet)
        }
    }

}
