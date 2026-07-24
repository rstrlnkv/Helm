import SwiftUI
import HelmRuntime
import HelmUI

/// Compact tile shown in the shared Helm panel.
public struct KeepAwakePanelTile: View {
    @ObservedObject private var vm: ModuleViewModel
    private let store: NamespacedStore

    @State private var customMinutes: Int
    @State private var showMore = false
    /// Natural height of the ⋯ block, measured once so the disclosure can
    /// animate between 0 and a concrete value.
    @State private var moreHeight: CGFloat = 0
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _autoExternalDisplay = State(initialValue: store.bool("autoExternalDisplay", default: false))
        _autoPower = State(initialValue: store.bool("autoPower", default: false))
        // Last panel choice wins; otherwise the module's default duration
        // (0 = indefinite, which isn't a timer value) and finally 30.
        let remembered = store.int("panelTimerMinutes", default: 0)
        let fallback = store.int("defaultDurationMinutes", default: 0)
        _customMinutes = State(initialValue: remembered > 0 ? remembered : (fallback > 0 ? fallback : 30))
    }

    public var body: some View {
        // spacing 0 + explicit padding: a stack spacing would still insert its
        // gap before the collapsed (zero-height) disclosure, leaving a stray
        // strip under the presets.
        VStack(alignment: .leading, spacing: 0) {
            header
            if vm.isActive, let end = vm.endDate {
                countdownRow(end).padding(.top, 10)
            } else {
                presetRow.padding(.top, 10)
            }
            // Canonical accordion, available in both states: the block always
            // exists, its natural height is measured, and the animation
            // interpolates between 0 and that number (SwiftUI can't animate to
            // `nil`, which left the card and its content out of step).
            moreControls
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { h in
                    if h > 0 { moreHeight = h }
                }
                .frame(height: showMore ? moreHeight : 0, alignment: .top)
                .opacity(showMore ? 1 : 0)
                .clipped()
                .allowsHitTesting(showMore)
        }
        .helmPanelCard()
        // The store isn't observable, so these mirrored values would otherwise
        // drift once the same settings are changed in the Settings window.
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            if store.changed(note, is: "autoExternalDisplay") {
                autoExternalDisplay = store.bool("autoExternalDisplay", default: false)
            }
            if store.changed(note, is: "autoPower") {
                autoPower = store.bool("autoPower", default: false)
            }
        }
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
        // The top gap lives INSIDE the measured block: with stack spacing at 0
        // it must not exist while collapsed, and it should animate in with the
        // rest of the block.
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 10)
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
                    // A menu of sensible durations beats nudging a stepper five
                    // minutes at a time in a 300pt panel.
                    Picker("", selection: $customMinutes) {
                        ForEach(Self.timerOptions, id: \.self) { minutes in
                            Text(Self.durationLabel(minutes)).tag(minutes)
                        }
                    }
                    .onChange(of: customMinutes) { _, v in store.set(v, for: "panelTimerMinutes") }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()

                    Button(KAStr.start) {
                        vm.send("start", payload: startPayload(customMinutes))
                        withAnimation(.easeInOut(duration: 0.24)) { showMore = false }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private static let timerOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]

    /// "45 мин" / "1 ч" / "1 ч 30 мин" — minutes below an hour, hours above.
    private static func durationLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) \(KAStr.minutesUnit)" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) \(KAStr.hoursUnit)"
                      : "\(h) \(KAStr.hoursUnit) \(m) \(KAStr.minutesUnit)"
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
                // Ends the timed session; the header toggle is the all-or-nothing
                // switch, this stops just the countdown.
                Button(KAStr.stop) { vm.send("stop") }
                    .controlSize(.small)
                // The automation controls must stay reachable while a timer runs.
                // A fixed width, not fixedSize(): the pill stretches inside the
                // preset row, so left to itself here it shrank to the glyph.
                morePill.frame(width: 46)
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
