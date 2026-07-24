import SwiftUI
import HelmUI

/// Compact tile shown in the shared Helm panel.
public struct KeepAwakePanelTile: View {
    @ObservedObject private var vm: ModuleViewModel
    @State private var customMinutes = 30
    @State private var showCustom = false

    public init(vm: ModuleViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if vm.isActive, let end = vm.endDate {
                countdownRow(end)
            } else {
                presetRow
                if showCustom { customRow }
            }
        }
        .helmPanelCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "moon.zzz.fill", color: .orange, active: vm.isActive)
            VStack(alignment: .leading, spacing: 1) {
                Text(KAStr.moduleName).font(.headline)
                if let subtitle = activeSubtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { vm.isActive }, set: { _ in vm.send("toggle") }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    /// Small line under the title while active: the auto conditions (and a
    /// lid-closed hint), shown next to the toggle instead of at the bottom.
    private var activeSubtitle: String? {
        guard vm.isActive else { return nil }
        var parts: [String] = []
        if !vm.activeConditions.isEmpty { parts.append(conditionsCaption) }
        if vm.clamshellActive { parts.append(KAStr.lidClosed) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Idle: presets + custom

    private var presetRow: some View {
        HStack(spacing: 6) {
            presetPill("15m", 15)
            presetPill("1h", 60)
            presetPill("2h", 120)
            presetPill("∞", 0)
            customPill
        }
    }

    private var customPill: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { showCustom.toggle() } } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(showCustom ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func presetPill(_ label: String, _ minutes: Int) -> some View {
        Button {
            vm.send("start", payload: startPayload(minutes))
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var customRow: some View {
        HStack(spacing: 8) {
            Stepper("\(customMinutes) \(KAStr.minutesUnit)", value: $customMinutes, in: 5...720, step: 5)
                .font(.subheadline)
            Button(KAStr.start) {
                vm.send("start", payload: startPayload(customMinutes))
            }
            .controlSize(.small)
        }
    }

    // MARK: - Active: countdown

    private func countdownRow(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(.secondary)
                Text(Self.formatRemaining(remaining))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Button("+15m") {
                    let newMinutes = Int(ceil(remaining / 60)) + 15
                    vm.send("start", payload: startPayload(newMinutes))
                }
                .controlSize(.small)
            }
        }
    }

    private static func formatRemaining(_ s: TimeInterval) -> String {
        let t = Int(s), h = Int(t) / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Active: auto conditions

    private var conditionsCaption: String {
        vm.activeConditions
            .map(KAStr.condition)
            .sorted()
            .joined(separator: ", ")
    }
}

private func startPayload(_ minutes: Int) -> Data {
    struct P: Codable { let minutes: Int }
    return (try? JSONEncoder().encode(P(minutes: minutes))) ?? Data()
}
