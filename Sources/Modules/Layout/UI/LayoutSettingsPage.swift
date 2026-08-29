import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

struct LayoutSettingsPage: View {
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
    @State private var introSeen: Bool
    @StateObject private var convertKey: HelmHotkeyRecorder
    @State private var abbreviations: [AutoReplace.Entry]
    @State private var newShort = ""
    @State private var newLong = ""
    @State private var fixCapitals: Bool
    @State private var heroPeriod: ConversionPeriod
    @State private var heroMetric: HeroMetric

    init(vm: ModuleViewModel, store: NamespacedStore) {
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
            MenuBarIconSize(stored: store.string(LayoutKey.badgeSize, default: "small")))
        _tapKey = State(initialValue: TapKey.from(store.string(LayoutKey.tapKey, default: TapKey.rightCommand.rawValue)))
        _introSeen = State(initialValue: store.bool(LayoutKey.introSeen, default: false))
        _convertKey = StateObject(wrappedValue:
            HelmHotkeyRecorder(store: store, prefix: LayoutHotkey.storePrefix))
        _abbreviations = State(initialValue: AutoReplaceStore.load(store))
        _fixCapitals = State(initialValue: store.bool(LayoutKey.fixCapitals, default: false))
        _heroPeriod = State(initialValue: ConversionPeriod(
            rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today)
        _heroMetric = State(initialValue: HeroMetric(
            rawValue: store.string(LayoutKey.heroMetric, default: "")) ?? .words)
    }

