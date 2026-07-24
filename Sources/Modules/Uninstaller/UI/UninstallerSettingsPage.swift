import AppKit
import SwiftUI
import HelmUI
import Module_Uninstaller_Engine

extension InstalledApp: Identifiable { public var id: String { bundleID } }

public struct UninstallerSettingsPage: View {
    @StateObject private var uvm: UninstallerViewModel

    @State private var apps: [InstalledApp] = []
    @State private var loading = true
    @State private var search = ""
    @State private var selectedID: String?
    @State private var scan: ScanResult?
    @State private var scanning = false
    @State private var selectedPaths: Set<String> = []
    @State private var busy = false
    @State private var confirming = false
    @State private var confirmingRunning = false
    @State private var resultBanner: String?

    public init(vm: ModuleViewModel) {
        _uvm = StateObject(wrappedValue: UninstallerViewModel(vm: vm))
    }

    private var filtered: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var selectedApp: InstalledApp? { apps.first { $0.bundleID == selectedID } }

    /// 0 = installed apps, 1 = leftovers from apps that are already gone.
    @State private var tab = 0

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(UnStr.tabApps).tag(0)
                Text(UnStr.tabOrphans).tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            if tab == 0 {
                HStack(spacing: 0) {
                    appList.frame(width: 260)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                OrphansView(uvm: uvm)
            }
        }
        .task { await reload() }
    }

    // MARK: - Left: app list

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(UnStr.searchApps, text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            Divider()
            if loading {
                Spacer(); ProgressView().controlSize(.small); Text(UnStr.loadingApps).font(.caption).foregroundStyle(.secondary); Spacer()
            } else {
                List(filtered, selection: $selectedID) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(ByteFormat.string(app.sizeBytes)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(app.bundleID)
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: selectedID) { _, _ in Task { await runScan() } }
    }

    // MARK: - Right: scan detail

    @ViewBuilder private var detail: some View {
        if selectedApp == nil {
            HelmCenteredContent { Text(UnStr.pickApp).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }
        } else if scanning {
            HelmCenteredContent { ProgressView(); Text(UnStr.scanning).font(.caption).foregroundStyle(.secondary) }
        } else if let scan {
            scanView(scan)
        }
    }

    private func scanView(_ scan: ScanResult) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // The app bundle — always removed.
                    row(icon: NSWorkspace.shared.icon(forFile: scan.appPath),
                        title: selectedApp?.name ?? scan.bundleID,
                        subtitle: UnStr.theApp, size: scan.appSizeBytes,
                        checked: .constant(true), locked: true, byName: false)

                    if scan.leftovers.isEmpty {
                        Text(UnStr.nothingFound).font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(LeftoverKind.allCases, id: \.self) { kind in
                            let items = scan.leftovers.filter { $0.kind == kind }
                            if !items.isEmpty {
                                Text(UnStr.kind(kind)).font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(items, id: \.path) { lo in
                                    row(icon: nil, title: (lo.path as NSString).lastPathComponent,
                                        subtitle: lo.path, size: lo.sizeBytes,
                                        checked: binding(for: lo.path), locked: false, byName: lo.matchedByName)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            footer(scan)
        }
    }

    private func footer(_ scan: ScanResult) -> some View {
        HStack {
            if let resultBanner {
                Label(resultBanner, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text(ByteFormat.string(selectedTotalSize(scan))).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if scan.runningNow { confirmingRunning = true } else { confirming = true }
            } label: {
                if busy { ProgressView().controlSize(.small) } else { Text(UnStr.moveToTrash) }
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(busy)
        }
        .padding(12)
        .confirmationDialog(UnStr.confirmTrash(selectedCount(scan), ByteFormat.string(selectedTotalSize(scan))),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(UnStr.moveToTrash, role: .destructive) { Task { await performUninstall(scan, quitFirst: false) } }
            Button(UnStr.cancel, role: .cancel) {}
        }
        .confirmationDialog(UnStr.appRunningTitle, isPresented: $confirmingRunning, titleVisibility: .visible) {
            Button(UnStr.quitAndRemove, role: .destructive) { Task { await performUninstall(scan, quitFirst: true) } }
            Button(UnStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Row

    private func row(icon: NSImage?, title: String, subtitle: String, size: Int,
                     checked: Binding<Bool>, locked: Bool, byName: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: checked).labelsHidden().disabled(locked)
            if let icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1)
                    if byName {
                        Text(UnStr.byName).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                }
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(size)).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { selectedPaths.contains(path) },
                set: { if $0 { selectedPaths.insert(path) } else { selectedPaths.remove(path) } })
    }
    private func selectedCount(_ scan: ScanResult) -> Int { 1 + selectedPaths.count }
    private func selectedTotalSize(_ scan: ScanResult) -> Int {
        scan.appSizeBytes + scan.leftovers.filter { selectedPaths.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    private func reload() async {
        loading = true
        apps = await uvm.listApps()
        loading = false
    }
    private func runScan() async {
        resultBanner = nil
        guard let app = selectedApp else { scan = nil; return }
        scanning = true; scan = nil
        let r = await uvm.scan(app)
        scan = r
        selectedPaths = Set(r?.leftovers.map(\.path) ?? [])
        scanning = false
    }
    private func performUninstall(_ scan: ScanResult, quitFirst: Bool) async {
        busy = true
        if quitFirst {
            await uvm.quit(bundleID: scan.bundleID)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        let r = await uvm.uninstall(appPath: scan.appPath, paths: Array(selectedPaths))
        busy = false
        if let r {
            resultBanner = UnStr.freed(ByteFormat.string(r.freedBytes))
        }
        await reload()
        selectedID = nil; self.scan = nil
    }
}
