import SwiftUI
import HelmUI

/// Compact tile shown in the shared Helm panel.
public struct KeepAwakePanelTile: View {
    @ObservedObject private var vm: ModuleViewModel

    public init(vm: ModuleViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            presetRow
            if vm.isActive {
                captionRow
            }
        }
        .helmPanelCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "moon.zzz.fill", color: .orange, active: vm.isActive)
            Text("Keep Awake").font(.headline)
            Spacer()
            Toggle("", isOn: Binding(get: { vm.isActive }, set: { _ in vm.send("toggle") }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            presetButton(label: "15m", minutes: 15)
            presetButton(label: "1h", minutes: 60)
            presetButton(label: "2h", minutes: 120)
            presetButton(label: "∞", minutes: 0)
        }
    }

    private func presetButton(label: String, minutes: Int) -> some View {
        Button(label) {
            vm.send("start", payload: startPayload(minutes))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var captionRow: some View {
        if !vm.activeConditions.isEmpty {
            Text(conditionsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if vm.clamshellActive {
            Text("Lid closed — keeping display awake")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var conditionsCaption: String {
        vm.activeConditions
            .map(Self.readableCondition)
            .sorted()
            .joined(separator: ", ")
    }

    private static func readableCondition(_ wireName: String) -> String {
        switch wireName {
        case "manual": return "Manual"
        case "timer": return "Timer"
        case "externalDisplay": return "External display"
        case "power": return "Power"
        case "app": return "App"
        default: return wireName
        }
    }
}

private func startPayload(_ minutes: Int) -> Data {
    struct P: Codable { let minutes: Int }
    return (try? JSONEncoder().encode(P(minutes: minutes))) ?? Data()
}