    var body: some View {
        Form {
            // Once, and to the person who came looking for the module — rather
            // than in a queue of notices at first launch that nobody reads.
            if !introSeen { introSection }
            if accessibility == .denied {
                // **The hero stays and speaks.** It used to go with the page,
                // and VPN's and Keep Awake's never do — a module that vanishes
                // when it cannot work leaves nothing to read but an empty
                // screen. So the figure says «Not watching», and the empty
                // state arrives *under* it rather than instead of it.
                //
                // The settings below are still not drawn: 1867 pt of controls
                // macOS ignores, dimmed, reads as «broken»; absent reads as
                // «this first». The indicator is the exception and stays — it
                // reads the input source through TIS and needs no grant.
                // The hero alone, with no «Behaviour» over it: there is no
                // behaviour under it to name, and a section title standing over
                // a permission notice is a heading for the wrong thing.
                Section(header: hero) { EmptyView() }
                deniedSection
                indicatorSection
            } else {
                // The order is against the fold. «Try it» — which the
                // introduction promises — sat at 1045 pt, below a key
                // combination somebody sets once; the first screen now carries
                // the figure, what it does, and the field to try it in.
                behaviourSection
                tryItSection
                triggersSection
                exceptionsSection
                appsSection
                autoReplaceSection
                shortcutsSection
                indicatorSection
            }
        }
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        .helmTracksAccessibility($accessibility)
        // The two things on this page that arrive rather than being drawn once.
        // The indicator's own block is 174.5 pt and appeared instantly under the
        // switch that asks for it; a fix arrives from the engine while the page
        // is open — reachable by typing `ghbdtn` into the field above — and its
        // row appeared the same way.
        .animation(HelmMotion.interface, value: indicator)
        .animation(HelmMotion.interface, value: lvm.state.lastConversion)
        // Said once, out loud: losing the grant swaps the whole page for the
        // empty state, and nothing a VoiceOver reader is on changes its value.
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

    /// **In the page, not in a sheet.**
    ///
    /// It was `.sheet(isPresented:)`, which is a window: five of them per
    /// offscreen render, nothing of the introduction inside the page's own
    /// layers, and therefore the first screen a new user meets measured by
    /// nothing at all. A sheet's modality was protecting nothing either — the
    /// module is already running when the page opens, so this explains rather
    /// than asks — and «Got it» does exactly what it did.
    private var introSection: some View {
        Section {
            LayoutIntro(gesture: gestureName) {
                store.set(true, for: LayoutKey.introSeen)
                withAnimation(HelmMotion.disclosure) { introSeen = true }
            }
        }
    }

    /// Three states, not two: watching, paused by secure input, and not
    /// watching at all because the grant is missing.
    /// The grant comes first, because without it the module is not watching
    /// anything and the switch above is the only thing that says otherwise.
    /// Measured in this machine's log: 84 warnings of `no accessibility grant —
    /// not watching`, against a page that said "On" in green throughout. The
    /// state is what the module can do, not what the setting says.
    private var stateLabel: String {
        if accessibility == .denied { return LyStr.notWatching }
        if !lvm.state.enabled { return LyStr.notWatching }
        return lvm.state.suspended ? LyStr.paused : LyStr.on
    }

    /// From `HelmSignal`, never the raw system palette: orange measures 2.31:1
    /// and green 2.22:1 against this page's own background in light.
    private var stateTint: Color {
        if accessibility == .denied { return HelmSignal.warning }
        if !lvm.state.enabled { return HelmSignal.warning }
        return lvm.state.suspended ? HelmSignal.warning : HelmSignal.success
    }

    /// The figure this module has, at the size a figure gets.
    ///
    /// It was a `HelmMetricStrip` — «Active · 17» over 9 pt capitals reading
    /// STATE and TODAY, which is a label for a number nobody needs labelled and
    /// a second word for the badge in the page header. The count of words put
    /// right today is the one thing here worth a glance, and the type scale's
    /// top step is what it is set in — `HelmText.heroFigureFont`, the same
    /// token Keep Awake's countdown draws, so two pages of this app cannot
    /// measure their own heroes differently. That last clause was prose here
    /// with nothing under it until the token existed.
    private var hero: some View {
        LayoutHero(totals: lvm.state.totals,
                   suspended: lvm.state.suspended,
                   watching: accessibility != .denied && lvm.state.enabled,
                   period: $heroPeriod,
                   metric: $heroMetric,
                   grant: accessibility == .denied
                       ? { PermissionNeed.accessibility.openSettings() } : nil)
        .onChange(of: heroPeriod) { _, new in store.set(new.rawValue, for: LayoutKey.heroPeriod) }
        .onChange(of: heroMetric) { _, new in store.set(new.rawValue, for: LayoutKey.heroMetric) }
    }

    /// The hero rides on the first section's header, for the reason Keep Awake's
    /// does: a section **header** is the one part of a grouped `Form` that is
    /// drawn on the bare pane and still scrolls with the page. A row would be
    /// inside the card, and pinning it above the form would spend a fifth of the
    /// window on a figure however far down the settings somebody had gone.
    private var heroAndTitle: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            hero
            HelmSectionTitle(HelmSectionName.behaviour)
        }
        // **No outset.** It was on this whole block — the figure *and* the
        // section title — so «Behaviour» sat 9.5 pt left of the other seven
        // headings on the page, measured. The 10 pt is for a block that draws a
        // surface; this one is centred text, and Keep Awake's hero, centred for
        // the same reason, takes none either.
        .padding(.bottom, HelmSpace.s5)
    }

    /// What it does, and the last thing it did.
    ///
    /// It had no heading at all — a 10 pt gap where every other section has 54 —
    /// so it and the block above read as one card.
    @ViewBuilder private var behaviourSection: some View {
        Section(header: heroAndTitle) {
            HelmSettingRow(LyStr.automatic, note: LyStr.automaticNote) {
                Toggle(LyStr.automatic, isOn: $automatic)
                    .labelsHidden()
                    .onChange(of: automatic) { _, value in write(value, LayoutKey.automatic) }
            }
            HelmSettingRow(LyStr.audible) {
                Toggle(LyStr.audible, isOn: $audible)
                    .labelsHidden()
                    .onChange(of: audible) { _, value in write(value, LayoutKey.audible) }
            }
            if lvm.state.suspended {
                Text(LyStr.suspended).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = lvm.state.lastConversion {
                // Shown, not offered. Undoing has to happen in the app the
                // conversion happened in, and reaching a button here means
                // bringing Helm forward — which is both the wrong app and, as a
                // click, the thing that ends the chance to undo. A button that
                // cannot fire is worse than no button. So the sentence saying
                // how to undo is this row's own note rather than a row of its
                // own with a hairline between it and the thing it explains.
                HelmSettingRow(lvm.state.lastConversionUndone
                                ? LyStr.lastChangeUndone : LyStr.lastChange,
                               note: lastChangeNote) {
                    // A 48-character word used to put «Last change» on two
                    // lines: inside `HelmSettingRow` the label holds the layout
                    // priority and a value with a line limit gives way, so the
                    // long one truncates in the middle and the row keeps its
                    // height.
                    Text("\(last.before) → \(last.after)")
                        .font(HelmText.figureFont)
                        .lineLimit(1).truncationMode(.middle)
                    // Unlike undoing, this works from anywhere: it changes
                    // a list, not somebody else's text. Not for a forced
                    // conversion, though: there `before` is arbitrary typed
                    // text the dictionary never vouched for — possibly a field
                    // nothing recognised as secure — and this button is the
                    // module's one path from typed text to a file on disk.
                    if !last.forced {
                        Button(LyStr.neverThisWord) { addException(last.before) }
                            .controlSize(.small)
                            .disabled(exceptionsContain(last.before))
                    }
                }
            }
        }
    }

    /// Without the grant the whole page is inert, and it said so in a banner
    /// over 1867 pt of settings macOS ignores.
    /// What is left to say once the hero has said it.
    ///
    /// **It used to say the same thing twice.** The hero drew «Not watching»
    /// and the whole sentence, and this drew the sentence again under a title
    /// that repeated it a third time — with the window header's own badge
    /// making four. So the hero keeps the figure, the reason and the verb, and
    /// this keeps the two facts the hero has no room for: what the permission
    /// cannot see, and what still works without it.
    private var deniedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: HelmSpace.s4) {
                Text(LyStr.deniedGuarantee)
                Text(LyStr.indicatorWorksAnyway)
            }
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var triggersSection: some View {
        Section {
            Toggle(LyStr.onSpace, isOn: $onSpace)
                .onChange(of: onSpace) { _, value in write(value, LayoutKey.onSpace) }
            Toggle(LyStr.onReturn, isOn: $onReturn)
                .onChange(of: onReturn) { _, value in write(value, LayoutKey.onReturn) }
            Toggle(LyStr.onPunctuation, isOn: $onPunctuation)
                .onChange(of: onPunctuation) { _, value in write(value, LayoutKey.onPunctuation) }
        } header: {
            HelmSectionTitle(LyStr.triggers)
        } footer: {
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                sectionNote(LyStr.triggersHint)
                // All three off is «Fix as I type» switched on and doing
                // nothing: no ending ever confirms a word, and the green badge
                // above keeps saying «Active» because the tap is, in fact,
                // alive. Judged by the same value the engine acts on, not by a
                // hand-assembled `&&` that could drift from it.
                if ConversionTriggers(onSpace: onSpace, onReturn: onReturn,
                                      onPunctuation: onPunctuation).fixesNothing {
                    Text(LyStr.noTriggers)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmSignal.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A layout macOS cannot spell-check. «Fix as I type» is dead
                // for every pair that includes it, and until now the page said
                // nothing — the switch stayed on and the badge stayed green.
                // Named by the system's own name for the source, never by its id.
                if !lvm.state.noDictionary.isEmpty {
                    Text(LyStr.noDictionary(layouts: lvm.state.noDictionary
                                                .map { InputSourceInfo.name(of: $0) }
                                                .joined(separator: ", ")))
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmSignal.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var shortcutsSection: some View {
        Section {
            // One gesture. This was two sections and eleven controls: chords for
            // "convert the last word" and "undo", and three more for the three
            // things that could be done to a selection. The engine already chose
            // between converting and undoing by itself, and now it chooses
            // between the selection and the last word too — so every one of
            // those rows was asking the reader to assemble something the app
            // assembles better.
            HelmSettingRow(LyStr.tapKey, note: tapKeyNote) {
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
            // For keyboards with no right-hand modifier to tap: 60% boards,
            // HHKB. Same action, so there is no second behaviour to explain and
            // no way to bind the two against each other.
            HelmHotkeyRow(LyStr.orShortcut, recorder: convertKey,
                          taken: HotkeyStatus.isTaken(LayoutHotkey.fix))
        } header: {
            HelmSectionTitle(LyStr.shortcuts)
        }
    }

    /// The note under the key's own row, and it is two sentences at most: what
    /// the gesture is, plus whatever that particular key costs.
    ///
    /// 🌐︎ is the system's key first — Helm cannot take it, and cannot even read
    /// what it is set to until the person has changed it once, so the note states
    /// the precondition instead of promising anything. A left-hand key is a key
    /// you type with, which is not a warning against it but should be visible at
    /// the moment the choice is made rather than discovered later. Both used to
    /// be rows of their own, under the hint, which is three rows and two
    /// hairlines for one control.
    private var tapKeyNote: String {
        if tapKey == .globe { return LyStr.tapKeyHint + " " + LyStr.globeNote }
        // Either Control: a solo Control tap is VoiceOver's own «pause speech»
        // gesture, and the person choosing it should hear that here, not
        // discover the collision later. The left one still carries the
        // typing-key trade as well.
        if tapKey == .leftControl || tapKey == .rightControl {
            let habit = tapKey.isFrequentlyUsed ? LyStr.leftKeyNote + " " : ""
            return LyStr.tapKeyHint + " " + habit + LyStr.controlKeyNote
        }
        if tapKey.isFrequentlyUsed { return LyStr.tapKeyHint + " " + LyStr.leftKeyNote }
        return LyStr.tapKeyHint
    }

    /// The note under «Last change», built from the current binding the way
    /// `VPNStr.secretNeedsAPress` is — the sentence cannot drift from the
    /// control it names. Three honest states: a gesture exists and is named;
    /// none exists and the hint says the change can only be put back by hand;
    /// the change was already taken back and needs no undo instructions.
    private var lastChangeNote: String? {
        if lvm.state.lastConversionUndone { return nil }
        guard let gestureName else { return LyStr.undoImpossible }
        return LyStr.undoHint(gesture: gestureName)
    }

    /// Abbreviations, and the one typing habit Helm is sure enough about to
    /// correct.
    private var autoReplaceSection: some View {
        Section {
            if abbreviations.isEmpty {
                Text(LyStr.noAbbreviations).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
            }
            ForEach(abbreviations) { entry in
                HStack(spacing: HelmSpace.s5) {
                    Text(entry.from)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minWidth: 60, alignment: .leading)
                    Text("→").foregroundStyle(HelmText.faint)
                    Text(entry.to).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Button {
                        abbreviations.removeAll { $0.from == entry.from }
                        AutoReplaceStore.save(abbreviations, to: store)
                        lvm.vm.send(LayoutCommand.settingsChanged)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(HelmText.quiet)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(HelmA11y.remove), \(entry.from)")
                }
                // One element per abbreviation: read apart, the row was a
                // token, «right arrow», a phrase and a button with nothing
                // saying the four belong together. The remove button's action
                // survives the merge as the element's action.
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                // `prompt:` rather than a title, and labels hidden: inside a
                // `Form` a `TextField`'s title is drawn as a label *beside* the
                // field, so the placeholder ended up as a two-line word to the
                // left of an empty box with "stands for" floating between them.
                TextField("", text: $newShort, prompt: Text(LyStr.abbreviation))
                    // A prompt is a placeholder, and a placeholder disappears
                    // the moment there is a value to read.
                    .accessibilityLabel(LyStr.abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 150)
                TextField("", text: $newLong, prompt: Text(LyStr.expansion))
                    .accessibilityLabel(LyStr.expansion)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Button(LyStr.addAbbreviation) { addAbbreviation() }
                    .disabled(newShort.trimmingCharacters(in: .whitespaces).isEmpty
                              || newLong.isEmpty)
            }
            HelmSettingRow(LyStr.fixCapitals, note: LyStr.fixCapitalsNote) {
                Toggle(LyStr.fixCapitals, isOn: $fixCapitals)
                    .labelsHidden()
                    .onChange(of: fixCapitals) { _, value in write(value, LayoutKey.fixCapitals) }
            }
        } header: {
            HelmSectionTitle(LyStr.autoReplaceSection)
        } footer: {
            sectionNote(LyStr.autoReplaceNote)
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
        lvm.vm.send(LayoutCommand.settingsChanged)
        newShort = ""
        newLong = ""
    }

    /// A place to try it without risking anything that was being written.
    ///
    /// Above the triggers and the lists now: it is what the introduction
    /// promises, and it was at 1045 pt — under two sections of things somebody
    /// sets once and then never opens this page for again.
    private var tryItSection: some View {
        Section(header: HelmSectionTitle(LyStr.tryIt)) { LayoutTestField() }
    }

    private var exceptionsSection: some View {
        Section {
            TextEditor(text: $exceptions)
                .font(.system(size: 13, design: .monospaced))
                // The one place a saved word can be removed, and to VoiceOver
                // it was an anonymous text area: the section header does not
                // name a bare editor the way it names a labelled control.
                .accessibilityLabel(LyStr.exceptions)
                .accessibilityHint(LyStr.exceptionsHint)
                // **A ceiling, because the list is somebody else's length.** At
                // 14.55 pt a line, 200 words made the page 4695 pt: an editor
                // with no maximum grows the whole form instead of scrolling
                // itself, and it scrolls itself perfectly well.
                .frame(minHeight: 90, maxHeight: 220)
                .helmFieldWell()
                .onChange(of: exceptions) { _, value in
                    write(value.split(separator: "\n").map(String.init), LayoutKey.exceptions)
                }
        } header: {
            HelmSectionTitle(LyStr.exceptions)
        } footer: {
            sectionNote(LyStr.exceptionsHint)
        }
    }

    @ViewBuilder private var appsSection: some View {
        Section {
            if appRules.isEmpty {
                Text(LyStr.noAppsYet).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
            }
            // By the name the row draws, not by the bundle id it is stored
            // under: `com.apple.Safari` before `org.mozilla.firefox` reads as
            // Safari before Firefox, which is an order with no rule in it.
            ForEach(AppInfo.sortedByName(appRules.keys), id: \.self) { bundleID in
                appRow(bundleID)
            }
            Button { pickApps() } label: { Label(LyStr.addApp, systemImage: "plus") }
        } header: {
            HelmSectionTitle(LyStr.apps)
        } footer: {
            sectionNote(LyStr.appsHint)
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        HelmAppRuleRow(bundleID: bundleID) {
            // The picker carries the app's name: "Off, pop-up button" answers
            // nothing when there are five of these in a list.
            Picker(AppInfo.resolve(bundleID).name, selection: ruleBinding(bundleID)) {
                Text(LyStr.ruleOff).tag(false)
                Text(LyStr.ruleOn).tag(true)
            }
            .labelsHidden()
            .fixedSize()
        } remove: {
            appRules.removeValue(forKey: bundleID)
            write(appRules, LayoutKey.appRules)
        }
    }

    @ViewBuilder private var indicatorSection: some View {
        Section {
            HelmSettingRow(LyStr.indicatorShow) {
                Toggle(LyStr.indicatorShow, isOn: $indicator)
                    .labelsHidden()
                    .onChange(of: indicator) { _, value in write(value, LayoutKey.indicator) }
            }
            if indicator {
                // The note about a layout that names no country belongs to the
                // style row: it explains what that choice does, and as a row of
                // its own it had a hairline between the control and its own
                // explanation.
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
                HelmSettingRow(LyStr.badgeSize) {
                    Picker(LyStr.badgeSize, selection: $badgeSize) {
                        ForEach(MenuBarIconSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: badgeSize) { _, value in write(value.rawValue, LayoutKey.badgeSize) }
                }
                BadgePreview(style: badgeStyle, size: badgeSize)
            }
        } header: {
            HelmSectionTitle(LyStr.indicator)
        } footer: {
            sectionNote(LyStr.indicatorHint)
        }
    }

    /// The one shape a note under a card takes on this page.
    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
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
        lvm.vm.send(LayoutCommand.settingsChanged)
    }
}
