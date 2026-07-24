import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmUI

/// Settings page for the Keep Awake module. The `NamespacedStore` isn't
/// observable, so values are seeded into local `@State` and written through
/// on every change, notifying the engine via `settingsChanged`.
public struct KeepAwakeSettingsPage: View {
    private let vm: ModuleViewModel
    private let store: NamespacedStore

    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool
    @State private var autoApps: [String]

    @State private var keepDisplayOn: Bool
    @State private var jiggleEnabled: Bool
    @State private var jiggleIntervalMinutes: Int
    @State private var defaultDurationMinutes: Int

    @State private var clamshellEnabled: Bool

    @State private var batteryGuardEnabled: Bool
    @State private var batteryGuardPercent: Int

    @State private var activeTintColor: String
    @StateObject private var recorder: HotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _recorder = StateObject(wrappedValue: HotkeyRecorder(store: store))
        _autoExternalDisplay = State(initialValue: store.bool("autoExternalDisplay", default: false))
        _autoPower = State(initialValue: store.bool("autoPower", default: false))
        _autoApps = State(initialValue: store.stringArray("autoApps"))
        _keepDisplayOn = State(initialValue: store.bool("keepDisplayOn", default: false))
        _jiggleEnabled = State(initialValue: store.bool("jiggleEnabled", default: false))
        _jiggleIntervalMinutes = State(initialValue: max(1, store.int("jiggleIntervalMinutes", default: 5)))
        _defaultDurationMinutes = State(initialValue: store.int("defaultDurationMinutes", default: 0))
        _clamshellEnabled = State(initialValue: store.bool("clamshellEnabled", default: false))
        _batteryGuardEnabled = State(initialValue: store.bool("batteryGuardEnabled", default: false))
        _batteryGuardPercent = State(initialValue: store.int("batteryGuardPercent", default: 20))
        _activeTintColor = State(initialValue: store.string("activeTintColor", default: "green"))
    }

    public var body: some View {
        Form {
            Section("Automation") {
                Toggle("Keep awake with external display", isOn: $autoExternalDisplay)
                    .onChange(of: autoExternalDisplay) { _, v in write(v, "autoExternalDisplay") }
                Toggle("Keep awake while on power", isOn: $autoPower)
                    .onChange(of: autoPower) { _, v in write(v, "autoPower") }
            }

            Section("Apps that keep the Mac awake") {
                appTriggersEditor
            }

            Section("Behavior") {
                Toggle("Keep display on", isOn: $keepDisplayOn)
                    .onChange(of: keepDisplayOn) { _, v in write(v, "keepDisplayOn") }
                Toggle("Move pointer periodically", isOn: $jiggleEnabled)
                    .onChange(of: jiggleEnabled) { _, v in write(v, "jiggleEnabled") }
                Stepper("Every \(jiggleIntervalMinutes) min", value: $jiggleIntervalMinutes, in: 1...60)
                    .disabled(!jiggleEnabled)
                    .onChange(of: jiggleIntervalMinutes) { _, v in write(v, "jiggleIntervalMinutes") }
                Picker("Default duration", selection: $defaultDurationMinutes) {
                    Text("15 min").tag(15)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("Indefinite").tag(0)
                }
                .onChange(of: defaultDurationMinutes) { _, v in write(v, "defaultDurationMinutes") }
            }

            Section("Global shortcut") {
                HStack(spacing: 10) {
                    Text("Toggle Keep Awake")
                    Spacer()
                    if recorder.recording {
                        Text("Press keys…").foregroundStyle(.secondary)
                    } else if !recorder.label.isEmpty {
                        Text(recorder.label).font(.body.monospaced())
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                    Button(recorder.recording ? "Cancel" : "Record") {
                        recorder.recording ? recorder.stop() : recorder.startRecording()
                    }
                    .controlSize(.small)
                    if !recorder.label.isEmpty && !recorder.recording {
                        Button("Clear") { recorder.clear() }
                            .controlSize(.small)
                    }
                }
            }

            Section("Closed lid") {
                Toggle("Keep awake with the lid closed", isOn: $clamshellEnabled)
                    .onChange(of: clamshellEnabled) { _, v in write(v, "clamshellEnabled") }
                Text("Requires an admin password once (uses pmset).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Battery") {
                Toggle("Turn off on low battery", isOn: $batteryGuardEnabled)
                    .onChange(of: batteryGuardEnabled) { _, v in write(v, "batteryGuardEnabled") }
                Stepper("Below \(batteryGuardPercent)%", value: $batteryGuardPercent, in: 5...50, step: 5)
                    .disabled(!batteryGuardEnabled)
                    .onChange(of: batteryGuardPercent) { _, v in write(v, "batteryGuardPercent") }
            }

            Section("Active icon color") {
                colorSwatches
                Text("Menu-bar ring color while active (white when idle).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Write-through

    private func write(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.send("settingsChanged")
    }

    // MARK: - App picker

    private var appTriggersEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(autoApps, id: \.self) { bundleID in
                let info = Self.appInfo(bundleID)
                HStack(spacing: 10) {
                    Image(nsImage: info.icon)
                        .resizable().frame(width: 20, height: 20)
                    Text(info.name)
                    Spacer()
                    Button {
                        autoApps.removeAll { $0 == bundleID }
                        write(autoApps, "autoApps")
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                pickApp()
            } label: {
                Label("Add app…", systemImage: "plus")
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        var added = false
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !autoApps.contains(bundleID) else { continue }
            autoApps.append(bundleID)
            added = true
        }
        if added { write(autoApps, "autoApps") }
    }

    private static func appInfo(_ bundleID: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }

    // MARK: - Color swatches

    private var colorSwatches: some View {
        // 5 columns × 2 rows for the 10 palette colors.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 24, maximum: 44)), count: 5), spacing: 12) {
            ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                let selected = activeTintColor == palette.rawValue
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
                    .onTapGesture {
                        activeTintColor = palette.rawValue
                        write(palette.rawValue, "activeTintColor")
                    }
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
