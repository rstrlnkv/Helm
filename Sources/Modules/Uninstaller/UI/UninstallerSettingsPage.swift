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
        VStack(spacing: 0) {
            HelmMetricStrip([
                .init(loading ? "—" : "\(apps.count)", UnStr.metricApps),
                .init("\(checked.count)", UnStr.metricChosen, tint: checked.isEmpty ? nil : .accentColor),
                .init(sizeText, UnStr.metricSize),
            ])
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Picker("", selection: $tab) {
                Text(UnStr.tabApps).tag(0)
                Text(UnStr.tabOrphans).tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            .disabled(step == .review)

            Divider()

            if tab == 0 {
                switch step {
                case .pick: pickStep
                case .review: reviewStep
                }
            } else {
                OrphansView(uvm: uvm)
            }
        }
        .task {
            apps = await uvm.listApps()
            loading = false
        }
    }

    private var sizeText: String {
        let bytes: Int
        if step == .review {
            bytes = UninstallPlan.totalBytes(groups, selectedLeftovers: selectedLeftovers)
        } else {
            bytes = apps.filter { checked.contains($0.bundleID) }.reduce(0) { $0 + $1.sizeBytes }
        }
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Step 1: pick apps

    private var pickStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(UnStr.searchApps, text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .helmCard(padding: 8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
                Button(UnStr.selectNone) { checked.removeAll() }
                    .disabled(checked.isEmpty)
                Spacer()
                if let banner = resultBanner {
                    Text(banner).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            .padding(12)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Toggle(isOn: Binding(
            get: { checked.contains(app.bundleID) },
            set: { on in
                if on { checked.insert(app.bundleID) } else { checked.remove(app.bundleID) }
            }
        )) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(forFile: app.path))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1)
                    Text(app.path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(app.sizeBytes), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Step 2: review the files, grouped per app

    private var reviewStep: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups, id: \.id) { group in
                    Section {
                        if group.leftovers.isEmpty {
                            Text(UnStr.noLeftoversForApp)
                                .font(.caption).foregroundStyle(.secondary)
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
                .background(Color.orange.opacity(0.10))
            }

            HStack(spacing: 10) {
                Button(UnStr.back) {
                    step = .pick
                    forceQuit = false
                }
                Spacer()
                Text(UnStr.willFree(sizeText)).font(.caption).foregroundStyle(.secondary)
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
            .padding(12)
        }
    }

    private func groupHeader(_ group: UninstallGroup) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(forFile: group.app.path))
                .resizable().frame(width: 18, height: 18)
            Text(group.app.name).font(.callout.weight(.semibold))
            if group.running {
                Text(UnStr.runningBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(group.app.sizeBytes), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        Toggle(isOn: Binding(
            get: { selectedLeftovers.contains(leftover.path) },
            set: { on in
                if on { selectedLeftovers.insert(leftover.path) }
                else { selectedLeftovers.remove(leftover.path) }
            }
        )) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text((leftover.path as NSString).lastPathComponent).lineLimit(1)
                    Text(leftover.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(leftover.sizeBytes), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Actions

    private func prepareReview() async {
        scanning = true
        resultBanner = nil
        defer { scanning = false }
        var built: [UninstallGroup] = []
        for app in apps where checked.contains(app.bundleID) {
            let scan = await uvm.scan(app)
            built.append(UninstallGroup(app: app,
                                        leftovers: scan?.leftovers ?? [],
                                        running: scan?.runningNow ?? false))
        }
        groups = built
        selectedLeftovers = Set(UninstallPlan.allLeftoverPaths(built))
        forceQuit = false
        HelmLog.shared.info("uninstaller",
                            "review \(built.count) apps, \(selectedLeftovers.count) leftovers, running: "
                            + built.filter(\.running).map(\.app.name).joined(separator: ","))
        step = .review
    }

    private func removeSelection() async {
        guard UninstallPlan.readiness(groups, forceQuit: forceQuit) == .ready else { return }
        busy = true
        defer { busy = false }

        if forceQuit {
            for group in groups where group.running {
                HelmLog.shared.info("uninstaller", "force quit \(group.app.bundleID)")
                await uvm.quit(bundleID: group.app.bundleID, force: true)
            }
            // Let the apps disappear before their bundles move.
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        let paths = UninstallPlan.paths(groups, selectedLeftovers: selectedLeftovers)
        HelmLog.shared.info("uninstaller", "trashing \(paths.count) paths")
        let result = await uvm.trashPaths(paths)

        let freed = ByteCountFormatter.string(fromByteCount: Int64(result?.freedBytes ?? 0), countStyle: .file)
        if let failed = result?.failed, !failed.isEmpty {
            HelmLog.shared.warn("uninstaller", "failed to trash: \(failed.joined(separator: ", "))")
            resultBanner = UnStr.removedWithFailures(freed, failed.count)
        } else {
            resultBanner = UnStr.removedFreed(freed)
        }

        checked.removeAll()
        groups = []
        selectedLeftovers = []
        forceQuit = false
        step = .pick
        apps = await uvm.listApps()
    }
}
