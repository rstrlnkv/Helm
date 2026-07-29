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
    }

    /// Connections that are up. Not on their way up: the strip says "active"
    /// and tints it green, beside a row spinning and saying "Connecting".
    private var activeCount: Int {
        vm.connections.filter(\.status.isConnected).count
    }

    private var vpnForm: some View {
        Form {
            Section {
                HelmMetricStrip([
                    .init("\(vm.connections.count)", VPNStr.metricConnections),
                    .init("\(activeCount)", VPNStr.metricActive, tint: activeCount > 0 ? .green : nil),
                    // The rules written down, not the ones firing this second:
                    // the dial sat directly above the list and read 0 over one
                    // visible rule. Which of them is up is the dot's answer.
                    .init("\(VPNRules.automationCount(rules))", VPNStr.metricAutomatic),
                ])
            }

            Section(VPNStr.connections) {
                connectionsList
            }

            Section(VPNStr.perAppAutomation) {
                appRulesEditor
            }
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        // The engine is asked once in `init` and the view model is cached for
        // the app's lifetime, so without these the page showed whatever the
        // system said at launch — this was the only settings page of nine with
        // no `.task` at all.
        .task { vm.refresh() }
        // A VPN connected, disconnected or added while the person was in
        // System Settings. `DynamicStoreNetworkWatch` catches most of that
        // already; coming back to Helm is the moment it costs nothing to be
        // sure, and it is the one route that needs no observer to have fired.
        .helmOnAppActive { vm.refresh() }
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
            .foregroundStyle(HelmText.quiet)
            .accessibilityElement(children: .combine)
        } else {
            ForEach(vm.connections) { connection in
                connectionRow(connection)
            }
        }
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        let active = c.status.isUp
        let transitioning = c.status.isTransitioning
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
                .foregroundStyle(HelmText.quiet)
            }
            // The name and what it is doing are one thing to read, not two
            // stops. On the text only, the way Disk and Duplicates do it: the
            // switch beside it stays its own control.
            .accessibilityElement(children: .combine)
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
                .foregroundStyle(HelmText.quiet)
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

    /// One line per app: which VPN, and when the rule fires. The two switches
    /// this replaces were not independent settings — "neither" is a rule that
    /// does nothing, which the menu can name.
    private func appRuleRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
        // A renamed or deleted VPN silently disables its rules; the row said
        // nothing and the picker simply showed blank.
        // `VPNRules.orphaned` is this question, tested, and was answered here
        // by hand — per row, which is also how the second answer gets written.
        let missing = VPNRules.orphaned(rules, against: vm.connections)[bundleID] != nil
        return HelmAppRuleRow(bundleID: bundleID) {
            // Two nameless pop-ups in one row are indistinguishable to
            // VoiceOver; each carries what it chooses.
            Picker("\(info.name) — \(VPNStr.rulePickerVPN)", selection: vpnNameBinding(bundleID)) {
                ForEach(vm.connections.map(\.name), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("\(info.name) — \(VPNStr.rulePickerWhen)", selection: timingBinding(bundleID)) {
                ForEach(VPNAppRule.Timing.allCases, id: \.self) { timing in
                    Text(VPNStr.ruleTiming(timing)).tag(timing)
                }
            }
            .labelsHidden()
            .fixedSize()
        } note: {
            if missing, let name = rules[bundleID]?.vpnName {
                HStack(spacing: 6) {
                    // The token, not `.orange`: `HelmPermissionNote` draws this
                    // exact glyph two rows away at 4.54:1, and the literal
                    // measured 2.31:1 in light appearance.
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .accessibilityHidden(true)   // the text beside it says it
                    Text(VPNStr.ruleVPNMissing(name))
                        .font(.caption)
                        .foregroundStyle(HelmText.quiet)
                }
            }
        } remove: {
            rules.removeValue(forKey: bundleID)
            persist()
        }
    }

    private func timingBinding(_ bundleID: String) -> Binding<VPNAppRule.Timing> {
        Binding(
            get: { rules[bundleID]?.timing ?? .launchAndQuit },
            set: { newValue in
                guard var rule = rules[bundleID] else { return }
                rule.set(newValue)
                rules[bundleID] = rule
                persist()
            })
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
