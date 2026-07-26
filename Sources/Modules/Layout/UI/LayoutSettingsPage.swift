import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

public struct LayoutSettingsPage: View {
    @ObservedObject private var lvm: LayoutViewModel
    private let store: NamespacedStore

    @State private var automatic: Bool
    @State private var exceptions: String
    @State private var accessibility: PermissionState = .granted
    @State private var onSpace: Bool
    @State private var onReturn: Bool
    @State private var onPunctuation: Bool
    @State private var appRules: [String: Bool]
    @StateObject private var convertKey: HelmHotkeyRecorder
    @StateObject private var undoKey: HelmHotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        lvm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool("automatic", default: true))
        _exceptions = State(initialValue: store.stringArray("exceptions").joined(separator: "\n"))
        _onSpace = State(initialValue: store.bool("onSpace", default: true))
        _onReturn = State(initialValue: store.bool("onReturn", default: true))
        _onPunctuation = State(initialValue: store.bool("onPunctuation", default: true))
        _appRules = State(initialValue: store.boolTable("appRules"))
        _convertKey = StateObject(wrappedValue:
            HelmHotkeyRecorder(store: store, prefix: "convertHotkey"))
        _undoKey = StateObject(wrappedValue:
            HelmHotkeyRecorder(store: store, prefix: "undoHotkey"))
    }

    public var body: some View {
        Form {
            stateSection
            behaviourSection
            triggersSection
            shortcutsSection
            exceptionsSection
            appsSection
        }
        .formStyle(.grouped)
        // A grouped Form caps its content at 704 pt and centres it; capping it
        // keeps the system on its constant-20 branch, matching the page header.
        .frame(maxWidth: 744, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task { accessibility = PermissionCheck.currentAccessibility() }
    }

    /// Three states, not two: watching, paused by secure input, and not
    /// watching at all because the grant is missing.
    private var stateLabel: String {
        if !lvm.state.enabled { return LyStr.notWatching }
        return lvm.state.suspended ? LyStr.paused : LyStr.on
    }

    private var stateTint: Color {
        if !lvm.state.enabled { return .orange }
        return lvm.state.suspended ? .orange : .green
    }

    private var stateSection: some View {
        Section {
            HelmMetricStrip([
                .init(stateLabel, LyStr.metricState, tint: stateTint),
                .init("\(lvm.state.conversionsToday)", LyStr.metricToday),
            ])
        }
    }

    @ViewBuilder private var behaviourSection: some View {
        Section {
            Toggle(LyStr.automatic, isOn: $automatic)
                .onChange(of: automatic) { _, value in write(value, "automatic") }
            Text(LyStr.automaticNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // macOS gives a key tap nothing without this grant, so the switch
            // above would be on and silent.
            if accessibility == .denied {
                HelmPermissionNote(need: .accessibility, text: LyStr.needsAccessibility)
            }
            if lvm.state.suspended {
                Text(LyStr.suspended).font(.caption).foregroundStyle(.secondary)
            }
            if let last = lvm.state.lastConversion {
                LabeledContent(LyStr.lastChange) {
                    HStack(spacing: 8) {
                        Text("\(last.before) → \(last.after)")
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Button(LyStr.undo) { lvm.undoLast() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var triggersSection: some View {
        Section(LyStr.triggers) {
            Text(LyStr.triggersHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(LyStr.onSpace, isOn: $onSpace)
                .onChange(of: onSpace) { _, value in write(value, "onSpace") }
            Toggle(LyStr.onReturn, isOn: $onReturn)
                .onChange(of: onReturn) { _, value in write(value, "onReturn") }
            Toggle(LyStr.onPunctuation, isOn: $onPunctuation)
                .onChange(of: onPunctuation) { _, value in write(value, "onPunctuation") }
        }
    }

    private var shortcutsSection: some View {
        Section(LyStr.shortcuts) {
            // Both are explicit requests, for the two cases the automatic rules
            // cannot cover: a word they declined, and a word they should have.
            HelmHotkeyRow(LyStr.convertAction, recorder: convertKey,
                          taken: HotkeyStatus.isTaken("layout.convert"))
            HelmHotkeyRow(LyStr.undoAction, recorder: undoKey,
                          taken: HotkeyStatus.isTaken("layout.undo"))
        }
    }

    private var exceptionsSection: some View {
        Section(LyStr.exceptions) {
            Text(LyStr.exceptionsHint).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $exceptions)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 90)
                .onChange(of: exceptions) { _, value in
                    write(value.split(separator: "\n").map(String.init), "exceptions")
                }
        }
    }

    @ViewBuilder private var appsSection: some View {
        Section(LyStr.apps) {
            Text(LyStr.appsHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if appRules.isEmpty {
                Text(LyStr.noAppsYet).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(appRules.keys.sorted(), id: \.self) { bundleID in
                appRow(bundleID)
            }
            Button { pickApps() } label: { Label(LyStr.addApp, systemImage: "plus") }
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
        return HStack(spacing: 10) {
            Image(nsImage: info.icon)
                .resizable().frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(info.name).lineLimit(1)
            Spacer(minLength: 12)
            Picker("", selection: ruleBinding(bundleID)) {
                Text(LyStr.ruleOff).tag(false)
                Text(LyStr.ruleOn).tag(true)
            }
            .labelsHidden()
            .fixedSize()
            Button {
                appRules.removeValue(forKey: bundleID)
                write(appRules, "appRules")
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(HelmA11y.remove)
        }
    }

    private func ruleBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(get: { appRules[bundleID] ?? false },
                set: { value in
                    appRules[bundleID] = value
                    write(appRules, "appRules")
                })
    }

    /// A rule is added switched **off**: someone reaching for this list is
    /// almost always trying to stop conversions somewhere, not start them.
    private func pickApps() {
        for bundleID in AppPicker.choose() where appRules[bundleID] == nil {
            appRules[bundleID] = false
        }
        write(appRules, "appRules")
    }

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        lvm.vm.send("settingsChanged")
    }
}
