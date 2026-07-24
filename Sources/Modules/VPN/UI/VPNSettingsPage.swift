import SwiftUI
import AppKit
import HelmRuntime
import Module_VPN_Engine

/// Settings page for the VPN module. Connections are read live from the view
/// model; per-app automation rules are seeded from the `NamespacedStore` into
/// local `@State` and written through on every change, notifying the engine
/// via `reloadRules`.
public struct VPNSettingsPage: View {
    @ObservedObject private var vm: VPNViewModel
    private let store: NamespacedStore

    @State private var rules: [String: VPNAppRule]

    public init(vm: VPNViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _rules = State(initialValue: VPNRules.decode(store.string("vpnAppRules", default: "{}")))
    }

    public var body: some View {
        Form {
            Section("Connections") {
                connectionsList
            }

            Section("Per-app automation") {
                appRulesEditor
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connections

    @ViewBuilder
    private var connectionsList: some View {
        if vm.connections.isEmpty {
            Text("No VPNs configured.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(vm.connections) { connection in
                HStack {
                    Text(connection.name)
                    Spacer()
                    Text(statusText(connection.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusText(_ status: VPNStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .disconnecting: return "Disconnecting…"
        case .unknown: return "Unknown"
        }
    }

    // MARK: - Per-app automation

    private var sortedBundleIDs: [String] {
        rules.keys.sorted()
    }

    private var appRulesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedBundleIDs, id: \.self) { bundleID in
                appRuleRow(bundleID)
            }
            Button {
                pickApp()
            } label: {
                Label("Add app…", systemImage: "plus")
            }
        }
    }

    private func appRuleRow(_ bundleID: String) -> some View {
        let info = Self.appInfo(bundleID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: info.icon)
                    .resizable().frame(width: 20, height: 20)
                Text(info.name)
                Spacer()
                Button {
                    rules.removeValue(forKey: bundleID)
                    persist()
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Picker("VPN", selection: vpnNameBinding(bundleID)) {
                ForEach(vm.connections.map(\.name), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            Toggle("Connect on launch", isOn: connectOnLaunchBinding(bundleID))
            Toggle("Disconnect on quit", isOn: disconnectOnQuitBinding(bundleID))
        }
        .padding(.vertical, 4)
    }

    private func vpnNameBinding(_ bundleID: String) -> Binding<String> {
        Binding(
            get: { rules[bundleID]?.vpnName ?? vm.connections.first?.name ?? "" },
            set: { newValue in
                var rule = rules[bundleID] ?? VPNAppRule(vpnName: newValue)
                rule.vpnName = newValue
                rules[bundleID] = rule
                persist()
            })
    }

    private func connectOnLaunchBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { rules[bundleID]?.connectOnLaunch ?? true },
            set: { newValue in
                var rule = rules[bundleID] ?? VPNAppRule(vpnName: vm.connections.first?.name ?? "")
                rule.connectOnLaunch = newValue
                rules[bundleID] = rule
                persist()
            })
    }

    private func disconnectOnQuitBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { rules[bundleID]?.disconnectOnQuit ?? true },
            set: { newValue in
                var rule = rules[bundleID] ?? VPNAppRule(vpnName: vm.connections.first?.name ?? "")
                rule.disconnectOnQuit = newValue
                rules[bundleID] = rule
                persist()
            })
    }

    private func persist() {
        store.set(VPNRules.encode(rules), for: "vpnAppRules")
        vm.send("reloadRules")
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        guard rules[bundleID] == nil else { return }
        rules[bundleID] = VPNAppRule(vpnName: vm.connections.first?.name ?? "")
        persist()
    }

    private static func appInfo(_ bundleID: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}
