import SwiftUI
import AppKit
import HelmRuntime
import HelmUI
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
        vpnForm
            .helmMetricsHeader {
                HelmMetricStrip([
                    .init("\(vm.connections.count)", VPNStr.metricConnections),
                    .init("\(activeCount)", VPNStr.metricActive, tint: activeCount > 0 ? .green : nil),
                    .init("\(vm.autoConnected.count)", VPNStr.metricAutomatic),
                ])
            }
    }

    /// Connections that are up or on their way up.
    private var activeCount: Int {
        vm.connections.filter { $0.status == .connected || $0.status == .connecting }.count
    }

    private var vpnForm: some View {
        Form {
            Section(VPNStr.connections) {
                connectionsList
            }

            Section(VPNStr.perAppAutomation) {
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
                Text(VPNStr.noVPNsSystem)
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
            HelmStatusDot(active: active)
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
                .accessibilityLabel(c.name)
        }
        .padding(.vertical, 3)
    }

    private func prettyKind(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for k in ["L2TP", "IKEv2", "IPSec", "WireGuard", "PPTP"] where raw.contains(k) { return k }
        return raw.split(separator: ":").first.map(String.init)
    }

    private func statusText(_ status: VPNStatus) -> String { VPNStr.status(status) }

    // MARK: - Per-app automation

    private var sortedBundleIDs: [String] {
        rules.keys.sorted()
    }

    @ViewBuilder
    private var appRulesEditor: some View {
        if rules.isEmpty {
            Text(VPNStr.perAppHint)
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
            Label(VPNStr.addApp, systemImage: "plus")
        }
        .disabled(vm.connections.isEmpty)
    }

    private func appRuleRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
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
            Toggle(VPNStr.connectOnLaunch, isOn: connectOnLaunchBinding(bundleID))
                .controlSize(.small)
            Toggle(VPNStr.disconnectOnQuit, isOn: disconnectOnQuitBinding(bundleID))
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
        let defaultVPN = vm.connections.first?.name ?? ""
        var added = false
        for bundleID in AppPicker.choose() where rules[bundleID] == nil {
            rules[bundleID] = VPNAppRule(vpnName: defaultVPN)
            added = true
        }
        if added { persist() }
    }
}
