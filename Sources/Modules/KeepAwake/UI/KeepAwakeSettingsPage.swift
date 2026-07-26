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
    private let vm: ModuleViewModel
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
    @StateObject private var recorder: HotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _recorder = StateObject(wrappedValue: HotkeyRecorder(store: store))
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
        _activeTintColor = State(initialValue: store.string("activeTintColor", default: "orange"))
        _ringTimer = State(initialValue: store.bool("ringTimer", default: true))
        _showTimerText = State(initialValue: store.bool("showTimerText", default: false))
        _timerTintColor = State(initialValue: store.string("timerTintColor", default: "red"))
        _customActiveIcon = State(initialValue: store.bool("customActiveIcon", default: false))
        _activeIconShape = State(initialValue: store.string("activeIconShape", default: "ring"))
    }

    public var body: some View {
        keepAwakeForm
            .task { accessibility = PermissionCheck.currentAccessibility() }
    }

    /// mm:ss left on the timer, or an em dash when no timer is running.
    private var remainingText: String {
        guard let end = vm.endDate else { return "—" }
        let left = max(Int(end.timeIntervalSinceNow), 0)
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    private var keepAwakeForm: some View {
        Form {
            Section {
                HelmMetricStrip([
                    .init(vm.isActive ? KAStr.metricOn : KAStr.metricOff, KAStr.metricState,
                          tint: vm.isActive ? .green : nil),
                    .init(remainingText, KAStr.metricTimer, tint: vm.endDate != nil ? .orange : nil),
                    .init("\(vm.activeConditions.count)", KAStr.metricRules),
                ])
            }

            Section(KAStr.automation) {
                Toggle(KAStr.withExternalDisplay, isOn: $autoExternalDisplay)
                    .onChange(of: autoExternalDisplay) { _, v in write(v, "autoExternalDisplay") }
                Toggle(KAStr.whileOnPower, isOn: $autoPower)
                    .onChange(of: autoPower) { _, v in write(v, "autoPower") }
                Toggle(KAStr.keepAwakeLidClosed, isOn: $clamshellEnabled)
                    .onChange(of: clamshellEnabled) { _, v in write(v, "clamshellEnabled") }
                Text(KAStr.adminNote)
                    .font(.caption).foregroundStyle(.secondary)
                // The threshold only means anything with the rule on, so it
                // shares the row instead of floating below it.
                LabeledContent(KAStr.turnOffLowBattery) {
                    HStack(spacing: 10) {
                        Stepper(KAStr.belowPercent(batteryGuardPercent),
                                value: $batteryGuardPercent, in: 5...50, step: 5)
                            .disabled(!batteryGuardEnabled)
                            .onChange(of: batteryGuardPercent) { _, v in write(v, "batteryGuardPercent") }
                            .fixedSize()
                        Toggle("", isOn: $batteryGuardEnabled)
                            .labelsHidden()
                            .onChange(of: batteryGuardEnabled) { _, v in write(v, "batteryGuardEnabled") }
                    }
                }
            }

            Section(KAStr.appsSection) {
                appTriggersEditor
            }

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
                        Toggle("", isOn: $jiggleEnabled)
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

            Section(KAStr.menuBarIcon) {
                LabeledContent(KAStr.activeIconColor) { colorSwatches }
                Toggle(KAStr.customActiveIcon, isOn: $customActiveIcon)
                    .onChange(of: customActiveIcon) { _, v in write(v, "customActiveIcon") }
                if customActiveIcon {
                    IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                        .onChange(of: activeIconShape) { _, v in write(v, "activeIconShape") }
                }
                Text(KAStr.ringColorNote)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(KAStr.timer) {
                Toggle(KAStr.ringTimer, isOn: $ringTimer)
                    .onChange(of: ringTimer) { _, v in write(v, "ringTimer") }
                Text(KAStr.ringTimerNote)
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(KAStr.showTimerText, isOn: $showTimerText)
                    .onChange(of: showTimerText) { _, v in write(v, "showTimerText") }
                LabeledContent(KAStr.timerColor) { timerColorSwatches }
            }

            Section(KAStr.globalShortcut) {
                HStack(spacing: 10) {
                    Text(KAStr.toggleAction)
                    Spacer()
                    if recorder.recording {
                        Text(KAStr.pressKeys).foregroundStyle(.secondary)
                    } else if !recorder.label.isEmpty {
                        Text(recorder.label).font(.body.monospaced())
                    } else {
                        Text(KAStr.none).foregroundStyle(.secondary)
                    }
                    Button(recorder.recording ? KAStr.cancel : KAStr.record) {
                        recorder.recording ? recorder.stop() : recorder.startRecording()
                    }
                    .controlSize(.small)
                    if !recorder.label.isEmpty && !recorder.recording {
                        Button(KAStr.clear) { recorder.clear() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    // MARK: - Write-through

    private func write(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.send("settingsChanged")
    }

    // MARK: - App picker

    private var appTriggersEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(appTriggers.enumerated()), id: \.element.bundleID) { index, trigger in
                let info = AppInfo.resolve(trigger.bundleID)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(nsImage: info.icon)
                            .resizable().frame(width: 20, height: 20)
                        Text(info.name)
                        Spacer()
                        Button {
                            appTriggers.remove(at: index)
                            saveTriggers()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    // Narrowing is optional: with both off the app holds the
                    // Mac awake whenever it runs, which is what it did before.
                    Toggle(KAStr.onlyWithExternalDisplay,
                           isOn: binding(index, \.needsExternalDisplay))
                        .font(.callout)
                    Toggle(KAStr.onlyOnPower, isOn: binding(index, \.needsPower))
                        .font(.callout)
                }
            }
            Button {
                pickApp()
            } label: {
                Label(KAStr.addApp, systemImage: "plus")
            }
        }
    }

    private func binding(_ index: Int,
                         _ path: WritableKeyPath<AppTrigger, Bool>) -> Binding<Bool> {
        Binding(
            get: { appTriggers.indices.contains(index) ? appTriggers[index][keyPath: path] : false },
            set: { newValue in
                guard appTriggers.indices.contains(index) else { return }
                appTriggers[index][keyPath: path] = newValue
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
            write(token, "activeTintColor")
        }
    }

    /// Timer palette: the countdown can stand out from the active colour.
    private var timerColorSwatches: some View {
        // No stored value yet → the active colour is what the timer will use, so
        // show that as the selection.
        swatchGrid(selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            write(token, "timerTintColor")
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
                    .help(palette.rawValue.capitalized)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Records a global-shortcut combo into the module store and notifies the app's
/// HotkeyManager (via `helmHotkeyChanged`) to (re)register it. Capture uses a
/// local key monitor while the settings window is key — no Accessibility needed.
@MainActor final class HotkeyRecorder: ObservableObject {
    @Published var label: String
    @Published var recording = false

    private let store: NamespacedStore
    private var monitor: Any?

    init(store: NamespacedStore) {
        self.store = store
        self.label = store.string("hotkeyLabel", default: "")
    }

    func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil   // swallow the keystroke while recording
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false
    }

    func clear() {
        store.set(-1, for: "hotkeyKeyCode")
        store.set(0, for: "hotkeyModifiers")
        store.set("", for: "hotkeyLabel")
        label = ""
        NotificationCenter.default.post(name: Notification.Name("helmHotkeyChanged"), object: nil)
    }

    private func capture(_ event: NSEvent) {
        let flags = event.modifierFlags
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        guard carbon != 0 else { return }   // require at least one modifier

        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        let text = modifierSymbols(flags) + key
        store.set(Int(event.keyCode), for: "hotkeyKeyCode")
        store.set(carbon, for: "hotkeyModifiers")
        store.set(text, for: "hotkeyLabel")
        label = text
        stop()
        NotificationCenter.default.post(name: Notification.Name("helmHotkeyChanged"), object: nil)
    }

    private func modifierSymbols(_ f: NSEvent.ModifierFlags) -> String {
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s
    }
}
