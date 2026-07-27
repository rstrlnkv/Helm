import SwiftUI
import HelmUI
import Module_Homebrew_Engine

extension BrewPackage: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }
extension OutdatedPackage: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }
extension SearchHit: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }

public struct HomebrewSettingsPage: View {
    @StateObject private var hb: HomebrewViewModel
    @State private var pendingUninstall: BrewPackage?
    @State private var segment = 0
    @State private var query = ""

    public init(vm: ModuleViewModel) { _hb = StateObject(wrappedValue: HomebrewViewModel(vm: vm)) }

    public var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                manager
            } else {
                installScreen
            }
            if !hb.consoleLines.isEmpty || hb.running {
                Divider()
                console
            }
        }
        .task {
            await hb.refreshStatus()
            if hb.status.installed { await hb.refreshInstalled() }
        }
        // Removing a cask removes an application. Every other destructive
        // action in Helm asks first; this one used to go on a single click.
        .confirmationDialog(pendingUninstall.map { HbStr.confirmUninstall($0.name) } ?? "",
                            isPresented: Binding(get: { pendingUninstall != nil },
                                                 set: { if !$0 { pendingUninstall = nil } }),
                            titleVisibility: .visible) {
            Button(HbStr.uninstall, role: .destructive) {
                if let package = pendingUninstall { hb.uninstall(package) }
                pendingUninstall = nil
            }
            Button(HbStr.cancel, role: .cancel) { pendingUninstall = nil }
        }
    }

    // MARK: - Not installed

    private var installScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            HelmIconPlate(symbol: "shippingbox", tint: .pink, size: 56)
            VStack(spacing: 6) {
                Text(HbStr.notInstalledTitle)
                    .font(.system(size: 20, weight: .semibold))
                Text(HbStr.notInstalledBody)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            Button {
                hb.installBrew()
            } label: {
                Label(HbStr.installBrew, systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 260)
            .disabled(hb.running)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Manager

    private var manager: some View { managerBody }

    /// Counts as a quiet status line rather than a panel of dials.
    private var statusLine: String {
        // A count that has not arrived is not a count of zero. The list reloads
        // after every operation, and for that second the line read
        // "0 packages · 0 updates · 0 casks" over a machine with 53 of them.
        guard hb.loadedInstalled else { return HbStr.packagesLoading }
        return HbStr.packagesStatus(hb.installed.count,
                             hb.outdated.count,
                             hb.installed.filter(\.isCask).count)
    }

    private var managerBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $segment) {
                    Text(HbStr.segInstalled).tag(0)
                    Text(HbStr.segUpdates).tag(1)
                    Text(HbStr.segSearch).tag(2)
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 300)
                .onChange(of: segment) { _, seg in
                    Task {
                        if seg == 0 { await hb.refreshInstalled() }
                        else if seg == 1 { await hb.refreshOutdated() }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        if segment == 1 { await hb.refreshOutdated() }
                        else { await hb.refreshInstalled() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: hb.running)
                }
                .buttonStyle(.borderless)
                .disabled(hb.running)
                .help(HbStr.refreshList)
                .accessibilityLabel(HbStr.refreshList)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            Divider()
            Group {
                switch segment {
                case 1: updatesList
                case 2: searchView
                default: installedList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Counts belong in a quiet bottom bar, like the other list screens;
            // the toolbar is for what you can do, not for what there is.
            Divider()
            HStack {
                Text(statusLine)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            // A caption is shorter than a button: without this the bar was
            // 38 pt where the other two list screens are 49, and the content
            // jumped when switching between them.
            .frame(minHeight: 25)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private var installedList: some View {
        listOrEmpty(hb.installed, empty: hb.loadedInstalled ? HbStr.noneInstalled : nil) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask,
                   desc: hb.description(name: pkg.name, isCask: pkg.isCask)) {
                // Every other destructive action in Helm asks first; this one
                // removed a cask — an app — on a single click.
                Button(HbStr.uninstall) { pendingUninstall = pkg }
                    .disabled(hb.running)
                    .accessibilityLabel("\(HbStr.uninstall), \(pkg.name)")
            }
        }
    }

    private var updatesList: some View {
        VStack(spacing: 0) {
            if !hb.outdated.isEmpty {
                HStack {
                    Spacer()
                    Button(HbStr.upgradeAll) { hb.upgradeAll() }.disabled(hb.running)
                }.padding(8)
                Divider()
            }
            listOrEmpty(hb.outdated, empty: hb.loadedOutdated ? HbStr.upToDate : nil) { pkg in
                pkgRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask) {
                    Button(HbStr.upgrade) { hb.upgrade(pkg) }
                        .disabled(hb.running)
                        .accessibilityLabel("\(HbStr.upgrade), \(pkg.name)")
                }
            }
        }
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            HelmSearchField(text: $query, placeholder: HbStr.searchPlaceholder,
                            onSubmit: { Task { await hb.search(query) } })
                .frame(height: 22)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            if query.isEmpty && hb.searchHits.isEmpty {
                HelmCenteredContent { Text(HbStr.typeToSearch).foregroundStyle(HelmText.quiet) }
            } else {
                listOrEmpty(hb.searchHits, empty: HbStr.noResults) { hit in
                    pkgRow(name: hit.name, detail: nil, isCask: hit.isCask,
                           desc: hb.description(name: hit.name, isCask: hit.isCask)) {
                        Button(HbStr.install) { hb.install(hit) }
                            .disabled(hb.running)
                            .accessibilityLabel("\(HbStr.install), \(hit.name)")
                    }
                }
            }
        }
    }

    // MARK: - Console

    private var console: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusPill
                Spacer()
                Button(HbStr.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(hb.consoleLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: hb.consoleLines.count) { _, _ in
                    withAnimation(HelmMotion.interface) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: 160)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(12)
    }

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(hb.op.label).font(.caption) }
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed:
            Label(HbStr.failed, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Row helpers

    private func pkgRow<Action: View>(name: String, detail: String?, isCask: Bool,
                                      desc: String? = nil,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    // Only when it says something: 46 of 47 rows were
                    // "formula", and a label with one value is an ornament.
                    if isCask { HelmBadge(HbStr.cask, tint: .purple) }
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                }
                // The description arrives from a separate `brew desc` batch.
                // The line is always present (empty until then) so rows keep
                // their height and the list doesn't re-flow twice on load.
                Text(desc ?? " ")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            action().controlSize(.small)
        }
        .frame(minHeight: 34)
    }

    /// `empty` is nil while the first query is still out: "nothing installed"
    /// must not be shown to someone who is simply waiting for the list.
    private func listOrEmpty<T: Identifiable, Row: View>(_ items: [T], empty: String?,
                                                         @ViewBuilder row: @escaping (T) -> Row) -> some View {
        Group {
            if items.isEmpty, let empty {
                HelmCenteredContent { Text(empty).foregroundStyle(HelmText.quiet).multilineTextAlignment(.center).padding() }
            } else if items.isEmpty {
                HelmCenteredContent { ProgressView().controlSize(.small) }
            } else {
                List(items) { row($0) }
                    .listStyle(.inset)
                                .padding(.horizontal, 12)
            }
        }
    }

}
