import AppKit
import SwiftUI
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// The copy on disk, not the bundle id, as in `UninstallGroup.id`: two copies
/// of one app share an id, and a `ForEach` given one identity for two rows has
/// undefined results.
extension InstalledApp: Identifiable { public var id: String { path } }

/// Two steps, AppCleaner-style: tick the apps to remove, then review the files
/// found for each of them before anything goes to the Trash. A running app is
/// never removed silently — it is quit first, and only if the user says so.
struct UninstallerSettingsPage: View {
    @ObservedObject private var uvm: UninstallerViewModel

    /// Only what is cheap to lose lives here: the permission is re-probed on every
    /// appearance, and a search term costs a second. The rest is on the view model
    /// (`UninstallerViewModel.step`).
    @State private var diskAccess: PermissionState = .granted
    @State private var search = ""

    /// Installed apps, or leftovers from apps already gone. A string-backed id,
    /// as `HelmHeaderTab.id` wants: an index would mis-read if the tabs reordered.
    private enum Tab: String { case apps, orphans }
    @State private var tab: Tab = .apps

    init(uvm: UninstallerViewModel) {
        self.uvm = uvm
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
            // Declared for every tab and step, so the band is lit from the first
            // frame. `HelmPageHeader.standsOnStillContent` says why it is kept.
            .helmPageStandsOnStillContent()
            .helmTracksFullDiskAccess($diskAccess)
            .task {
                await uvm.refreshTrashWatch()
                await uvm.refreshSortOrder()
                await uvm.loadAppsIfNeeded()
            }
    }

    /// The page's switcher and Refresh, in the header row of the window's card
    /// (`HelmHeaderContent.swift` in `HelmUI`).
    ///
    /// Refresh is only on the Apps tab: Leftovers has its own scan button.
    /// `tabsEnabled: step != .review` dims the whole strip while a removal is
    /// reviewed, since switching tabs would abandon it; `HelmHeaderContent` cannot
    /// disable one tab alone.
    private var headerContent: HelmHeaderContent {
        HelmHeaderContent(
            tabs: [
                HelmHeaderTab(id: Tab.apps.rawValue, title: HelmWord.apps, symbol: "square.grid.2x2"),
                HelmHeaderTab(id: Tab.orphans.rawValue, title: HelmWord.leftovers, symbol: "doc.badge.ellipsis"),
            ],
            selectedTab: Binding(get: { tab.rawValue }, set: { tab = Tab(rawValue: $0) ?? tab }),
            tabsEnabled: step != .review,
            actions: [
                // Nothing to order on the review, the failure report or the
                // Leftovers tab. The engine remembers the choice.
                HelmHeaderAction(id: "sort", title: UnStr.sortBy, symbol: "arrow.up.arrow.down",
                                  isEnabled: step == .pick && failures.isEmpty,
                                  isVisible: tab == .apps,
                                  menu: AppSortOrder.allCases.map { order in
                    HelmHeaderMenuItem(id: order.rawValue, title: UnStr.sortName(order),
                                        isOn: uvm.effectiveSortOrder == order,
                                        isEnabled: order != .dateLastOpened || uvm.dateOrderAvailable) {
                        Task { await uvm.setSortOrder(order) }
                    }
                }),
                HelmHeaderAction(id: "refresh", title: HelmWord.refreshList, symbol: "arrow.clockwise",
                                  isEnabled: !loading, isVisible: tab == .apps, isBusy: loading) {
                    Task { await uvm.reloadApps() }
                },
            ],
            // No `onSubmit`: the term filters the Apps list live, on every keystroke.
            search: HelmHeaderQuery(prompt: HelmControlName.searchApps, text: $search))
    }

