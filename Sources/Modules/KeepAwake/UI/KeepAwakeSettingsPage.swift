import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// Settings page for the Keep Awake module. The `NamespacedStore` isn't
/// observable, so values are seeded into local `@State` and written through
/// on every change, notifying the engine via `settingsChanged`.
public struct KeepAwakeSettingsPage: View {
    // Observed, not held: the state strip reads isActive and the live
    // conditions, and a plain `let` means SwiftUI never hears them change —
    // the figures froze at whatever they were when the page opened.
    @ObservedObject private var vm: KeepAwakeViewModel
    private let store: NamespacedStore

    @State private var accessibility: PermissionState = .granted
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool
    @State private var appTriggers: [AppTrigger]

    @State private var keepDisplayOn: Bool
    @State private var jiggleEnabled: Bool
    @State private var jiggleIntervalMinutes: Int
    @State private var defaultDurationMinutes: Int

    @State private var clamshellEnabled: Bool

    @State private var batteryGuardEnabled: Bool
    @State private var batteryGuardPercent: Int

    @State private var activeTintColor: String
    @State private var ringTimer: Bool
    @State private var showTimerText: Bool
    @State private var timerTintColor: String
    @State private var customActiveIcon: Bool
    @State private var activeIconShape: String
    @StateObject private var recorder: HelmHotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = KeepAwakeViewModel.shared(vm: vm)
        self.store = store
        _recorder = StateObject(wrappedValue: HelmHotkeyRecorder(store: store))
        _autoExternalDisplay = State(initialValue: store.bool("autoExternalDisplay", default: false))
        _autoPower = State(initialValue: store.bool("autoPower", default: false))
        _appTriggers = State(initialValue: KeepAwakeSettings(store: store).appTriggers)
        _keepDisplayOn = State(initialValue: store.bool("keepDisplayOn", default: false))
        _jiggleEnabled = State(initialValue: store.bool("jiggleEnabled", default: false))
        _jiggleIntervalMinutes = State(initialValue: max(1, store.int("jiggleIntervalMinutes", default: 5)))
        _defaultDurationMinutes = State(initialValue: store.int("defaultDurationMinutes", default: 0))
        _clamshellEnabled = State(initialValue: store.bool("clamshellEnabled", default: false))
        _batteryGuardEnabled = State(initialValue: store.bool("batteryGuardEnabled", default: false))
        _batteryGuardPercent = State(initialValue: store.int("batteryGuardPercent", default: 20))
        _activeTintColor = State(initialValue: MenuBarLook.activeTint(store))
        _ringTimer = State(initialValue: MenuBarLook.ringTimer(store))
        _showTimerText = State(initialValue: MenuBarLook.showTimerText(store))
        _timerTintColor = State(initialValue: MenuBarLook.timerTint(store))
        _customActiveIcon = State(initialValue: MenuBarLook.customIcon(store))
        _activeIconShape = State(initialValue: MenuBarLook.iconShape(store))
    }

    public var body: some View {
        keepAwakeForm
            .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task { accessibility = PermissionCheck.currentAccessibility() }
    }

    /// mm:ss left on the timer, or an em dash when no timer is running.
    /// The same countdown the menu bar and the panel show.
    ///
    /// This was a third spelling with no hours field, so a two-hour session —
    /// one of the offered presets — read "120:00" here while the menu bar read
    /// "2:00:00" at the same instant.
    private var remainingText: String {
        guard let end = vm.endDate else { return "—" }
        return TimerProgress.label(remaining: end.timeIntervalSinceNow)
    }

    /// Seven sections, each its own fragment.
    ///
    /// This was one 123-line expression: more than anyone can hold at once and
    /// more than SwiftUI's type-checker enjoys. `Section` stays the outermost
    /// view of every fragment — a `Form` groups by what its direct children
    /// are, so wrapping one in anything would change the layout — and every
    /// modifier below stays on the `Form` itself, including the store observer
    /// that keeps this page and the panel agreeing.
    private var keepAwakeForm: some View {
        Form {
            sessionSection

            automationSection
            appsSection

            behaviourSection

            menuBarIconSection
            timerSection
            shortcutSection
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        // The panel's ⋯ block writes the same keys; without this the page shows
        // stale values when both are open (the reverse direction already works).
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            if store.changed(note, is: "autoExternalDisplay") {
                autoExternalDisplay = store.bool("autoExternalDisplay", default: false)
            }
            if store.changed(note, is: "autoPower") {
                autoPower = store.bool("autoPower", default: false)
            }
        }
    }

    // MARK: - The sections

    @ViewBuilder private var sessionSection: some View {
        Section {
            // A countdown needs a tick of its own: the engine emits state on
            // change, not once a second, so this figure sat at whatever it
            // read when the page opened. The panel tile solves it the same
            // way.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
            HelmMetricStrip([
                .init(vm.isActive ? KAStr.metricOn : KAStr.metricOff, KAStr.metricState,
                      tint: vm.isActive ? .green : nil),
                .init(remainingText, KAStr.metricTimer, tint: vm.endDate != nil ? .orange : nil),
                // Only the automatic reasons. `activeConditions` also
                // carries `manual` and `timer`, so turning Keep Awake on by
                // hand — with no rule configured at all — used to report
                // "AUTOMATIC 1". The panel already counts it this way.
                .init("\(vm.activeConditions.intersection(["externalDisplay", "power", "app"]).count)",
                      KAStr.metricRules),
            ])
            }
        }
    }

    @ViewBuilder private var automationSection: some View {
        Section(KAStr.automation) {
            Toggle(KAStr.withExternalDisplay, isOn: $autoExternalDisplay)
                .onChange(of: autoExternalDisplay) { _, v in write(v, "autoExternalDisplay") }
            Toggle(KAStr.whileOnPower, isOn: $autoPower)
                .onChange(of: autoPower) { _, v in write(v, "autoPower") }
            Toggle(KAStr.keepAwakeLidClosed, isOn: $clamshellEnabled)
                .onChange(of: clamshellEnabled) { _, v in write(v, "clamshellEnabled") }
            Text(KAStr.adminNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
            // The threshold only means anything with the rule on, so it
            // shares the row instead of floating below it.
            LabeledContent(KAStr.turnOffLowBattery) {
                HStack(spacing: 10) {
                    Stepper(KAStr.belowPercent(batteryGuardPercent),
                            value: $batteryGuardPercent, in: 5...50, step: 5)
                        .disabled(!batteryGuardEnabled)
                        .onChange(of: batteryGuardPercent) { _, v in write(v, "batteryGuardPercent") }
                        .fixedSize()
                    Toggle(KAStr.turnOffLowBattery, isOn: $batteryGuardEnabled)
                        .labelsHidden()
                        .onChange(of: batteryGuardEnabled) { _, v in write(v, "batteryGuardEnabled") }
                }
            }
        }
    }

    @ViewBuilder private var appsSection: some View {
        Section(KAStr.appsSection) {
            appTriggersEditor
        }
    }

    @ViewBuilder private var behaviourSection: some View {
        Section(KAStr.behavior) {
            Toggle(KAStr.keepDisplayOn, isOn: $keepDisplayOn)
                .onChange(of: keepDisplayOn) { _, v in write(v, "keepDisplayOn") }
            // One row: the interval only means anything with the switch on,
            // so it sits beside it instead of on a line of its own.
            LabeledContent(KAStr.movePointer) {
                HStack(spacing: 10) {
                    Stepper(KAStr.everyMinutes(jiggleIntervalMinutes),
                            value: $jiggleIntervalMinutes, in: 1...60)
                        .disabled(!jiggleEnabled)
                        .onChange(of: jiggleIntervalMinutes) { _, v in write(v, "jiggleIntervalMinutes") }
                        .fixedSize()
                    Toggle(KAStr.movePointer, isOn: $jiggleEnabled)
                        .labelsHidden()
                        .onChange(of: jiggleEnabled) { _, v in write(v, "jiggleEnabled") }
                }
            }
            // macOS drops synthetic mouse events from an untrusted app, so
            // without this grant the switch above is on and nothing moves.
            // Say so where the switch is, not only in the app's settings.
            if jiggleEnabled, accessibility == .denied {
                HelmPermissionNote(need: .accessibility,
                                   text: KAStr.pointerNeedsAccessibility)
            }
            Picker(KAStr.defaultDuration, selection: $defaultDurationMinutes) {
                Text(KAStr.min15).tag(15)
                Text(KAStr.oneHour).tag(60)
                Text(KAStr.twoHours).tag(120)
                Text(KAStr.indefinite).tag(0)
            }
            .onChange(of: defaultDurationMinutes) { _, v in write(v, "defaultDurationMinutes") }
        }
    }

    @ViewBuilder private var menuBarIconSection: some View {
        Section(KAStr.menuBarIcon) {
            LabeledContent(KAStr.activeIconColor) { colorSwatches }
            Toggle(KAStr.customActiveIcon, isOn: $customActiveIcon)
                .onChange(of: customActiveIcon) { _, v in write(v, MenuBarLook.Key.customIcon) }
            if customActiveIcon {
                IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                    .onChange(of: activeIconShape) { _, v in write(v, MenuBarLook.Key.iconShape) }
            }
            Text(KAStr.ringColorNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
        }
    }

    @ViewBuilder private var timerSection: some View {
        Section(KAStr.timer) {
            Toggle(KAStr.ringTimer, isOn: $ringTimer)
                .onChange(of: ringTimer) { _, v in write(v, MenuBarLook.Key.ringTimer) }
            Text(KAStr.ringTimerNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
            Toggle(KAStr.showTimerText, isOn: $showTimerText)
                .onChange(of: showTimerText) { _, v in write(v, MenuBarLook.Key.showTimerText) }
            LabeledContent(KAStr.timerColor) { timerColorSwatches }
        }
    }

    @ViewBuilder private var shortcutSection: some View {
        Section(KAStr.globalShortcut) {
            HelmHotkeyRow(KAStr.toggleAction, recorder: recorder,
                          taken: HotkeyStatus.isTaken("keep-awake.toggle"))
        }
    }

    // MARK: - Write-through

    private func write(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.send("settingsChanged")
    }

    // MARK: - App picker

    /// Rows handed to the `Section` one by one, not wrapped in a `VStack`.
    ///
    /// The wrapper made this the only per-app list in Helm without the system's
    /// row padding and hairlines: measured against the identical list in VPN it
    /// came out 13 pt shorter with no separators at all. The form draws both,
    /// and draws them the way every other section is drawn.
    @ViewBuilder
    private var appTriggersEditor: some View {
        if appTriggers.isEmpty {
            Text(KAStr.noAppsYet)
                .font(.callout).foregroundStyle(HelmText.quiet)
        }
            // One row per app: icon, name, when it applies, and the remove
            // button. The condition is a single menu because the two flags are
            // not independent choices — "display and power" means both.
            ForEach(Array(appTriggers.enumerated()), id: \.element.bundleID) { index, trigger in
                HelmAppRuleRow(bundleID: trigger.bundleID) {
                    Picker(AppInfo.resolve(trigger.bundleID).name,
                           selection: conditionBinding(index)) {
                        ForEach(AppTrigger.Condition.allCases, id: \.self) { condition in
                            Text(KAStr.triggerCondition(condition)).tag(condition)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } remove: {
                    appTriggers.remove(at: index)
                    saveTriggers()
                }
        }
        Button {
            pickApp()
        } label: {
            Label(KAStr.addApp, systemImage: "plus")
        }
    }

    private func conditionBinding(_ index: Int) -> Binding<AppTrigger.Condition> {
        Binding(
            get: { appTriggers.indices.contains(index) ? appTriggers[index].condition : .always },
            set: { newValue in
                guard appTriggers.indices.contains(index) else { return }
                appTriggers[index].set(newValue)
                saveTriggers()
            })
    }

    private func saveTriggers() {
        write(AppTriggerRules.encode(appTriggers), "autoAppRules")
    }

    private func pickApp() {
        var added = false
        for bundleID in AppPicker.choose()
        where !appTriggers.contains(where: { $0.bundleID == bundleID }) {
            appTriggers.append(AppTrigger(bundleID: bundleID))
            added = true
        }
        if added { saveTriggers() }
    }

    // MARK: - Color swatches

    private var colorSwatches: some View {
        swatchGrid(selection: activeTintColor) { token in
            activeTintColor = token
            write(token, MenuBarLook.Key.activeTint)
        }
    }

    /// Timer palette: the countdown can stand out from the active colour.
    private var timerColorSwatches: some View {
        // No stored value yet → the active colour is what the timer will use, so
        // show that as the selection.
        swatchGrid(selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            write(token, MenuBarLook.Key.timerTint)
        }
    }

    private func swatchGrid(selection: String, pick: @escaping (String) -> Void) -> some View {
        // 5 columns × 2 rows for the 10 palette colors.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 24, maximum: 44)), count: 5), spacing: 12) {
            ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                let selected = selection == palette.rawValue
                Circle()
                    .fill(palette.color)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette == .white || palette == .yellow || palette == .mint ? .black : .white)
                        }
                    }
                    .overlay {
                        if selected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture { pick(palette.rawValue) }
                    .help(palette.label)
                    .accessibilityElement()
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel(palette.label)
                    .accessibilityAction { pick(palette.rawValue) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Records a global-shortcut combo into the module store and notifies the app's
/// HotkeyManager (via `helmHotkeyChanged`) to (re)register it. Capture uses a
/// local key monitor while the settings window is key — no Accessibility needed.
