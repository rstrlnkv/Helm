import AppKit
import SwiftUI
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

extension InstalledApp: Identifiable { public var id: String { bundleID } }

/// `NSWorkspace.icon(forFile:)` hits the disk; List rows re-render often, so
/// icons are memoized per bundle path.
@MainActor
private enum AppIconCache {
    static let cache = NSCache<NSString, NSImage>()
    static func icon(forFile path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

/// Two steps, AppCleaner-style: tick the apps to remove, then review the files
/// found for each of them before anything goes to the Trash. A running app is
/// never removed silently — it is quit first, and only if the user says so.
public struct UninstallerSettingsPage: View {
    @StateObject private var uvm: UninstallerViewModel

    private enum Step: Equatable { case pick, review }

    @State private var diskAccess: PermissionState = .granted
    @State private var step: Step = .pick
    @State private var apps: [InstalledApp] = []
    @State private var loading = true
    @State private var search = ""
    @State private var checked: Set<String> = []          // bundle ids
    @State private var groups: [UninstallGroup] = []
    @State private var selectedLeftovers: Set<String> = []
    @State private var scanning = false
    @State private var busy = false
    @State private var forceQuit = false
    @State private var resultBanner: String?
    @State private var failures: [TrashFailureInfo] = []

    /// 0 = installed apps, 1 = leftovers from apps that are already gone.
    @State private var tab = 0

    public init(vm: ModuleViewModel) {
        _uvm = StateObject(wrappedValue: UninstallerViewModel(vm: vm))
    }

    private var filtered: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var runningNames: [String] {
        if case .needsQuit(let names) = UninstallPlan.readiness(groups, forceQuit: false) { return names }
        return []
    }

    public var body: some View {
        pageBody
            .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .task {
                diskAccess = PermissionCheck.currentFullDiskAccess()
                apps = await uvm.listApps()
                loading = false
                await fillInSizes()
            }
    }

    private var pageBody: some View {
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
                        .symbolEffect(.rotate, options: .repeating, isActive: loading)
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
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: UnStr.removalNeedsAccess)
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
    }

    /// Counts read as a quiet status line instead of a panel of dials.
    private var statusLine: String {
        let count: Int? = loading ? nil : apps.count
        guard !checked.isEmpty else { return UnStr.appsCount(count) }
        return UnStr.appsCountSelected(count, checked.count, sizeText)
    }

    private func refreshApps() async {
        loading = true
        apps = await uvm.listApps()
        await fillInSizes()
        loading = false
    }

    private var sizeText: String {
        let bytes: Int
        if step == .review {
            bytes = UninstallPlan.totalBytes(groups, selectedLeftovers: selectedLeftovers)
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
                .padding(.horizontal, 12)
            }
            Divider()
            HStack(spacing: 10) {
                Button(UnStr.selectNone) { checked.removeAll() }
                    .disabled(checked.isEmpty)
                Text(statusLine)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                Spacer()
                if let banner = resultBanner {
                    Text(banner).font(.caption).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
                Button {
                    Task { await prepareReview() }
                } label: {
                    if scanning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(UnStr.scanning)
                        }
                    } else {
                        Text(UnStr.reviewCount(checked.count))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(checked.isEmpty || scanning)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        // The checkbox is its own control centred against the row, so it lines
        // up with the icon and the name instead of hanging above them.
        HStack(spacing: 10) {
            // Named, though the label stays hidden: `.labelsHidden()` hides a
            // label visually and keeps it for VoiceOver, but an empty string
            // leaves nothing to keep — a list of 250 rows read as "checkbox,
            // unchecked" 250 times.
            Toggle(app.name, isOn: Binding(
                get: { checked.contains(app.bundleID) },
                set: { on in
                    if on { checked.insert(app.bundleID) } else { checked.remove(app.bundleID) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Image(nsImage: AppIconCache.icon(forFile: app.path))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.path)
                    .font(.caption).foregroundStyle(HelmText.quiet).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Bytes(app.sizeBytes))
                .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .onTapGesture {
            if checked.contains(app.bundleID) { checked.remove(app.bundleID) }
            else { checked.insert(app.bundleID) }
        }
    }

    // MARK: - Step 2: review the files, grouped per app

    private var reviewStep: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups, id: \.id) { group in
                    Section {
                        if group.leftovers.isEmpty {
                            Text(UnStr.noLeftoversForApp)
                                .font(.caption).foregroundStyle(HelmText.quiet)
                        }
                        ForEach(group.leftovers, id: \.path) { leftover in
                            leftoverRow(leftover)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)

            Divider()

            if !runningNames.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UnStr.runningWarning(runningNames.joined(separator: ", ")))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(UnStr.forceQuitAndRemove, isOn: $forceQuit)
                            .font(.callout)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                
            }

            HStack(spacing: 10) {
                Button(UnStr.back) {
                    step = .pick
                    forceQuit = false
                }
                Spacer()
                Text(UnStr.willFree(sizeText)).font(.caption).foregroundStyle(HelmText.quiet)
                // A blocked action must also LOOK blocked: a prominent blue
                // button that silently does nothing invites repeated clicks.
                let ready = UninstallPlan.readiness(groups, forceQuit: forceQuit) == .ready
                Button {
                    Task { await removeSelection() }
                } label: {
                    if busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(UnStr.removing)
                        }
                    } else {
                        Text(UnStr.moveToTrash)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ready ? Color.accentColor : Color.gray)
                .opacity(ready ? 1 : 0.55)
                .disabled(busy || !ready)
                .help(ready ? "" : UnStr.blockedByRunning)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    /// What stayed behind, why, and what to do about it.
    private var failureReport: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(failures, id: \.path) { failure in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text((failure.path as NSString).lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Button(UnStr.showInFinder) { reveal(failure.path) }
                                    .controlSize(.small)
                            }
                            Text(failure.path)
                                .font(.caption).foregroundStyle(HelmText.quiet)
                                .lineLimit(1).truncationMode(.middle)
                            Text(UnStr.failureReason(failure.reason))
                                .font(.caption).foregroundStyle(.orange)
                            if !failure.message.isEmpty {
                                // macOS's own words: the classification is a
                                // summary, this is the evidence behind it.
                                Text(failure.message)
                                    .font(.caption2).foregroundStyle(HelmText.faint)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text(UnStr.couldNotRemove(failures.count))
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)

            Divider()
            HStack(spacing: 10) {
                if failures.contains(where: { $0.reason == TrashFailure.Reason.needsFullDiskAccess.rawValue }) {
                    Button(UnStr.openDiskAccess) { PermissionCheck.openFullDiskAccessSettings() }
                }
                if failures.contains(where: { $0.reason == TrashFailure.Reason.activeSystemExtension.rawValue }) {
                    Button(UnStr.openExtensions) { PermissionCheck.openExtensionSettings() }
                }
                Spacer()
                Button(UnStr.done) { failures = [] }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    /// Selecting a file Finder cannot see does nothing at all, so fall back to
    /// opening the enclosing folder — and bring Finder forward either way.
    private func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder").first?.activate()
    }

    private func groupHeader(_ group: UninstallGroup) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(forFile: group.app.path))
                .resizable().frame(width: 18, height: 18)
            Text(group.app.name).font(.callout.weight(.semibold))
            if group.running {
                HelmBadge(UnStr.runningBadge, tint: .orange)
            }
            Spacer()
            Text(Bytes(group.app.sizeBytes))
                .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
        }
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: 10) {
            Toggle((leftover.path as NSString).lastPathComponent, isOn: Binding(
                get: { selectedLeftovers.contains(leftover.path) },
                set: { on in
                    if on { selectedLeftovers.insert(leftover.path) }
                    else { selectedLeftovers.remove(leftover.path) }
                }
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
            Spacer()
            Text(Bytes(leftover.sizeBytes))
                .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
        }
        .frame(minHeight: 32)
    }

    /// The list is drawn from names alone and the numbers land a moment later.
    /// Measuring 39 bundles took four seconds here — nine on a cold cache — and
    /// the page paid it before showing anything, every single visit.
    private func fillInSizes() async {
        let sizes = await uvm.appSizes()
        guard !sizes.isEmpty else { return }
        apps = apps.map { app in
            guard let size = sizes[app.bundleID], size != app.sizeBytes else { return app }
            return InstalledApp(name: app.name, bundleID: app.bundleID,
                                path: app.path, sizeBytes: size)
        }
    }

    // MARK: - Actions

    private func prepareReview() async {
        scanning = true
        resultBanner = nil
        defer { scanning = false }
        // Concurrently: the scans are independent, each already hops to a
        // background queue, and awaiting them in a row stacked every delay.
        // Order comes from `apps`, not from whichever finishes first.
        let chosen = apps.filter { checked.contains($0.bundleID) }
        var scans: [String: ScanResult] = [:]
        await withTaskGroup(of: (String, ScanResult?).self) { group in
            for app in chosen {
                group.addTask { (app.bundleID, await uvm.scan(app)) }
            }
            for await (id, scan) in group { scans[id] = scan }
        }
        let built = chosen.map { app in
            UninstallGroup(app: app,
                           leftovers: scans[app.bundleID]?.leftovers ?? [],
                           running: scans[app.bundleID]?.runningNow ?? false)
        }
        groups = built
        selectedLeftovers = Set(UninstallPlan.defaultSelection(built))
        forceQuit = false
        HelmLog.shared.info("uninstaller",
                            "review \(built.count) apps, \(selectedLeftovers.count) leftovers, running: "
                            + built.filter(\.running).map { Redact.app($0.app.name) }.joined(separator: ","))
        step = .review
    }

    private func removeSelection() async {
        guard UninstallPlan.readiness(groups, forceQuit: forceQuit) == .ready else { return }
        busy = true
        defer { busy = false }

        if forceQuit {
            for group in groups where group.running {
                HelmLog.shared.info("uninstaller", "force quit \(Redact.app(group.app.bundleID))")
                await uvm.quit(bundleID: group.app.bundleID, force: true)
            }
            // Let the apps disappear before their bundles move.
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        let paths = UninstallPlan.paths(groups, selectedLeftovers: selectedLeftovers)
        HelmLog.shared.info("uninstaller", "trashing \(paths.count) paths")
        let result = await uvm.trashPaths(paths)

        let freed = Bytes(result?.freedBytes ?? 0)
        if let failed = result?.failed, !failed.isEmpty {
            HelmLog.shared.warn("uninstaller", "failed to trash: \(Redact.paths(failed))")
            resultBanner = UnStr.removedWithFailures(freed, failed.count)
            // Leftovers that stayed put are the whole point of the module, so
            // they get a screen of their own rather than a line to overlook.
            failures = result?.failures ?? failed.map { TrashFailureInfo(path: $0, reason: "unknown") }
        } else {
            resultBanner = UnStr.removedFreed(freed)
            failures = []
        }

        checked.removeAll()
        groups = []
        selectedLeftovers = []
        forceQuit = false
        step = .pick
        apps = await uvm.listApps()
        await fillInSizes()
    }
}
