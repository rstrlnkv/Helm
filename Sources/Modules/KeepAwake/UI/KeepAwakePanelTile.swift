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
            }
        }
        .helmPanelCard()
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
        Button { showMore.toggle() } label: {
            pillLabel(Image(systemName: "ellipsis"), active: showMore)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMore, arrowEdge: .bottom) { moreControls }
    }

    private func pillLabel(_ content: some View, active: Bool = false) -> some View {
        content
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 16)
            .padding(.vertical, 6)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
    }

    /// Popover with quick automation toggles + a custom timer — kept out of the
    /// tile so the panel never resizes.
    private var moreControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(KAStr.withExternalDisplay, isOn: $autoExternalDisplay)
                .onChange(of: autoExternalDisplay) { _, v in writeSetting(v, "autoExternalDisplay") }
            Toggle(KAStr.whileOnPower, isOn: $autoPower)
                .onChange(of: autoPower) { _, v in writeSetting(v, "autoPower") }
            Divider()
            HStack(spacing: 8) {
                Stepper("\(customMinutes) \(KAStr.minutesUnit)", value: $customMinutes, in: 5...720, step: 5)
                    .font(.subheadline)
                Button(KAStr.start) {
                    vm.send("start", payload: startPayload(customMinutes))
                    showMore = false
                }
                .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .frame(width: 260)
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
