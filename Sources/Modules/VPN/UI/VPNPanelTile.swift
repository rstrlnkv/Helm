import SwiftUI
import HelmUI
import Module_VPN_Engine

/// Compact tile shown in the shared Helm panel: each configured VPN gets a
/// small connect/disconnect switch.
public struct VPNPanelTile: View {
    @ObservedObject private var vm: VPNViewModel
    @Environment(\.helmTileSpan) private var span

    public init(vm: VPNViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if vm.connections.isEmpty {
                Text(VPNStr.noVPNs)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if span == .compact {
                // Half width: one switch for the whole module — it toggles the
                // connected VPN off, or the first one on. The full list lives in
                // the wide tile and in Settings.
                compactControl
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.connections) { connectionRow($0) }
                }
            }
        }
        .helmPanelCard()
    }

    /// Summary + single switch used when the grid gives this tile half a row.
    private var compactControl: some View {
        let connected = vm.connections.first { $0.status == .connected || $0.status == .connecting }
        return HStack(spacing: 8) {
            Text(connected?.name ?? VPNStr.status(.disconnected))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(
                get: { connected != nil },
                set: { on in
                    if on {
                        if let first = vm.connections.first { vm.connect(first.name) }
                    } else if let connected {
                        vm.disconnect(connected.name)
                    }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .accessibilityLabel("VPN")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "lock.shield", color: .indigo, active: anyConnected)
            Text("VPN").font(.headline)
            Spacer()
            HelmStatusDot(active: anyConnected)
        }
    }

    private var anyConnected: Bool {
        vm.connections.contains { $0.status == .connected || $0.status == .connecting }
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        let active = c.status == .connected || c.status == .connecting
        let transitioning = c.status == .connecting || c.status == .disconnecting
        return HStack(spacing: 8) {
            HelmStatusDot(active: active)
            Text(c.name).lineLimit(1)
            Spacer(minLength: 8)
            if transitioning { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(
                get: { active },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .accessibilityLabel(c.name)
        }
    }

}
