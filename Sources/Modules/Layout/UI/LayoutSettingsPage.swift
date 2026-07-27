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
    @State private var tapKey: TapKey
    @State private var showingIntro = false
    @StateObject private var convertKey: HelmHotkeyRecorder
    @State private var abbreviations: [AutoReplace.Entry]
    @State private var newShort = ""
    @State private var newLong = ""
    @State private var fixCapitals: Bool

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        lvm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        _exceptions = State(initialValue: store.stringArray(LayoutKey.exceptions).joined(separator: "\n"))
        _onSpace = State(initialValue: store.bool(LayoutKey.onSpace, default: ConversionTriggers.default.onSpace))
        _onReturn = State(initialValue: store.bool(LayoutKey.onReturn, default: ConversionTriggers.default.onReturn))
        _onPunctuation = State(initialValue: store.bool(LayoutKey.onPunctuation, default: ConversionTriggers.default.onPunctuation))
        _appRules = State(initialValue: store.boolTable(LayoutKey.appRules))
        _audible = State(initialValue: store.bool(LayoutKey.audible, default: false))
        _indicator = State(initialValue: store.bool(LayoutKey.indicator, default: false))
        _badgeStyle = State(initialValue:
            BadgeStyle.from(store.string(LayoutKey.badgeStyle, default: BadgeStyle.default.rawValue)))
        _badgeSize = State(initialValue:
            MenuBarIconSize(rawValue: store.string(LayoutKey.badgeSize, default: "small")) ?? .small)
        _tapKey = State(initialValue: TapKey.from(store.string(LayoutKey.tapKey, default: TapKey.rightCommand.rawValue)))
        _convertKey = StateObject(wrappedValue:
            HelmHotkeyRecorder(store: store, prefix: "convertHotkey"))
        _abbreviations = State(initialValue: AutoReplaceStore.load(store))
        _fixCapitals = State(initialValue: store.bool(LayoutKey.fixCapitals, default: false))
    }

    public var body: some View {
        Form {
            stateSection
            behaviourSection
            triggersSection
            shortcutsSection
            autoReplaceSection
            tryItSection
            exceptionsSection
            indicatorSection
            appsSection
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task {
            accessibility = PermissionCheck.currentAccessibility()
            // Once, and to the person who came looking for the module — rather
            // than in a queue of notices at first launch that nobody reads.
            if !store.bool(LayoutKey.introSeen, default: false) { showingIntro = true }
        }
        .sheet(isPresented: $showingIntro) {
            LayoutIntro {
                store.set(true, for: LayoutKey.introSeen)
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
                .onChange(of: automatic) { _, value in write(value, LayoutKey.automatic) }
            Text(LyStr.automaticNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(LyStr.audible, isOn: $audible)
                .onChange(of: audible) { _, value in write(value, LayoutKey.audible) }
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
                .onChange(of: onSpace) { _, value in write(value, LayoutKey.onSpace) }
            Toggle(LyStr.onReturn, isOn: $onReturn)
                .onChange(of: onReturn) { _, value in write(value, LayoutKey.onReturn) }
            Toggle(LyStr.onPunctuation, isOn: $onPunctuation)
                .onChange(of: onPunctuation) { _, value in write(value, LayoutKey.onPunctuation) }
        }
    }

    private var shortcutsSection: some View {
        Section(LyStr.shortcuts) {
            // One gesture. This was two sections and eleven controls: chords for
            // "convert the last word" and "undo", and three more for the three
            // things that could be done to a selection. The engine already chose
            // between converting and undoing by itself, and now it chooses
            // between the selection and the last word too — so every one of
            // those rows was asking the reader to assemble something the app
            // assembles better.
            Picker(LyStr.tapKey, selection: $tapKey) {
                ForEach(TapKey.allCases, id: \.self) { key in
                    Text(LyStr.tapKeyName(key)).tag(key)
                }
            }
            .onChange(of: tapKey) { _, value in write(value.rawValue, LayoutKey.tapKey) }
            Text(LyStr.tapKeyHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // 🌐 is the system's key first. Helm cannot take it, and cannot even
            // read what it is set to until the person has changed it once, so
            // the note states the precondition instead of promising anything.
            if tapKey == .globe {
                Text(LyStr.globeNote)
                    .font(.caption).foregroundStyle(HelmText.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // For keyboards with no right-hand modifier to tap: 60% boards,
            // HHKB. Same action, so there is no second behaviour to explain and
            // no way to bind the two against each other.
            HelmHotkeyRow(LyStr.orShortcut, recorder: convertKey,
                          taken: HotkeyStatus.isTaken("layout.fix"))
        }
    }

    /// Abbreviations, and the one typing habit Helm is sure enough about to
    /// correct.
    private var autoReplaceSection: some View {
        Section(LyStr.autoReplaceSection) {
            Text(LyStr.autoReplaceNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if abbreviations.isEmpty {
                Text(LyStr.noAbbreviations).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(abbreviations) { entry in
                HStack(spacing: 10) {
                    Text(entry.from)
                        .font(.callout.monospaced())
                        .frame(minWidth: 60, alignment: .leading)
                    Text("→").foregroundStyle(HelmText.faint)
                    Text(entry.to).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Button {
                        abbreviations.removeAll { $0.from == entry.from }
                        AutoReplaceStore.save(abbreviations, to: store)
                        lvm.vm.send("settingsChanged")
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(HelmA11y.remove), \(entry.from)")
                }
            }
            HStack(spacing: 8) {
                // `prompt:` rather than a title, and labels hidden: inside a
                // `Form` a `TextField`'s title is drawn as a label *beside* the
                // field, so the placeholder ended up as a two-line word to the
                // left of an empty box with "stands for" floating between them.
                TextField("", text: $newShort, prompt: Text(LyStr.abbreviation))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 150)
                TextField("", text: $newLong, prompt: Text(LyStr.expansion))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Button(LyStr.addAbbreviation) { addAbbreviation() }
                    .disabled(newShort.trimmingCharacters(in: .whitespaces).isEmpty
                              || newLong.isEmpty)
            }
            Toggle(LyStr.fixCapitals, isOn: $fixCapitals)
                .onChange(of: fixCapitals) { _, value in write(value, LayoutKey.fixCapitals) }
            Text(LyStr.fixCapitalsNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addAbbreviation() {
        let short = newShort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !short.isEmpty, !newLong.isEmpty, short != newLong else { return }
        abbreviations.removeAll { $0.from == short }
        abbreviations.append(AutoReplace.Entry(from: short, to: newLong))
        abbreviations.sort { $0.from < $1.from }
        AutoReplaceStore.save(abbreviations, to: store)
        // Announced rather than written through a spare key: the table is
        // already saved, and the engine needs to be told to re-read it.
        lvm.vm.send("settingsChanged")
        newShort = ""
        newLong = ""
    }

    /// The three that act on a selection.
    ///
    /// A separate section from the shortcuts above, because they are a separate
    /// promise: those two edit a word Helm watched being typed a keystroke ago,
    /// these edit whatever is selected in whatever app is in front. Mixing them
    /// into one list would read as five variations of the same thing.
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
                    write(value.split(separator: "\n").map(String.init), LayoutKey.exceptions)
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
            // The picker carries the app's name: "Off, pop-up button" answers
            // nothing when there are five of these in a list.
            Picker(info.name, selection: ruleBinding(bundleID)) {
                Text(LyStr.ruleOff).tag(false)
                Text(LyStr.ruleOn).tag(true)
            }
            .labelsHidden()
            .fixedSize()
            Button {
                appRules.removeValue(forKey: bundleID)
                write(appRules, LayoutKey.appRules)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(HelmA11y.remove), \(info.name)")
        }
    }

    @ViewBuilder private var indicatorSection: some View {
        Section(LyStr.indicator) {
            Text(LyStr.indicatorHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(LyStr.indicatorShow, isOn: $indicator)
                .onChange(of: indicator) { _, value in write(value, LayoutKey.indicator) }
            if indicator {
                Picker(LyStr.badgeStyle, selection: $badgeStyle) {
                    ForEach(BadgeStyle.allCases, id: \.self) { style in
                        Text(LyStr.badgeStyleName(style)).tag(style)
                    }
                }
                .onChange(of: badgeStyle) { _, value in write(value.rawValue, LayoutKey.badgeStyle) }
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
                .onChange(of: badgeSize) { _, value in write(value.rawValue, LayoutKey.badgeSize) }
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
        write(exceptions.split(separator: "\n").map(String.init), LayoutKey.exceptions)
    }

    private func ruleBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(get: { appRules[bundleID] ?? false },
                set: { value in
                    appRules[bundleID] = value
                    write(appRules, LayoutKey.appRules)
                })
    }

    /// A rule is added switched **off**: someone reaching for this list is
    /// almost always trying to stop conversions somewhere, not start them.
    private func pickApps() {
        for bundleID in AppPicker.choose() where appRules[bundleID] == nil {
            appRules[bundleID] = false
        }
        write(appRules, LayoutKey.appRules)
    }

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        lvm.vm.send("settingsChanged")
    }
}
