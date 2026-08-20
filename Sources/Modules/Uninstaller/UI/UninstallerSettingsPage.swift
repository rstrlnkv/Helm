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

    /// 0 = installed apps, 1 = leftovers from apps that are already gone.
    @State private var tab = 0

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

    private var filtered: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var runningNames: [String] {
        if case .needsQuit(let names) = UninstallPlan.readiness(groups, forceQuit: false) { return names }
        return []
    }

    var body: some View {
        pageBody
            .helmTracksFullDiskAccess($diskAccess)
            .task {
                await uvm.refreshTrashWatch()
                await uvm.loadAppsIfNeeded()
            }
    }

    private var pageBody: some View {
        // The module had no motion at all: three steps and two lists, and
        // moving between them — or losing the app you just removed — happened
        // in a single frame. One token on the three things that change, the
        // same one the other list screens use.
        VStack(spacing: 0) {
            // One toolbar row instead of a metric panel, a segmented row and a
            // search row stacked on top of each other.
            HStack(spacing: HelmSpace.s5) {
                Picker(HelmA11y.whatToShow, selection: $tab) {
                    Text(UnStr.tabApps).tag(0)
                    Text(UnStr.tabOrphans).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden()
                // No width, because a segmented control sizes itself from its own
                // labels and never stretches past that — so a fixed number is
                // slack in the languages below it and a squeeze in the ones
                // above. 200 was both: 39 pt of slack in English, where the
                // control drew itself at x=39.5, indented from the 20 pt every
                // row below it starts at, and 8 pt short in Russian, where AppKit
                // took the difference out of the segments' padding until
                // «Приложения» sat against the edge of its pill. A bigger number
                // would only move which language pays.
                .disabled(step == .review)

                if tab == 0 && step == .pick {
                    HelmSearchField(text: $search, placeholder: UnStr.searchApps)
                        .frame(height: 22)
                }
                Spacer(minLength: 0)
                // Only on the Apps tab: Orphans has its own scan and its own
                // Rescan button, so here this spun an icon and changed nothing
                // the user could see.
                if tab == 0 {
                Button {
                    Task { await refreshApps() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        // Was `.rotationEffect(.degrees(loading ? 360 : 0))`,
                        // which is geometrically a no-op — and nothing wrapped
                        // the mutation in an animation either, so the button
                        // sat perfectly still through every reload.
                        .helmSteadySpin(loading)
                }
                .buttonStyle(.borderless)
                .disabled(loading)
                .help(UnStr.refreshList)
                .accessibilityLabel(UnStr.refreshList)
                }
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)

            Divider()

            // Page level: the user used to tick apps, sit through a scan and
            // only then learn the removal would be refused.
            if let note = permissionNote {
                HelmPermissionNote(need: .fullDiskAccess, text: note)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }

            if tab == 0 {
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
        .animation(HelmMotion.interface, value: step)
        .animation(HelmMotion.interface, value: tab)
        .animation(HelmMotion.interface, value: apps.count)
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
            bytes = UninstallPlan.totalBytes(groups, selectedLeftovers: uvm.selectedLeftovers)
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
                    }
                }
                .listStyle(.inset)
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
            Text(Bytes(app.sizeBytes))
                .helmFigure().foregroundStyle(HelmText.quiet)
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .onTapGesture { uvm.toggleChecked(app.bundleID) }
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
                        if group.leftovers.isEmpty {
                            Text(UnStr.noLeftoversForApp)
                                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.inset)

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
                Text(UnStr.toTrash(sizeText)).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
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
            Text(Bytes(app.sizeBytes))
                .helmFigure().foregroundStyle(HelmText.quiet)
        }
        .frame(minHeight: 32)
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
                    }
                } header: {
                    Text(UnStr.couldNotRemove(failures.count))
                }
            }
            .listStyle(.inset)

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
            Text(Bytes(group.app.sizeBytes))
                .helmFigure().foregroundStyle(HelmText.quiet)
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
        .frame(minHeight: 32)
    }

}
