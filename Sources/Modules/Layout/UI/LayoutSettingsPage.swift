import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

struct LayoutSettingsPage: View {
    @ObservedObject private var lvm: LayoutViewModel
    private let store: NamespacedStore

    @State private var automatic: Bool
    /// Counts, not the lists: the window owns those. Kept in `@State` and
    /// refreshed on the store's own announcement so the rows stay right while
    /// somebody edits in the window beside this one.
    @State private var exceptionCount: Int
    @State private var ruleCount: Int
    @State private var listsWindow: LayoutListsWindow?
    /// Separate from `introSeen`, which is the stored fact. This is «is it on
    /// screen now», so the button can bring it back without unlearning that the
    /// person has already met the module once.
    @State private var showTour: Bool
    @State private var accessibility: PermissionState = .granted
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
        _exceptionCount = State(initialValue: store.stringArray(LayoutKey.exceptions).count)
        _ruleCount = State(initialValue: store.boolTable(LayoutKey.appRules).count)
        _showTour = State(initialValue: !store.bool(LayoutKey.introSeen, default: false))
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
            if showTour, accessibility != .denied { tourSection }
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
                listsSection
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
        // **Filtered by key**, which `NamespacedStore.changed(_:is:)` exists for
        // and nobody used: two unfiltered mirrors of one setting re-read
        // themselves on every write anywhere in Helm, which is how the hero and
        // the window header came to disagree about the same value.
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            if store.changed(note, is: LayoutKey.exceptions) {
                exceptionCount = store.stringArray(LayoutKey.exceptions).count
            }
            if store.changed(note, is: LayoutKey.appRules) {
                ruleCount = store.boolTable(LayoutKey.appRules).count
            }
        }
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
    /// The tour, where the introduction used to be.
    ///
    /// **The introduction told you what would happen; this lets you do it.**
    /// Four steps, each carrying the live control it is about — the real try-it
    /// field on step two, the three switches on step three — so agreeing with a
    /// step is switching the thing on rather than reading that you could.
    ///
    /// Shown by itself on a first visit and reachable afterwards from the
    /// button beside the behaviour heading, because somebody who dismissed it
    /// on day one still has the questions on day thirty.
    private var tourSection: some View {
        Section {
            LayoutTour(gesture: gestureName, store: store) {
                lvm.vm.send(LayoutCommand.settingsChanged)
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

    @ViewBuilder private var behaviourSection: some View {
        Section(header: heroAndTitle) {
            // The way back into the tour, and only once it has been dismissed —
            // a button that reopens what is already open is a button that does
            // nothing, which is worse than no button.
            if !showTour {
                HelmSettingRow(LyStr.tourTitle) {
                    Button(LyStr.tourTitle) {
                        withAnimation(HelmMotion.interface) { showTour = true }
                    }
                    .controlSize(.small)
                }
            }
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
                ConversionPair(last, undone: lvm.state.lastConversionUndone)
                    .font(HelmText.rowDetail)
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
        guard let gestureName else { return LyStr.undoImpossible() }
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

    /// The words the module must never touch.
    ///
    /// **Rows, not a text blob.** It was a `TextEditor`, one word a line, so
    /// removing a single word meant aiming inside a block of text without
    /// disturbing its neighbours — and the «Never this word» button beside the
    /// last change, and the panel tile's, both appended into that same blob. One
    /// idea, reached three ways, editable only as prose. A row with a cross
    /// beside it is the shape the abbreviations list used before it was cut, and
    /// it is the shape everything else on this page that holds a list uses.
    /// The two lists, as two rows that open the window holding them.
    ///
    /// **They were sections here and the page is not where they belong.** A
    /// list of words and a list of apps grow without limit, are visited rarely
    /// and edited deliberately — and between them they pushed the three
    /// switches somebody actually reaches for below the fold. `LayoutLists` is
    /// the same two sections, in `LayoutListsWindow`.
    ///
    /// **Each row carries its own count**, which is the one thing a list behind
    /// a button owes: «Never this word» is pressed from the panel tile and from
    /// the row above, and somebody who presses it has to be able to see that
    /// the word went somewhere.
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
                    .frame(width: 18)
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
        // Read apart it was a name, a count and two unnamed glyphs.
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
                // Size and the preview are about a badge, and «Название
                // раскладки» draws no badge — it draws the layout's name at the
                // menu bar's own size. They used to stay live and go on
                // promising «your layouts, as they will look» over an indicator
                // that had stopped looking like that at all, because the switch
                // that caused it lived in the status item's menu and nothing
                // here knew about it.
                if !badgeStyle.isName {
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
        Exceptions(words: store.stringArray(LayoutKey.exceptions)).contains(word)
    }

    /// Adds the word as typed, straight to the store — the list itself lives in
    /// `LayoutLists` now, and this page holds only the count.
    ///
    /// The verdict checks both forms, so one entry covers the word however it
    /// ends up spelled. Sorted, so a list somebody comes back to is in an order
    /// they can search: the text blob this replaced grew by appending, and a
    /// fiftieth word landed wherever the last one had.
    private func addException(_ word: String) {
        guard let words = Exceptions.adding(word, to: store.stringArray(LayoutKey.exceptions))
        else { return }
        write(words, LayoutKey.exceptions)
        exceptionCount = words.count
    }

    /// One window, held for as long as it is up.
    ///
    /// The holder is cleared by `HostWindow`'s own `onClose`, however the window
    /// goes away — the pattern `TrashedLeftoversWindow` uses, and the reason
    /// that type exists rather than each caller keeping a flag of its own.
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
        LayoutLists(store: store, builtInBlocked: builtInBlocked) {
            lvm.vm.send(LayoutCommand.settingsChanged)
        }
    }

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        lvm.vm.send(LayoutCommand.settingsChanged)
    }
}