    private var pageBody: some View {
        // One token, `HelmMotion.interface`, on the step: the list and the review are the one change that moves.
        VStack(spacing: 0) {
            // The switcher, Refresh and the search are the window's header's
            // (`headerContent`, `.helmHeaderContent` below).
            //
            // Page level, so the person learns of a missing grant before ticking
            // apps and sitting through a scan.
            if let note = permissionNote {
                HelmPermissionNote(need: .fullDiskAccess, text: note)
                    .helmPageStrip()
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
        // Declared on every tab and step: dropping the field would shift every other
        // item in the bar (`HelmHeaderActions` keeps each declared width). `filtered`
        // still narrows only the Apps list at `step == .pick`.
        .helmHeaderContent(headerContent)
        .animation(HelmMotion.interface, value: step)
    }

    /// The one note about the one permission, or nil when there is nothing to say.
    ///
    /// Two readings stand behind it: `diskAccess`, `PermissionCheck`'s probe on
    /// every appearance, and a Trash read the engine attempted and was refused
    /// (`TrashWatch.cannotReadTrash`), the stronger evidence, since `~/.Trash` is
    /// what this grant covers.
    ///
    /// One note for one permission: what the Trash switch loses is a consequence,
    /// said in this sentence, not a second note with its own Grant button.
    private var permissionNote: String? {
        guard diskAccess == .denied || uvm.trashWatch == .cannotReadTrash else { return nil }
        return uvm.trashWatch.isOn ? UnStr.accessNeededWithWatch : UnStr.removalNeedsAccess
    }

    /// Counts as a quiet status line, or nothing when the body has already said
    /// why there is no count.
    ///
    /// `AppsEmpty.Status` decides it, so a list nobody asked for yet is not «0
    /// apps»; the switch is exhaustive so a third answer cannot arrive as a
    /// `default`.
    private var statusLine: String {
        let count: Int?
        switch AppsEmpty.status(answered: uvm.listAnswered, loading: loading, apps: apps.count) {
        case .counting: count = nil
        case .counted(let known): count = known
        }
        guard !checked.isEmpty else { return UnStr.appsCount(count) }
        return UnStr.appsCountSelected(count, checked.count, sizeText)
    }

    private var sizeText: String {
        let bytes: Int
        if step == .review {
            bytes = uvm.reviewBytes ?? 0
        } else {
            bytes = apps.filter { checked.contains($0.path) }.reduce(0) { $0 + (uvm.measuredSizes[$1.path] ?? 0) }
        }
        guard bytes > 0 else { return "—" }
        return Bytes(bytes)
    }

    // MARK: - Step 1: pick apps

    /// Why the list has no rows — and nil when it has some, which is what the
    /// body branches on.
    ///
    /// Not `filtered.isEmpty`: the two ways this tab comes up empty want two
    /// sentences (`AppsEmpty`). «Answered» is the flag the footer's count reads
    /// too, so the body cannot contradict the line under it.
    private func appsEmpty(shown: Int) -> AppsEmpty.Reason? {
        AppsEmpty.reason(answered: uvm.listAnswered, apps: apps.count, shown: shown)
    }

    @ViewBuilder private var pickStep: some View {
        let shown = filtered
        VStack(spacing: 0) {
            if loading || !uvm.listAnswered {
                HelmBusyState()
            } else if let nothing = appsEmpty(shown: shown.count) {
                // A statement and no verb: a Refresh would repeat a question just
                // answered, and the search field that hid the rows is right above.
                HelmEmptyState(message: UnStr.emptyMessage(nothing))
            } else {
                List {
                    ForEach(shown) { app in
                        appRow(app)
                            .listRowSeparator(.hidden)
                    }
                }
                .helmStripedList(rowPitch: HelmSpace.s8)
            }
            Divider()
            // The same line the review step draws (`resultLine`), full width so
            // the clause saying how many items stayed behind is not truncated.
            report
            HStack(spacing: HelmSpace.s5) {
                Button(HelmWord.clearSelection) { uvm.clearChecked() }
                    .disabled(checked.isEmpty)
                Text(statusLine)
                    .helmQuietDetail()
                Spacer()
                Button {
                    Task { await uvm.prepareReview() }
                } label: {
                    HelmBusyLabel(uvm.scanning ? HelmWord.scanning : UnStr.reviewCount(checked.count),
                                  busy: uvm.scanning)
                }
                .buttonStyle(.borderedProminent)
                .disabled(checked.isEmpty || uvm.scanning)
            }
            .helmPageStrip()
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        // The checkbox is its own control centred against the row, so it lines
        // up with the icon and the name instead of hanging above them.
        let system = SystemApp.isSystem(bundleID: app.bundleID)
        return HStack(spacing: HelmSpace.s5) {
            if system {
                // Marked the way Disk marks a row it cannot remove: no
                // checkbox, and a word saying why. The space keeps the icons
                // in one column.
                HelmCheckboxSlot()
            } else {
                // Named, though the label stays hidden: `.labelsHidden()` keeps a
                // label for VoiceOver, and an empty one reads as "checkbox" alone.
                Toggle(app.name, isOn: Binding(
                    get: { uvm.isChecked(app) },
                    set: { on in uvm.setChecked(app, on) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            Image(nsImage: AppInfo.icon(forFile: app.path))
                .resizable().frame(width: UninstallerLayout.appIcon, height: UninstallerLayout.appIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                // Two lines in every row, whatever the row is: the System mark is
                // a pill beside the name, so it costs no height and the list does
                // not go down the page in steps.
                HStack(spacing: HelmSpace.s3) {
                    Text(app.name).lineLimit(1)
                    if system { HelmBadge(UnStr.systemApp) }
                }
                Text(app.path)
                    .helmQuietDetail().lineLimit(1)
                    .truncationMode(.middle)
            }
            // A name, a path and the System caption are one thing to read, in
            // the order drawn. The checkbox stays its own: it is operated, not read.
            .accessibilityElement(children: .combine)
            Spacer()
            VStack(alignment: .trailing, spacing: HelmSpace.s1) {
                // Nothing until measured: «0 bytes» is a claim nobody made. A
                // bundle measured as nothing reads as the total's dash. The place
                // is held, hidden, so the date below does not slide when the size lands.
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
        .onTapGesture { uvm.toggleChecked(app) }
    }

    /// When the app was last opened, on every row in every order, so the date
    /// order can be checked by eye. Blank while Spotlight is asked and for an app
    /// the read did not reach, «no record» for one with no date, and absent when
    /// Spotlight answered for no app at all.
    ///
    /// Written out in full («hace 7 meses»): the short form in es and fr is one
    /// letter for both month and year.
    ///
    /// Blank is a held place, so the size above does not move when the date arrives.
    @ViewBuilder private func openedLine(_ app: InstalledApp) -> some View {
        if let line = openedText(app) {
            Text(line).helmQuietDetail()
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
                                .helmQuietDetail()
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
                    VStack(alignment: .leading, spacing: HelmSpace.s2) {
                        Text(UnStr.runningWarning(runningNames.joined(separator: ", ")))
                            .font(HelmText.rowTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(UnStr.forceQuitAndRemove, isOn: $uvm.forceQuit)
                            .font(HelmText.rowTitle)
                    }
                    Spacer()
                }
                .helmPageStrip()
            }

            report

            HStack(spacing: HelmSpace.s5) {
                Button(HelmWord.back) { uvm.backToPick() }
                Spacer()
                // A total that is not known is not drawn: the sizes are still
                // being measured, or a bundle measured as nothing promises none.
                if let bytes = uvm.reviewBytes, bytes > 0 {
                    Text(UnStr.toTrash(Bytes(bytes))).helmQuietDetail()
                }
                let ready = UninstallPlan.readiness(groups, forceQuit: uvm.forceQuit) == .ready
                Button {
                    Task { await uvm.removeSelection() }
                } label: {
                    HelmBusyLabel(uvm.busy ? UnStr.removing : HelmWord.moveToTrash, busy: uvm.busy)
                }
                .buttonStyle(.borderedProminent)
                // Not `!ready`: that reads `group.running`, stale since the scan,
                // and would leave the button dead after the app was quit. The
                // engine asks at removal, and a refused batch says so above this
                // row. The `.help` is advice, not a claim about the button.
                .disabled(uvm.busy)
                .help(ready ? "" : UnStr.blockedByRunning)
            }
            .helmPageStrip()
        }
    }

    /// What the last press said, drawn on the screen the person is still on.
    ///
    /// A full-width line of its own: every sentence here is two clauses, and in a
    /// one-line slot the clause about the rest is the one truncated.
    ///
    /// One line for both steps, so the last press reads the same way on either.
    @ViewBuilder private var report: some View {
        if let banner = uvm.resultBanner {
            HelmSettingsNote(banner)
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
                    .helmQuietDetail()
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
                        HStack(alignment: .top, spacing: HelmSpace.s4) {
                            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                                HStack(spacing: HelmSpace.s4) {
                                    // The line under it names the reason in
                                    // words; the triangle only repeats it.
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(HelmSignal.warning)
                                        .accessibilityHidden(true)
                                    Text((failure.path as NSString).lastPathComponent)
                                        .lineLimit(1)
                                }
                                Text(failure.path)
                                    .helmQuietDetail()
                                    .lineLimit(1).truncationMode(.middle)
                                Text(UnStr.failureReason(failure.reason))
                                    .font(HelmText.rowDetail).foregroundStyle(HelmSignal.warning)
                                if !failure.message.isEmpty {
                                    // macOS's own words: the classification is a
                                    // summary, this is the evidence behind it.
                                    Text(failure.message)
                                        .font(HelmText.smallPrint).foregroundStyle(HelmText.faint)
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
                    Button(HelmWord.openFullDiskAccess) { PermissionCheck.openFullDiskAccessSettings() }
                }
                if failures.contains(where: { $0.reason == .activeSystemExtension }) {
                    // The kit's word: Leftovers' extension row draws the same label over the same call.
                    Button(HelmControlName.openExtensions) { PermissionCheck.openExtensionSettings() }
                }
                Spacer()
                Button(HelmWord.done) { uvm.dismissFailures() }
                    .buttonStyle(.borderedProminent)
            }
            .helmPageStrip()
        }
    }

    /// The size of an app in the review, from the measurement as it stands, not
    /// the review's snapshot. Nothing is drawn until it is measured: «0 bytes» is
    /// a claim nobody made.
    @ViewBuilder private func sizeFigure(of app: InstalledApp) -> some View {
        if let size = uvm.measuredSizes[app.path] {
            Text(size > 0 ? Bytes(size) : "—")
                .helmFigure().foregroundStyle(HelmText.quiet)
        }
    }

    private func groupHeader(_ group: UninstallGroup) -> some View {
        HStack(spacing: HelmSpace.s4) {
            // The icon reads as an unticked checkbox beside a column of them,
            // and says nothing a screen reader needs — the name follows it.
            Image(nsImage: AppInfo.icon(forFile: group.app.path))
                .resizable().frame(width: UninstallerLayout.groupIcon, height: UninstallerLayout.groupIcon)
                .accessibilityHidden(true)
            Text(group.app.name).font(HelmText.sectionHeading)
            if group.running {
                HelmBadge(UnStr.runningBadge, tint: HelmSignal.warning)
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
                HStack(spacing: HelmSpace.s3) {
                    Text((leftover.path as NSString).lastPathComponent).lineLimit(1)
                    // Says why the box is empty: this one was found by the app's
                    // name, and names collide.
                    if leftover.matchedByName {
                        HelmBadge(UnStr.matchedByName)
                    }
                }
                Text(leftover.path)
                    .helmQuietDetail()
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
