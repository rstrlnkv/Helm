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
    @State private var audible: Bool
    @State private var indicator: Bool
    @State private var badgeStyle: BadgeStyle
    @State private var badgeSize: MenuBarIconSize
    @State private var showingIntro = false
    @StateObject private var convertKey: HelmHotkeyRecorder
    @StateObject private var undoKey: HelmHotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        lvm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool("automatic", default: true))
        _exceptions = State(initialValue: store.stringArray("exceptions").joined(separator: "\n"))
        _onSpace = State(initialValue: store.bool("onSpace", default: ConversionTriggers.default.onSpace))
        _onReturn = State(initialValue: store.bool("onReturn", default: ConversionTriggers.default.onReturn))
        _onPunctuation = State(initialValue: store.bool("onPunctuation", default: ConversionTriggers.default.onPunctuation))
        _appRules = State(initialValue: store.boolTable("appRules"))
        _audible = State(initialValue: store.bool("audible", default: false))
        _indicator = State(initialValue: store.bool("indicator", default: false))
        _badgeStyle = State(initialValue:
            BadgeStyle.from(store.string("badgeStyle", default: BadgeStyle.default.rawValue)))
        _badgeSize = State(initialValue:
            MenuBarIconSize(rawValue: store.string("badgeSize", default: "small")) ?? .small)
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
            tryItSection
            exceptionsSection
            indicatorSection
            appsSection
        }
        .formStyle(.grouped)
        // A grouped Form caps its content at 704 pt and centres it; capping it
        // keeps the system on its constant-20 branch, matching the page header.
        .frame(maxWidth: 744, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task {
            accessibility = PermissionCheck.currentAccessibility()
            // Once, and to the person who came looking for the module — rather
            // than in a queue of notices at first launch that nobody reads.
            if !store.bool("introSeen", default: false) { showingIntro = true }
        }
        .sheet(isPresented: $showingIntro) {
            LayoutIntro {
                store.set(true, for: "introSeen")
                showingIntro = false
            }
        }
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
            Toggle(LyStr.audible, isOn: $audible)
                .onChange(of: audible) { _, value in write(value, "audible") }
            // macOS gives a key tap nothing without this grant, so the switch
            // above would be on and silent.
            if accessibility == .denied {
                HelmPermissionNote(need: .accessibility, text: LyStr.needsAccessibility)
            }
            if lvm.state.suspended {
                Text(LyStr.suspended).font(.caption).foregroundStyle(.secondary)
            }
            if let last = lvm.state.lastConversion {
                // Shown, not offered. Undoing has to happen in the app the
                // conversion happened in, and reaching a button here means
                // bringing Helm forward — which is both the wrong app and, as a
                // click, the thing that ends the chance to undo. A button that
                // cannot fire is worse than no button.
                LabeledContent(LyStr.lastChange) {
                    HStack(spacing: 8) {
                        Text("\(last.before) → \(last.after)")
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        // Unlike undoing, this works from anywhere: it changes
                        // a list, not somebody else's text.
                        Button(LyStr.neverThisWord) { addException(last.before) }
                            .controlSize(.small)
                            .disabled(exceptionsContain(last.before))
                    }
                }
                Text(LyStr.undoHint).font(.caption).foregroundStyle(.secondary)
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

    /// A place to try it without risking anything that was being written.
    private var tryItSection: some View {
        Section(LyStr.tryIt) { LayoutTestField() }
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

    @ViewBuilder private var indicatorSection: some View {
        Section(LyStr.indicator) {
            Text(LyStr.indicatorHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(LyStr.indicatorShow, isOn: $indicator)
                .onChange(of: indicator) { _, value in write(value, "indicator") }
            if indicator {
                Picker(LyStr.badgeStyle, selection: $badgeStyle) {
                    ForEach(BadgeStyle.allCases, id: \.self) { style in
                        Text(LyStr.badgeStyleName(style)).tag(style)
                    }
                }
                .onChange(of: badgeStyle) { _, value in write(value.rawValue, "badgeStyle") }
                if badgeStyle.needsRegion {
                    Text(LyStr.flagNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker(LyStr.badgeSize, selection: $badgeSize) {
                    ForEach(MenuBarIconSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .onChange(of: badgeSize) { _, value in write(value.rawValue, "badgeSize") }
                BadgePreview(style: badgeStyle, size: badgeSize)
            }
        }
    }

    private func exceptionsContain(_ word: String) -> Bool {
        Exceptions(words: exceptions.split(separator: "\n").map(String.init)).contains(word)
    }

    /// Adds the word as typed. The verdict checks both forms, so one entry
    /// covers the word however it ends up spelled.
    private func addException(_ word: String) {
        guard !exceptionsContain(word) else { return }
        exceptions = exceptions.isEmpty ? word : exceptions + "\n" + word
        write(exceptions.split(separator: "\n").map(String.init), "exceptions")
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
