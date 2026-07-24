import SwiftUI
import HelmUI
import Module_VPN_Engine

/// Compact tile shown in the shared Helm panel.
public struct VPNPanelTile: View {
    @ObservedObject private var vm: VPNViewModel

    public init(vm: VPNViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if vm.connections.isEmpty {
                Text("No VPNs configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.connections.count <= 1 {
                defaultRow
            } else {
                connectionsList
            }
        }
        .helmPanelCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "lock.shield", color: .indigo, active: isDefaultActive)
            Text("VPN").font(.headline)
            Spacer()
            if vm.runState == "working" {
                ProgressView().controlSize(.small)
            }
            statusDot(for: defaultStatus)
        }
    }

    private var isDefaultActive: Bool {
        defaultStatus == .connected || defaultStatus == .connecting
    }

    private var defaultConnection: VPNConnection? {
        vm.connections.first(where: { $0.name == vm.defaultName }) ?? vm.connections.first
    }

    private var defaultStatus: VPNStatus {
        defaultConnection?.status ?? .unknown
    }

    private var defaultRow: some View {
        Button {
            vm.toggleDefault()
        } label: {
            HStack {
                Text(defaultConnection?.name ?? "VPN")
                Spacer()
                Text(statusText(defaultStatus))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDefaultActive ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.connections) { connection in
                Button {
                    if connection.status == .connected || connection.status == .connecting {
                        vm.disconnect(connection.name)
                    } else {
                        vm.connect(connection.name)
                    }
                } label: {
                    HStack {
                        statusDot(for: connection.status)
                        Text(connection.name)
                        Spacer()
                        Text(statusText(connection.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusDot(for status: VPNStatus) -> some View {
        Circle()
            .fill(status == .connected || status == .connecting ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
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
}
