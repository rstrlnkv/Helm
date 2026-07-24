import SwiftUI
import HelmUI
import Module_Homebrew_Engine

extension BrewPackage: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }
extension OutdatedPackage: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }
extension SearchHit: Identifiable { public var id: String { (isCask ? "c:" : "f:") + name } }

public struct HomebrewSettingsPage: View {
    @StateObject private var hb: HomebrewViewModel
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
    }

    // MARK: - Not installed

    private var installScreen: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "shippingbox").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(HbStr.notInstalledTitle).font(.title3.bold())
            Text(HbStr.notInstalledBody).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Button(HbStr.installBrew) { hb.installBrew() }
                .buttonStyle(.borderedProminent).disabled(hb.running)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Manager

    private var manager: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text(HbStr.segInstalled).tag(0)
                Text(HbStr.segUpdates).tag(1)
                Text(HbStr.segSearch).tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().padding(12)
            .onChange(of: segment) { _, seg in
                Task {
                    if seg == 0 { await hb.refreshInstalled() }
                    else if seg == 1 { await hb.refreshOutdated() }
                }
            }
            Divider()
            Group {
                switch segment {
                case 1: updatesList
                case 2: searchView
                default: installedList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var installedList: some View {
        listOrEmpty(hb.installed, empty: HbStr.noneInstalled) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask,
                   desc: hb.description(name: pkg.name, isCask: pkg.isCask)) {
                Button(HbStr.uninstall) { hb.uninstall(pkg) }.disabled(hb.running)
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
            listOrEmpty(hb.outdated, empty: HbStr.upToDate) { pkg in
                pkgRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask) {
                    Button(HbStr.upgrade) { hb.upgrade(pkg) }.disabled(hb.running)
                }
            }
        }
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(HbStr.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await hb.search(query) } }
            }.padding(10)
            Divider()
            if query.isEmpty && hb.searchHits.isEmpty {
                HelmCenteredContent { Text(HbStr.typeToSearch).foregroundStyle(.secondary) }
            } else {
                listOrEmpty(hb.searchHits, empty: HbStr.noResults) { hit in
                    pkgRow(name: hit.name, detail: nil, isCask: hit.isCask,
                           desc: hb.description(name: hit.name, isCask: hit.isCask)) {
                        Button(HbStr.install) { hb.install(hit) }.disabled(hb.running)
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
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: 160)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
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
                    Text(isCask ? HbStr.cask : HbStr.formula).font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(isCask ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2)))
                        .foregroundStyle(isCask ? .purple : .blue)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                }
                if let desc {
                    Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            action().controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func listOrEmpty<T: Identifiable, Row: View>(_ items: [T], empty: String,
                                                         @ViewBuilder row: @escaping (T) -> Row) -> some View {
        Group {
            if items.isEmpty { HelmCenteredContent { Text(empty).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() } }
            else {
                List(items) { row($0).listRowSeparator(.hidden) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
            }
        }
    }

}
