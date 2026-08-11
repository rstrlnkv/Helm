import AppKit
import SwiftUI
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

extension InstalledApp: Identifiable { public var id: String { bundleID } }

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
    /// Read from the engine so the page's one permission note can say what the
    /// missing grant actually costs *here* — the Trash switch being on makes it
    /// cost more than containers.
    @State private var watchingTrash = false

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
                watchingTrash = await uvm.watchingTrash()
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
            HStack(spacing: 10) {
                Picker(HelmA11y.whatToShow, selection: $tab) {
                    Text(UnStr.tabApps).tag(0)
                    Text(UnStr.tabOrphans).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 200)
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
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)

            Divider()

            // Page level: the user used to tick apps, sit through a scan and
            // only then learn the removal would be refused.
            // One note for one permission. There used to be a second under the
            // Trash switch with its own Grant button — same grant, same pane,
            // two rows a person has to work out are the same thing. What the
            // switch adds is a consequence, not a notice, so it lands in this
            // sentence instead.
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess,
                                   text: watchingTrash ? UnStr.accessNeededWithWatch
                                                       : UnStr.removalNeedsAccess)
                    .padding(.horizontal, 20).padding(.vertical, 10)
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

    /// Counts read as a quiet status line instead of a panel of dials.
    private var statusLine: String {
        let count: Int? = loading ? nil : apps.count
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

    private var pickStep: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { app in
                        appRow(app)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack(spacing: 10) {
                Button(UnStr.selectNone) { uvm.clearChecked() }
                    .disabled(checked.isEmpty)
                Text(statusLine)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                Spacer()
                if let banner = uvm.resultBanner {
                    Text(banner).font(.caption).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
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
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        // The checkbox is its own control centred against the row, so it lines
        // up with the icon and the name instead of hanging above them.
        let system = SystemApp.isSystem(bundleID: app.bundleID)
        return HStack(spacing: 10) {
            if system {
                // Marked the way Disk marks a row it cannot remove: no
                // checkbox, and a word saying why. Safari sat here tickable at
                // 0 bytes, and macOS refuses it — after the scan and the click.
                // The space keeps the icons in one column.
                Color.clear.frame(width: 16, height: 1)
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
            VStack(alignment: .leading, spacing: 1) {
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
                    .font(.caption).foregroundStyle(HelmText.quiet).lineLimit(1)
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
                                .font(.caption).foregroundStyle(HelmText.quiet)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            if !runningNames.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    // The sentence beside it already says an app is still
                    // running; read aloud, the triangle adds "warning" and no
                    // information.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UnStr.runningWarning(runningNames.joined(separator: ", ")))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(UnStr.forceQuitAndRemove, isOn: $uvm.forceQuit)
                            .font(.callout)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }

            HStack(spacing: 10) {
                Button(UnStr.back) { uvm.backToPick() }
                Spacer()
                Text(UnStr.toTrash(sizeText)).font(.caption).foregroundStyle(HelmText.quiet)
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
                // `.disabled` alone, like every other disabled button in the
                // app: a grey tint and an opacity stacked on top of it dimmed
                // the same button three times over, and the two extras only
                // said what the system already draws. The `.help` stays — it is
                // the one part that says *why*.
                .disabled(uvm.busy || !ready)
                .help(ready ? "" : UnStr.blockedByRunning)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    /// The app itself, first in its group and with no checkbox: `paths` always
    /// takes it, so a box to untick would be an offer the plan does not honour.
    private func bundleRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            // Where the leftover rows put their checkbox, so the paths line up.
            Color.clear.frame(width: 16, height: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.path)
                    .lineLimit(1).truncationMode(.middle)
                Text(UnStr.theAppItself)
                    .font(.caption).foregroundStyle(HelmText.quiet)
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
                            VStack(alignment: .leading, spacing: 3) {
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
                                    .font(.caption).foregroundStyle(HelmText.quiet)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(UnStr.failureReason(failure.reason))
                                    .font(.caption).foregroundStyle(HelmSignal.warning)
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
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text(UnStr.couldNotRemove(failures.count))
                }
            }
            .listStyle(.inset)

            Divider()
            HStack(spacing: 10) {
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
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func groupHeader(_ group: UninstallGroup) -> some View {
        HStack(spacing: 8) {
            // The icon reads as an unticked checkbox beside a column of them,
            // and says nothing a screen reader needs — the name follows it.
            Image(nsImage: AppInfo.icon(forFile: group.app.path))
                .resizable().frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(group.app.name).font(.callout.weight(.semibold))
            if group.running {
                HelmBadge(UnStr.runningBadge, tint: .orange)
            }
            Spacer()
            Text(Bytes(group.app.sizeBytes))
                .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
        }
        // A name, a "Running" badge and a size: one heading, read in order.
        .accessibilityElement(children: .combine)
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: 10) {
            Toggle((leftover.path as NSString).lastPathComponent, isOn: Binding(
                get: { uvm.isSelected(leftover: leftover.path) },
                set: { on in uvm.setSelected(leftover: leftover.path, on) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text((leftover.path as NSString).lastPathComponent).lineLimit(1)
                    // Says why the box is empty: this one was found by the app's
                    // name, and names collide.
                    if leftover.matchedByName {
                        HelmBadge(UnStr.matchedByName)
                    }
                }
                Text(leftover.path)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .lineLimit(1).truncationMode(.middle)
            }
            // The name, the badge that qualifies it and the path are one thing
            // to read; the checkbox stays its own stop.
            .accessibilityElement(children: .combine)
            Spacer()
            Text(Bytes(leftover.sizeBytes))
                .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
        }
        .frame(minHeight: 32)
    }

}
