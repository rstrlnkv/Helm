import SwiftUI
import HelmRuntime
import HelmUI

/// Compact tile shown in the shared Helm panel.
public struct KeepAwakePanelTile: View {
    @ObservedObject private var vm: ModuleViewModel
    private let store: NamespacedStore

    @State private var customMinutes = 30
    @State private var showMore = false
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _autoExternalDisplay = State(initialValue: store.bool("autoExternalDisplay", default: false))
        _autoPower = State(initialValue: store.bool("autoPower", default: false))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if vm.isActive, let end = vm.endDate {
                countdownRow(end)
            } else {
                presetRow
                if showMore {
                    // One fade for the whole block: per-row cascades made the
                    // rows pop in one by one, each half-clipped by the growing card.
                    moreControls.transition(.opacity)
                }
            }
        }
        .helmPanelCard()
        // Clip AFTER the card's padding, to the card's own shape: content that
        // is already at full height while the card is still growing must not
        // paint over the neighbouring tile. Clipping before the padding (an
        // earlier attempt) cut the preset pills instead.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Header

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
                .accessibilityLabel(KAStr.moduleName)
        }
    }

    /// Line under the title while active: the auto conditions and a lid hint,
    /// shown next to the toggle instead of at the bottom.
    private var activeSubtitle: String? {
        guard vm.isActive else { return nil }
        var parts: [String] = []
        if !vm.activeConditions.isEmpty {
            parts.append(vm.activeConditions.map(KAStr.condition).sorted().joined(separator: ", "))
        }
        if vm.clamshellActive { parts.append(KAStr.lidClosed) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Presets + more

    private var presetRow: some View {
        HStack(spacing: 6) {
            presetPill("15m", 15)
            presetPill("1h", 60)
            presetPill("2h", 120)
            presetPill("∞", 0)
            morePill
        }
    }

    private func presetPill(_ label: String, _ minutes: Int) -> some View {
        Button {
            vm.send("start", payload: startPayload(minutes))
        } label: {
            pillLabel(Text(label))
        }
        .buttonStyle(.plain)
    }

    private var morePill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) { showMore.toggle() }
        } label: {
            pillLabel(Image(systemName: "ellipsis"), active: showMore)
        }
        .buttonStyle(.plain)
    }

    private func pillLabel(_ content: some View, active: Bool = false) -> some View {
        content
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 16)
            .padding(.vertical, 6)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
    }

    /// Quick automation toggles + a custom timer, revealed inline under the
    /// presets — same disclosure language as the panel's Utilities section
    /// (rows fade in cascading, the card grows downward).
    private var moreControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            // Label left, control hard against the right edge — one alignment
            // line for every row in the block.
            settingRow(KAStr.withExternalDisplay) {
                Toggle("", isOn: $autoExternalDisplay)
                    .onChange(of: autoExternalDisplay) { _, v in writeSetting(v, "autoExternalDisplay") }
            }

            settingRow(KAStr.whileOnPower) {
                Toggle("", isOn: $autoPower)
                    .onChange(of: autoPower) { _, v in writeSetting(v, "autoPower") }
            }

            settingRow(KAStr.timer) {
                HStack(spacing: 6) {
                    Text("\(customMinutes) \(KAStr.minutesUnit)")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $customMinutes, in: 5...720, step: 5)
                        .labelsHidden()
                        .controlSize(.mini)
                    Button(KAStr.start) {
                        vm.send("start", payload: startPayload(customMinutes))
                        withAnimation(.easeInOut(duration: 0.24)) { showMore = false }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// Label on the left, trailing control(s) pinned to the right edge.
    private func settingRow<Control: View>(_ title: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            control()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func writeSetting(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.send("settingsChanged")
    }

    // MARK: - Active countdown

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
}

private func startPayload(_ minutes: Int) -> Data {
    struct P: Codable { let minutes: Int }
    return (try? JSONEncoder().encode(P(minutes: minutes))) ?? Data()
}
