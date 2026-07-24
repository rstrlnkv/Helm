import SwiftUI
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
    @State private var newAppBundleID: String = ""

    @State private var keepDisplayOn: Bool
    @State private var jiggleEnabled: Bool
    @State private var jiggleIntervalMinutes: Int
    @State private var defaultDurationMinutes: Int

    @State private var clamshellEnabled: Bool

    @State private var batteryGuardEnabled: Bool
    @State private var batteryGuardPercent: Int

    @State private var activeTintColor: String

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
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
                    .onChange(of: autoExternalDisplay) { _, v in
                        store.set(v, for: "autoExternalDisplay")
                        vm.send("settingsChanged")
                    }
                Toggle("Keep awake on power", isOn: $autoPower)
                    .onChange(of: autoPower) { _, v in
                        store.set(v, for: "autoPower")
                        vm.send("settingsChanged")
                    }
                appTriggersEditor
            }

            Section("Behavior") {
                Toggle("Keep display on", isOn: $keepDisplayOn)
                    .onChange(of: keepDisplayOn) { _, v in
                        store.set(v, for: "keepDisplayOn")
                        vm.send("settingsChanged")
                    }
                Toggle("Move pointer periodically", isOn: $jiggleEnabled)
                    .onChange(of: jiggleEnabled) { _, v in
                        store.set(v, for: "jiggleEnabled")
                        vm.send("settingsChanged")
                    }
                Stepper("Every \(jiggleIntervalMinutes) min", value: $jiggleIntervalMinutes, in: 1...60)
                    .disabled(!jiggleEnabled)
                    .onChange(of: jiggleIntervalMinutes) { _, v in
                        store.set(v, for: "jiggleIntervalMinutes")
                        vm.send("settingsChanged")
                    }
                Picker("Default duration", selection: $defaultDurationMinutes) {
                    Text("15m").tag(15)
                    Text("1h").tag(60)
                    Text("2h").tag(120)
                    Text("∞").tag(0)
                }
                .onChange(of: defaultDurationMinutes) { _, v in
                    store.set(v, for: "defaultDurationMinutes")
                    vm.send("settingsChanged")
                }
            }

            Section("Closed lid") {
                Toggle("Keep awake with lid closed", isOn: $clamshellEnabled)
                    .onChange(of: clamshellEnabled) { _, v in
                        store.set(v, for: "clamshellEnabled")
                        vm.send("settingsChanged")
                    }
                Text("Requires admin permission once (uses pmset).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Battery") {
                Toggle("Turn off on low battery", isOn: $batteryGuardEnabled)
                    .onChange(of: batteryGuardEnabled) { _, v in
                        store.set(v, for: "batteryGuardEnabled")
                        vm.send("settingsChanged")
                    }
                Stepper("Below \(batteryGuardPercent)%", value: $batteryGuardPercent, in: 5...50, step: 5)
                    .disabled(!batteryGuardEnabled)
                    .onChange(of: batteryGuardPercent) { _, v in
                        store.set(v, for: "batteryGuardPercent")
                        vm.send("settingsChanged")
                    }
            }

            Section("Appearance") {
                Picker("Active color", selection: $activeTintColor) {
                    ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                        Label {
                            Text(palette.rawValue.capitalized)
                        } icon: {
                            Circle()
                                .fill(palette.color)
                                .frame(width: 10, height: 10)
                        }
                        .tag(palette.rawValue)
                    }
                }
                .onChange(of: activeTintColor) { _, v in
                    store.set(v, for: "activeTintColor")
                    vm.send("settingsChanged")
                }
                Text("Menu-bar ring color while active (inactive = white).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appTriggersEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Bundle ID (e.g. com.apple.Terminal)", text: $newAppBundleID)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !autoApps.contains(trimmed) else { return }
                    autoApps.append(trimmed)
                    newAppBundleID = ""
                    store.set(autoApps, for: "autoApps")
                    vm.send("settingsChanged")
                }
                .disabled(newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !autoApps.isEmpty {
                ForEach(autoApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .font(.caption.monospaced())
                        Spacer()
                        Button {
                            autoApps.removeAll { $0 == bundleID }
                            store.set(autoApps, for: "autoApps")
                            vm.send("settingsChanged")
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
