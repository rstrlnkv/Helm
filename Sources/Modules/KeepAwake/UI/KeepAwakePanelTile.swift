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
    @State private var showCustomTime = false
    @State private var customMinutesText = ""
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
                // Composite before fading. Animating `.opacity` puts the block
                // in an offscreen layer, and hierarchical colours (.secondary
                // on the "Automation" heading) resolve differently inside one;
                // when the layer is dropped at the end of the animation the
                // colour jumps. A permanent compositing group keeps the
                // rendering path identical during and after the animation.
                .compositingGroup()
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
                // Orange switch = an automation rule (display/power/app) is
                // holding the session, so flipping it off may not stick.
                .tint(autoDriven ? .orange : nil)
                .accessibilityLabel(KAStr.moduleName)
        }
    }

    /// True while an automation condition (not just manual/timer) is active.
    private var autoDriven: Bool {
        !vm.activeConditions.isDisjoint(with: ["externalDisplay", "power", "app"])
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
            presetPill(Self.durationLabel(15, compact: true), 15)
            presetPill(Self.durationLabel(60, compact: true), 60)
            presetPill(Self.durationLabel(120, compact: true), 120)
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
            withAnimation(HelmMotion.disclosure) { showMore.toggle() }
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
        // Order follows intent: the custom timer continues the preset row above
        // it (same action, arbitrary length), then the automation rules — which
        // are standing settings, not actions — sit under their own heading so
        // their labels read as conditions.
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 10)

            settingRow(KAStr.timer) {
                HStack(spacing: 6) {
                    // A menu of sensible durations beats nudging a stepper five
                    // minutes at a time in a 300pt panel.
                    Menu {
                        ForEach(Self.timerOptions, id: \.self) { minutes in
                            Button(Self.durationLabel(minutes)) { setMinutes(minutes) }
                        }
                        Divider()
                        Button(KAStr.customTime) {
                            customMinutesText = String(customMinutes)
                            showCustomTime = true
                        }
                    } label: {
                        Text(Self.durationLabel(customMinutes))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .popover(isPresented: $showCustomTime, arrowEdge: .bottom) { customTimeEditor }

                    Button(KAStr.start) {
                        vm.send("start", payload: startPayload(customMinutes))
                        withAnimation(HelmMotion.disclosure) { showMore = false }
                    }
                    .controlSize(.small)
                }
            }

            Text(KAStr.automation)
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 2)

            settingRow(KAStr.onExternalDisplay) {
                Toggle("", isOn: $autoExternalDisplay)
                    .onChange(of: autoExternalDisplay) { _, v in writeSetting(v, "autoExternalDisplay") }
            }

            settingRow(KAStr.onPower) {
                Toggle("", isOn: $autoPower)
                    .onChange(of: autoPower) { _, v in writeSetting(v, "autoPower") }
            }
        }
    }

    // Round durations only: a compound label ("1 ч 30 мин") forced the menu wide
    // enough to push Start out of the card.
    private static let timerOptions = [5, 10, 15, 20, 30, 45, 60, 120, 180, 240]

    /// "45 мин" / "1 ч" / "1 ч 30 мин" — minutes below an hour, hours above.
    /// `compact` uses single-letter units, for the narrow preset pills.
    private static func durationLabel(_ minutes: Int, compact: Bool = false) -> String {
        let mUnit = compact ? KAStr.minutesUnitShort : KAStr.minutesUnit
        let hUnit = compact ? KAStr.hoursUnitShort : KAStr.hoursUnit
        guard minutes >= 60 else { return "\(minutes) \(mUnit)" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) \(hUnit)" : "\(h) \(hUnit) \(m) \(mUnit)"
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

    private func setMinutes(_ minutes: Int) {
        customMinutes = minutes
        store.set(minutes, for: "panelTimerMinutes")
    }

    /// Free-form duration entry, opened from the menu's "Custom…" entry.
    private var customTimeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(KAStr.customTimeTitle)
                .font(.subheadline.weight(.semibold))
            // One line: field, unit, confirm — instead of three separate rows.
            HStack(spacing: 6) {
                TextField("", text: $customMinutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(applyCustomTime)
                Text(KAStr.minutesUnit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(KAStr.done, action: applyCustomTime)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 218)
    }

    private func applyCustomTime() {
        // Clamped to the engine's sane range; junk input keeps the old value.
        if let entered = Int(customMinutesText.trimmingCharacters(in: .whitespaces)), entered > 0 {
            setMinutes(min(720, max(1, entered)))
        }
        showCustomTime = false
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
                Button("+" + Self.durationLabel(15, compact: true)) {
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
