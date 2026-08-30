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
    @State private var appRules: [String: Bool]
    @State private var audible: Bool
    @State private var indicator: Bool
    @State private var badgeStyle: BadgeStyle
    @State private var badgeSize: MenuBarIconSize
    @State private var tapKey: TapKey
    @State private var introSeen: Bool
    @StateObject private var convertKey: HelmHotkeyRecorder
    @State private var fixCapitals: Bool
    /// The apps Helm leaves alone before any rule is consulted, filtered to
    /// the ones this Mac actually has. Worked out once: each answer is an
    /// `NSWorkspace` lookup, and this is read while a form redraws.
    private let builtInBlocked: [String]
    @State private var heroPeriod: ConversionPeriod

    init(vm: ModuleViewModel, store: NamespacedStore) {
        lvm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool(LayoutKey.automatic, default: true))
        _exceptions = State(initialValue: store.stringArray(LayoutKey.exceptions).joined(separator: "\n"))
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
        _fixCapitals = State(initialValue: store.bool(LayoutKey.fixCapitals, default: false))
        builtInBlocked = AppScope.blockedByDefault.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        _heroPeriod = State(initialValue: ConversionPeriod(
            rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today)
    }

    var body: some View {
        Form {
            // Once, and to the person who came looking for the module — rather
            // than in a queue of notices at first launch that nobody reads.
            //
            // **Not before the grant.** It promises a field to try it in and a
            // section to pick a key in, and without Accessibility the page
            // carries neither — so on a fresh install, which is every install,
            // the first thing somebody read pointed twice at controls that were
            // not on the screen, directly above «Helm is not watching the
            // keyboard». It waits: the grant arrives, the page fills in, and
            // the introduction is still unseen and introduces something that is
            // actually there.
            if !introSeen, accessibility != .denied { introSection }
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
                exceptionsSection
                appsSection
                shortcutsSection
                indicatorSection
            }
        }
        // The metric now lives in the window header, which is a view with no
        // parent in common with this one. The store is what they share, and
        // this is the page's half of it: without it the header switches and the
        // figure under it does not.
        // The hero is 46 pt shorter without its verb row — measured — and that
        // is the state between the page appearing and the engine's first
        // `layoutState`. Unanimated it drops the whole form in one frame.
        .animation(HelmMotion.interface, value: lvm.state.enabled)
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
                   grant: accessibility == .denied
                       ? { PermissionNeed.accessibility.openSettings() } : nil)
        .onChange(of: heroPeriod) { _, new in store.set(new.rawValue, for: LayoutKey.heroPeriod) }
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
            // A layout macOS cannot spell-check. «Fix as I type» is dead for
            // every pair that includes it, and until this line the page said
            // nothing — the switch stayed on and the badge stayed green. It
            // used to hang under the three trigger toggles; it belongs to the
            // switch it is about, which is the one thing above it.
            // Named by the system's own name for the source, never by its id.
            if !lvm.state.noDictionary.isEmpty {
                Text(LyStr.noDictionary(layouts: lvm.state.noDictionary
                                            .map { InputSourceInfo.name(of: $0) }
                                            .joined(separator: ", ")))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HelmSettingRow(LyStr.fixCapitals, note: LyStr.fixCapitalsNote) {
                Toggle(LyStr.fixCapitals, isOn: $fixCapitals)
                    .labelsHidden()
                    .onChange(of: fixCapitals) { _, value in write(value, LayoutKey.fixCapitals) }
            }
            HelmSettingRow(LyStr.audible) {
                Toggle(LyStr.audible, isOn: $audible)
                    .labelsHidden()
                    .onChange(of: audible) { _, value in write(value, LayoutKey.audible) }
            }
            if let last = lvm.state.lastConversion {
                lastChangeRow(last)
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

    private var shortcutsSection: some View {
        Section {
            // One gesture. This was two sections and eleven controls: chords for
            // "convert the last word" and "undo", and three more for the three
            // things that could be done to a selection. The engine already chose
            // between converting and undoing by itself, and now it chooses
            // between the selection and the last word too — so every one of
            // those rows was asking the reader to assemble something the app
            // assembles better.
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
    /// **«Off» has its own sentence.** The row said how to tap a key that is
    /// not bound to anything: three lines telling somebody to press nothing.
    private var tapKeyNote: String {
        tapKey == .off ? LyStr.tapKeyOff : LyStr.tapKeyHint
    }

    /// The note under «Last change», built from the current binding the way
    /// `VPNStr.secretNeedsAPress` is — the sentence cannot drift from the
    /// control it names. Three honest states: a gesture exists and is named;
    /// none exists and the hint says the change can only be put back by hand;
    /// the change was already taken back and needs no undo instructions.
    /// The last change, its explanation, and the one act available from here.
    ///
    /// **Stacked rather than a row with a trailing group.** As three things on
    /// the right of a `HelmSettingRow` — the pair, the arrow, the button — it
    /// was the trailing side that gave way, because the label column holds the
    /// layout priority: photographed on the owner's Mac the value read «L…й»
    /// and the button «Н…», both cut mid-word, in the state this row is
    /// normally in. Nothing here is optional enough to truncate: the pair is
    /// what happened, and the button is what to do about it.
    ///
    /// Undo is deliberately not offered. It has to happen in the app the
    /// conversion happened in, and reaching a button here means bringing Helm
    /// forward — which is both the wrong app and, as a click, the thing that
    /// ends the chance to undo. So the sentence saying how lives here as the
    /// note, and the only button is the one that works from anywhere.
    @ViewBuilder
    private func lastChangeRow(_ last: ConversionEvent) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s5) {
                Text(lvm.state.lastConversionUndone ? LyStr.lastChangeUndone : LyStr.lastChange)
                Spacer(minLength: HelmSpace.s5)
                Text("\(last.before) → \(last.after)")
                    .font(HelmText.figureFont)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let note = lastChangeNote {
                Text(note)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Not for a forced conversion: there `before` is arbitrary typed
            // text the dictionary never vouched for — possibly a field nothing
            // recognised as secure — and this button is the module's one path
            // from typed text to a file on disk.
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
        guard let gestureName else { return LyStr.undoImpossible }
        return LyStr.undoHint(gesture: gestureName)
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
                .font(.system(.body, design: .monospaced))
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
            // **The built-in list is drawn, not described.** Seven apps were
            // refused before any rule was consulted and the page said so twice
            // in different words — «a few terminals and password managers are
            // left alone already» over an empty card, and «terminals and
            // password managers are left alone» under it — without naming one
            // of them. Somebody whose typing is not being fixed in Warp had no
            // way to learn from this page that Warp was the reason.
            //
            // They are ordinary rows now, set to «Don't fix», and switchable
            // like any other: the rule is visible and it is theirs to overrule.
            // Only the ones this Mac has — a row for an app nobody installed is
            // a list of somebody else's software.
            ForEach(AppInfo.sortedByName(Set(appRules.keys).union(builtInBlocked)),
                    id: \.self) { bundleID in
                appRow(bundleID)
            }
            Button { pickApps() } label: { Label(LyStr.addApp, systemImage: "plus") }
        } header: {
            HelmSectionTitle(LyStr.apps)
        } footer: {
            sectionNote(LyStr.appsWhy)
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
