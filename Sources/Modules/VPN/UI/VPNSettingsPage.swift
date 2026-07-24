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
            HStack(spacing: 8) {
                Image(systemName: "lock.slash")
                Text("No VPNs configured in System Settings.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            ForEach(vm.connections) { connection in
                connectionRow(connection)
            }
        }
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        let active = c.status == .connected || c.status == .connecting
        let transitioning = c.status == .connecting || c.status == .disconnecting
        return HStack(spacing: 12) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name)
                HStack(spacing: 6) {
                    if let kind = prettyKind(c.kind) {
                        Text(kind)
                    }
                    Text("· \(statusText(c.status))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if transitioning { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(
                get: { active },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func prettyKind(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for k in ["L2TP", "IKEv2", "IPSec", "WireGuard", "PPTP"] where raw.contains(k) { return k }
        return raw.split(separator: ":").first.map(String.init)
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

    @ViewBuilder
    private var appRulesEditor: some View {
        if rules.isEmpty {
            Text("Add an app to automatically connect a VPN while that app is running.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        ForEach(Array(sortedBundleIDs.enumerated()), id: \.element) { index, bundleID in
            if index > 0 { Divider() }
            appRuleRow(bundleID)
        }
        Button {
            pickApp()
        } label: {
            Label("Add app…", systemImage: "plus")
        }
        .disabled(vm.connections.isEmpty)
    }

    private func appRuleRow(_ bundleID: String) -> some View {
        let info = Self.appInfo(bundleID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: info.icon)
                    .resizable().frame(width: 24, height: 24)
                Text(info.name).font(.headline)
                Spacer()
                Picker("", selection: vpnNameBinding(bundleID)) {
                    ForEach(vm.connections.map(\.name), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                Button {
                    rules.removeValue(forKey: bundleID)
                    persist()
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Toggle("Connect when it launches", isOn: connectOnLaunchBinding(bundleID))
                .controlSize(.small)
            Toggle("Disconnect when it quits", isOn: disconnectOnQuitBinding(bundleID))
                .controlSize(.small)
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
