import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

struct LayoutSettingsPage: View {
    @ObservedObject private var lvm: LayoutViewModel
    private let store: NamespacedStore

    @State private var automatic: Bool
    /// Counts, not the lists: the window owns those. Refreshed on the store's own announcement so the
    /// rows stay right while somebody edits in the window beside this one.
    @State private var exceptionCount: Int
    @State private var ruleCount: Int
    @State private var listsWindow: LayoutListsWindow?
    /// "On screen now", apart from the stored `introSeen`, so the button can bring the tour back.
    @State private var showTour: Bool
    @State private var accessibility: PermissionState = .granted
    @State private var audible: Bool
    @State private var indicator: Bool
    @State private var badgeStyle: BadgeStyle
    @State private var tapKey: TapKey
    @State private var introSeen: Bool
    @StateObject private var convertKey: HelmHotkeyRecorder
    @State private var fixCapitals: Bool
    /// The apps Helm leaves alone before any rule is consulted, filtered to the ones this Mac has; worked
    /// out once because each answer is an `NSWorkspace` lookup and this is read while a form redraws.
    private let builtInBlocked: [String]
    @State private var heroPeriod: ConversionPeriod

    init(lvm: LayoutViewModel, store: NamespacedStore) {
        self.lvm = lvm
        self.store = store
        _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        _exceptionCount = State(initialValue: store.stringArray(LayoutKey.exceptions).count)
        _showTour = State(initialValue: !store.bool(LayoutKey.introSeen, default: false))
        _audible = State(initialValue: store.bool(LayoutKey.audible, default: false))
        _indicator = State(initialValue: store.bool(LayoutKey.indicator, default: false))
        _badgeStyle = State(initialValue:
            BadgeStyle.from(store.string(LayoutKey.badgeStyle, default: BadgeStyle.default.rawValue)))
        _tapKey = State(initialValue: TapKey.from(store.string(LayoutKey.tapKey, default: TapKey.rightCommand.rawValue)))
        _introSeen = State(initialValue: store.bool(LayoutKey.introSeen, default: false))
        _convertKey = StateObject(wrappedValue:
            HelmHotkeyRecorder(store: store, prefix: LayoutHotkey.storePrefix))
        _fixCapitals = State(initialValue: store.bool(LayoutKey.fixCapitals, default: true))
        builtInBlocked = AppScope.blockedByDefault.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        // The count is of what the window draws: the person's rules plus the built-in refusals this Mac has.
        _ruleCount = State(initialValue: Self.ruleCount(store, builtInBlocked))
        _heroPeriod = State(initialValue: ConversionPeriod(
            rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today)
    }

    var body: some View {
        Form {
            // Once, and to the person who came looking for the module. Not before the grant: it points at
            // a field and a section the page does not carry without Accessibility.
            if showTour, accessibility != .denied { tourSection }
            if accessibility == .denied {
                // The hero stays and speaks, with no «Behaviour» over it: the settings below are not drawn
                // (controls macOS ignores read as «broken»), but the indicator needs no grant and stays.
                Section(header: hero) { EmptyView() }
                deniedSection
                indicatorSection
            } else {
                // The order is against the fold: the figure, what it does, and the field to try it in.
                behaviourSection
                // Not while the tour holds the same field (its step 2); the section is where it lives afterwards.
                if !showTour { tryItSection }
                listsSection
                shortcutsSection
                indicatorSection
            }
        }
        // `enabled` feeds the hero's `watching`, whose period row closes and opens (`helmAccordion`); kept at the
        // page level for the form below it, not measured to be redundant with the hero's own animation.
        .animation(HelmMotion.interface, value: lvm.state.enabled)
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        .helmTracksAccessibility($accessibility)
        // The indicator's block and a fix arriving from the engine both appear under this animation.
        .animation(HelmMotion.interface, value: indicator)
        .animation(HelmMotion.interface, value: lvm.state.lastConversion)
        // Filtered by key (`NamespacedStore.changed(_:is:)`): an unfiltered mirror re-reads on every write anywhere.
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            if store.changed(note, is: LayoutKey.exceptions) {
                exceptionCount = store.stringArray(LayoutKey.exceptions).count
            }
            if store.changed(note, is: LayoutKey.appRules) {
                ruleCount = Self.ruleCount(store, builtInBlocked)
            }
            // The three switches are also written by the tour (step 3); the panel tile writes `automatic`.
            if store.changed(note, is: LayoutKey.automatic) {
                automatic = store.bool(LayoutKey.automatic, default: true)
            }
            if store.changed(note, is: LayoutKey.fixCapitals) {
                fixCapitals = store.bool(LayoutKey.fixCapitals, default: true)
            }
            if store.changed(note, is: LayoutKey.audible) {
                audible = store.bool(LayoutKey.audible, default: false)
            }
            // The panel tile's period menu writes this key too (`LayoutWidgets.Tall`); `LayoutDescriptor.storedPeriod` reads it.
            if store.changed(note, is: LayoutKey.heroPeriod) {
                heroPeriod = ConversionPeriod(
                    rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today
            }
        }
        // Said once, out loud: losing the grant takes the settings off the page, and nothing a VoiceOver
        // reader is on changes its value.
        .helmAnnounces(accessibility == .denied ? LyStr.deniedTitle : nil)
    }

    /// The undo gesture as it is actually bound right now: the tap key first,
    /// the recorded chord when the key is off, nil when neither exists. Every
    /// sentence naming the gesture is built from this, so none can drift from
    /// the control it names — and nil is the honest case the strings must not
    /// paper over: with no binding there is no undo.
    private var gestureName: String? {
        if tapKey != .off { return LyStr.tapKeyName(tapKey) }
        if !convertKey.label.isEmpty { return convertKey.label }
        return nil
    }

    /// The tour: shown by itself on a first visit and reachable afterwards from the button beside the
    /// behaviour heading.
    private var tourSection: some View {
        Section {
            LayoutTour(gesture: gestureName, store: store) {
                lvm.settingsChanged()
            } onDone: {
                withAnimation(HelmMotion.interface) { showTour = false }
                write(true, LayoutKey.introSeen)
                introSeen = true
            }
        }
    }

    private var hero: some View {
        LayoutHero(totals: lvm.state.totals,
                   suspended: lvm.state.suspended,
                   watching: accessibility != .denied && lvm.state.enabled,
                   period: $heroPeriod,
                   grant: accessibility == .denied
                       ? { PermissionNeed.accessibility.openSettings() } : nil)
        .onChange(of: heroPeriod) { _, new in store.set(new.rawValue, for: LayoutKey.heroPeriod) }
    }

    /// The heading only when the section under it has a card: a grouped `Form` draws none for an empty
    /// section, so a title over one falls onto the next section's.
    private var behaviourHasRows: Bool {
        !showTour || lvm.state.lastConversion != nil || !lvm.state.noDictionary.isEmpty
    }

    private var heroAndTitle: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            hero
            if behaviourHasRows { HelmSectionTitle(HelmSectionName.behaviour) }
        }
        // No outset: it is for a block that draws a surface, and this one is centred text.
    }

    @ViewBuilder private var behaviourSection: some View {
        Section(header: heroAndTitle) {
            // One copy of each switch on screen: while the tour is up it has them (step 3), and the button
            // that reopens it is gone for the same reason.
            if showTour {
                EmptyView()
            } else {
                HelmSettingRow(LyStr.tourTitle) {
                    Button(LyStr.showTour) {
                        withAnimation(HelmMotion.interface) { showTour = true }
                    }
                    .controlSize(.small)
                }
                HelmSettingRow(LyStr.automatic, note: LyStr.automaticNote) {
                    Toggle(LyStr.automatic, isOn: $automatic)
                        .labelsHidden()
                        .onChange(of: automatic) { _, value in write(value, LayoutKey.automatic) }
                }
                HelmSettingRow(LyStr.fixCapitals, note: LyStr.fixCapitalsNote) {
                    Toggle(LyStr.fixCapitals, isOn: $fixCapitals)
                        .labelsHidden()
                        .onChange(of: fixCapitals) { _, value in
                            write(value, LayoutKey.fixCapitals)
                        }
                }
                HelmSettingRow(LyStr.audible) {
                    Toggle(LyStr.audible, isOn: $audible)
                        .labelsHidden()
                        .onChange(of: audible) { _, value in write(value, LayoutKey.audible) }
                }
            }
            // Outside the tour's gate: a layout macOS cannot spell-check is a fact about this Mac, not a setting.
            // Named by the system's own name for the source, never by its id.
            if !lvm.state.noDictionary.isEmpty {
                Text(LyStr.noDictionary(layouts: lvm.state.noDictionary
                                            .map { InputSourceInfo.name(of: $0) }
                                            .joined(separator: ", ")))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = lvm.state.lastConversion {
                lastChangeRow(last)
            }
        }
    }

    /// What is left to say once the hero has said it: what the permission cannot see, and what still works
    /// without it.
    private var deniedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: HelmSpace.s4) {
                HelmSettingsNote(LyStr.deniedGuarantee)
                HelmSettingsNote(LyStr.indicatorWorksAnyway)
            }
        }
    }

    private var shortcutsSection: some View {
        Section {
            // One gesture: the engine chooses between converting and undoing, and between the selection and
            // the last word.
            HelmSettingRow(LyStr.tapKey, note: tapKeyNote,
                           explainer: LyStr.tapKeyExplainer(tapKey)) {
                Picker(LyStr.tapKey, selection: $tapKey) {
                    ForEach(TapKey.allCases, id: \.self) { key in
                        Text(LyStr.tapKeyName(key)).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: tapKey) { _, value in write(value.rawValue, LayoutKey.tapKey) }
            }
            // For keyboards with no right-hand modifier to tap: same action, so nothing to bind against.
            HelmHotkeyRow(LyStr.orShortcut, recorder: convertKey,
                          taken: HotkeyStatus.isTaken(LayoutHotkey.fix))
        } header: {
            HelmSectionTitle(LyStr.shortcuts)
        }
    }

    /// The note under the key's own row; «Off» has its own sentence.
    private var tapKeyNote: String {
        tapKey == .off ? LyStr.tapKeyOff : LyStr.tapKeyHint
    }

    /// The last change, its explanation, and the one act available from here, stacked: as trailing
    /// controls of a row the label column held the priority and cut the value and the button mid-word.
    ///
    /// Undo is not offered: it has to happen in the app the conversion happened in, and a click here
    /// would bring Helm forward and end the chance. The note says how; the one button works anywhere.
    @ViewBuilder
    private func lastChangeRow(_ last: ConversionEvent) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s5) {
                Text(lvm.state.lastConversionUndone ? LyStr.lastChangeUndone : LyStr.lastChange)
                Spacer(minLength: HelmSpace.s5)
                ConversionPair(last, undone: lvm.state.lastConversionUndone)
                    .font(HelmText.rowDetail)
            }
            if let note = lastChangeNote {
                HelmSettingsNote(note)
            }
            // Not for a forced conversion: `before` is typed text the dictionary never vouched for, and this
            // button is the module's one path from typed text to a file on disk.
            if !last.forced {
                Button(LyStr.neverThisWord) { addException(last.before) }
                    .controlSize(.small)
                    .disabled(exceptionsContain(last.before))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var lastChangeNote: String? {
        if lvm.state.lastConversionUndone { return nil }
        guard let gestureName else { return LyStr.undoImpossible() }
        return LyStr.undoHint(gesture: gestureName)
    }

    /// A place to try it without risking anything that was being written.
    private var tryItSection: some View {
        Section(header: HelmSectionTitle(LyStr.tryIt)) { LayoutTestField() }
    }

    /// The two lists as two rows that open the window holding them: they grow without limit and are
    /// edited deliberately. Each row carries its count, so a word added from the last-change row or the
    /// panel tile visibly went somewhere.
    @ViewBuilder private var listsSection: some View {
        Section {
            listRow(LyStr.exceptions, LyStr.exceptionsRow(exceptionCount),
                    symbol: "character.textbox")
            listRow(LyStr.apps, LyStr.appsRow(ruleCount), symbol: "app.badge.checkmark")
        } header: {
            HelmSectionTitle(LyStr.listsWindowTitle)
        }
    }

    private func listRow(_ title: String, _ detail: String, symbol: String) -> some View {
        Button { openLists() } label: {
            HStack(spacing: HelmSpace.s5) {
                Image(systemName: symbol)
                    .frame(width: HelmLayout.symbolColumn)
                    .foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: HelmSpace.s4)
                Text(detail).foregroundStyle(HelmText.quiet)
                Image(systemName: "chevron.right")
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Read apart it is a name, a count and two unnamed glyphs.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var indicatorSection: some View {
        Section {
            HelmSettingRow(LyStr.indicatorShow) {
                Toggle(LyStr.indicatorShow, isOn: $indicator)
                    .labelsHidden()
                    .onChange(of: indicator) { _, value in write(value, LayoutKey.indicator) }
            }
            if indicator {
                // The note about a layout that names no country explains this choice, so it sits in the row.
                HelmSettingRow(LyStr.badgeStyle,
                               note: badgeStyle.needsRegion ? LyStr.flagNote : nil) {
                    Picker(LyStr.badgeStyle, selection: $badgeStyle) {
                        ForEach(BadgeStyle.allCases, id: \.self) { style in
                            Text(LyStr.badgeStyleName(style)).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: badgeStyle) { _, value in write(value.rawValue, LayoutKey.badgeStyle) }
                }
                // The preview is not a control: it is what makes the style answerable at all. «Layout name»
                // draws the name at the menu bar's own size, so it has nothing to preview.
                if !badgeStyle.isName {
                    BadgePreview(style: badgeStyle, size: .small)
                }
            }
        } header: {
            HelmSectionTitle(LyStr.indicator)
        } footer: {
            HelmSettingsNote(LyStr.indicatorHint)
        }
    }

    private func exceptionsContain(_ word: String) -> Bool {
        Exceptions(words: store.stringArray(LayoutKey.exceptions)).contains(word)
    }

    /// Adds the word as typed, straight to the store; the verdict checks both forms, so one entry covers
    /// the word however it ends up spelled. Sorted, so a long list can be searched.
    private func addException(_ word: String) {
        guard let words = Exceptions.adding(word, to: store.stringArray(LayoutKey.exceptions))
        else { return }
        write(words, LayoutKey.exceptions)
        exceptionCount = words.count
    }

    /// One window, held for as long as it is up and cleared by `HostWindow`'s own `onClose`
    /// (`TrashedLeftoversWindow`'s pattern).
    private func openLists() {
        if let listsWindow {
            listsWindow.show(lists)
            return
        }
        let window = LayoutListsWindow { listsWindow = nil }
        listsWindow = window
        window.show(lists)
    }

    private var lists: LayoutLists {
        LayoutLists(store: store, builtInBlocked: builtInBlocked,
                    close: { listsWindow?.close() }) {
            lvm.settingsChanged()
        }
    }

    /// The number the row says, which is the number of rows the window draws —
    /// `AppScope.listed` is the set, and `LayoutLists` draws exactly it.
    private static func ruleCount(_ store: NamespacedStore, _ builtInBlocked: [String]) -> Int {
        AppScope.listed(rules: store.boolTable(LayoutKey.appRules),
                        layouts: store.stringTable(LayoutKey.appLayouts),
                        builtIn: builtInBlocked).count
    }

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        lvm.settingsChanged()
    }
}
