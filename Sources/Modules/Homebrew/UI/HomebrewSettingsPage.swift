import AppKit
import SwiftUI
import HelmUI
import Module_Homebrew_Engine

// The three `Identifiable` conformances that used to sit here are on the models
// themselves now, spelled once through `BrewKey` — the same key the description
// cache is read by, which is the half that has to agree with the row.

struct HomebrewSettingsPage: View {
    @ObservedObject private var hb: HomebrewViewModel
    @State private var query = ""
    /// The search a press of Return started, held so the next press can drop it.
    ///
    /// **Every press used to be its own `Task` and nothing held any of them.**
    /// One search is two `brew search` runs — measured at about nine seconds —
    /// and a `brew desc` per kind after them, so ten presses were ten of those
    /// chains at once. What stops the *work* is `HelmProcess.launchCeiling` and
    /// the `LatestRequest` in the view model; this is the third of the three and
    /// the smallest: it keeps the tasks themselves from piling up, one per
    /// keystroke, each holding its own await for the life of a `brew` run.
    ///
    /// Cancelling does not stop the tool, and nothing here pretends it does —
    /// the child is the engine's and runs to its end.
    @State private var searching: Task<Void, Never>?

    /// **Whether the page is in its wide shape — one fact, read from the one
    /// place that can answer it.**
    ///
    /// `headerBar`'s `ViewThatFits` is the only thing on this page that can say
    /// whether the segmented switcher fits the pane *in the language being
    /// drawn*, and `HomebrewSplit`'s floor is folded into the same question
    /// there, so the answer it publishes is the whole boundary. The columns
    /// below read it rather than asking the width a second time — that second
    /// asking is what put two reorganisations six points apart in Russian.
    ///
    /// `true` until the first pass publishes: the page opens at 984 pt on this
    /// Mac, where it is true in all eight languages, so the opening frame is
    /// not a guess that has to be corrected on screen.
    @State private var pageIsWide = true

    /// What `headerBar` publishes and `managerBody` reads.
    ///
    /// **`Bool?`, and the default is nil rather than either answer.** Written
    /// as a plain `Bool` defaulting to `true` it read `true` at every width and
    /// in every language: the default is contributed by *every* view under the
    /// reader that does not set one — the two dividers, the columns, the status
    /// bar — and `value = nextValue()` takes the last of them, which is never
    /// the bar. Measured 2026-09-16: the header switched at the coupled
    /// boundary and the columns went on switching at 560, which is the defect
    /// this was written to end, still there and now invisible in the source.
    /// nil means "this view is not the bar", so the one contributor that is
    /// survives wherever it sits in the order.
    private struct PageIsWideKey: PreferenceKey {
        static let defaultValue: Bool? = nil
        static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
            value = nextValue() ?? value
        }
    }

    init(vm: ModuleViewModel) { hb = HomebrewViewModel.shared(vm: vm) }

    var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                managerBody
            } else {
                installScreen
            }
            if showsConsole {
                Divider()
                console
            }
        }
        // **The console arrives by taking 200 pt off everything above it**, and
        // it used to do that in one frame: the first install of the session put
        // a divider and a 160 pt well under the page, and the list, the status
        // bar and whatever row the eye was on jumped up together. One token, on
        // the fact that decides it — the same one the other list screens use
        // (`UninstallerSettingsPage`, which carries three of these).
        //
        // `showsConsole` and not `hb.consoleLines.count`: the lines arriving
        // scroll, which `console` already animates, and re-running the page's
        // layout per line of `brew` output is a different thing entirely.
        .animation(HelmMotion.interface, value: showsConsole)
        // The view model outlives this page, so a return visit shows what is
        // already loaded instead of paying for `brew list` and a `brew desc`
        // batch again.
        .task { await hb.loadIfNeeded() }
        // The other side of that: the view model outliving the page is exactly
        // why the page has to say it has gone. An uninstall ask is asked over
        // the transport and can be out for the whole query deadline, and the
        // `Task` the press launches is not tied to this subtree — so switching
        // modules or closing Settings leaves a query whose answer would set
        // `pendingUninstall` on a view model with nothing mounted, and the next
        // visit to Homebrew opens a confirmation for the app's only
        // irreversible deletion that nobody asked for. `LatestRequest` retires
        // work on a later press and on a cancel; leaving is neither, and this
        // is the one place that knows it happened
        // (`LeavingThePageRetiresAnUninstallAskTests`). The modifier is not on
        // this page and this comment used to say it was: `.helmIdlesOffScreen()`
        // is on the detail hosting controller in `SettingsWindow.swift`, which
        // holds whichever module page is open — so hiding the app or occluding
        // the Settings window unmounts this subtree and fires this too, which is
        // the behaviour, reached from one level up. Dismissing a
        // confirmation dialog the person had left standing on screen rather
        // than leaving it to act later on a reading taken before the
        // interruption, which is the right call for the app's only
        // irreversible deletion.
        // And the other question this page can have standing: a `brew doctor`
        // fix that removes a package waits on a dialog too, and it is asked of
        // the same view model, which outlives this subtree.
        .onDisappear { hb.cancelUninstall(); hb.cancelFix() }
        // The second irreversible deletion this page can reach, and it used to
        // go on a single click six points from Copy. The question names the
        // package with the words the Uninstall dialog uses — `FixAsk` decides
        // which of the two questions is asked, and whether one is asked at all.
        .confirmationDialog(hb.pendingFix.flatMap { Self.fixQuestion($0) } ?? "",
                            isPresented: Binding(get: { hb.pendingFix != nil },
                                                 set: { if !$0 { hb.cancelFix() } }),
                            titleVisibility: .visible) {
            Button(HbStr.runTheFix, role: .destructive) { hb.confirmFix() }
            Button(HbStr.cancel, role: .cancel) { hb.cancelFix() }
        } message: {
            if let note = hb.pendingFix.flatMap({ Self.fixQuestionNote($0) }) { Text(note) }
        }
        // Removing a cask removes an application. Every other destructive
        // action in Helm asks first; this one used to go on a single click.
        .confirmationDialog(hb.pendingUninstall.map { HbStr.confirmUninstall($0.name) } ?? "",
                            isPresented: Binding(get: { hb.pendingUninstall != nil },
                                                 set: { if !$0 { hb.cancelUninstall() } }),
                            titleVisibility: .visible) {
            Button(HbStr.uninstall, role: .destructive) { hb.confirmUninstall() }
            Button(HbStr.cancel, role: .cancel) { hb.cancelUninstall() }
        } message: {
            // Two sentences, and the second only when there is something to say:
            // a heading over an empty list reads as a reassurance that nothing
            // depends on this, which a refused query has not earned.
            if hb.dependentsOfPending.isEmpty {
                Text(HbStr.uninstallIsPermanent)
            } else {
                Text(HbStr.uninstallIsPermanent + "\n\n"
                     + HbStr.stillNeededBy + "\n"
                     + hb.dependentsOfPending.joined(separator: ", "))
            }
        }
    }

    /// Whether the console and the hairline over it are on the page at all.
    ///
    /// `.failed` as well, and that is not cosmetic: an operation the engine
    /// refused before it launched anything writes no console line, so a refusal
    /// with an empty console had no console to be drawn in and reached the page
    /// as nothing at all.
    ///
    /// Internal rather than private for `statusLine`'s reason: it is the value
    /// the page's own layout animation is keyed on, and a `body` is not
    /// somewhere a test can reach.
    var showsConsole: Bool {
        !hb.consoleLines.isEmpty || hb.running || hb.op.phase == .failed
    }

    // MARK: - Not installed

    /// The same pane draws `HelmEmptyState` with the module switched off; this
    /// used to replace it in place with a hand-rolled second one — 16 pt stack
    /// spacing against 14, a 20 pt title against 17, a 12 pt body against 13,
    /// and a button pinned to 260 pt. One flick of the switch showed both.
    ///
    /// **The tint is the module's, not the category's.** This comment used to
    /// say the colour was «read off the descriptor rather than written as
    /// `.pink`» — and it was reading `category.tint`, which is `.pink` reached
    /// the long way round and shared with two other modules. The plate in the
    /// page header above it was already green.
    private var installScreen: some View {
        HelmEmptyState(symbol: "shippingbox",
                       tint: HomebrewDescriptor.tint.colour,
                       title: HbStr.notInstalledTitle,
                       message: HbStr.notInstalledBody) {
            Button {
                hb.installBrew()
            } label: {
                Label(HbStr.installBrew, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(hb.running)
        }
    }

    // MARK: - Manager

    /// Counts as a quiet status line rather than a panel of dials.
    ///
    /// Internal rather than private, for the reason the Uninstaller's
    /// `statusLine` gives: which sentence stands over which loading state is
    /// the whole of a fix, and a `body` is not somewhere a test can reach.
    var statusLine: String {
        // **Three readings, three sentences.** A count that has not arrived is
        // not a count of zero — the list reloads after every operation, and for
        // that second the line read "0 packages · 0 updates · 0 casks" over a
        // machine with 53 of them. And a count that *cannot* arrive is not a
        // count on its way: this used to read `loadedInstalled`, which is
        // `installedReading == .answered` and so false for `.waiting` and
        // `.unanswerable` alike, which put «Reading the package list…» in the
        // bar under a master already saying Homebrew had not answered.
        // `ListScreen.of` makes the same three-way distinction for the list
        // itself; this is the bar's half of it.
        switch hb.installedReading {
        case .notAsked, .waiting: return HbStr.packagesLoading
        case .unanswerable: return HbStr.couldNotCount
        case .answered: break
        }
        // The same rule for updates, which this guard fixed only half of the
        // first time: `loadIfNeeded` deliberately never asks `brew outdated`,
        // so on first open the line said «Updates: 0» about a question with no
        // answer — for as long as nobody visited the Updates tab.
        guard hb.loadedOutdated else {
            return HbStr.packagesStatusNoUpdates(hb.installed.count,
                                                 hb.installed.filter(\.isCask).count)
        }
        return HbStr.packagesStatus(hb.installed.count,
                             hb.outdated.count,
                             hb.installed.filter(\.isCask).count)
    }

    private var managerBody: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            // The split is asked of the pane, not of the window: `HomebrewSplit`
            // carries the measured threshold, and a `private var` inside `body`
            // would be out of a test's reach (`SearchDisplay.swift`'s own reason).
            //
            // **The width decides the container, `detail` decides the
            // content.** Above the threshold the list and the subject sit side
            // by side; below it, selecting a row replaces the list with that
            // same view at full width, with `backBar` above it to return —
            // there is exactly one builder per kind of subject, called from
            // both places, so a wide inspector and a narrow screen cannot
            // drift into offering two different things for one of them.
            GeometryReader { proxy in
                let split = HomebrewSplit(availableWidth: proxy.size.width,
                                          segmentedHeaderFits: pageIsWide)
                if split.showsInspector {
                    HStack(spacing: HelmSpace.s5) {
                        listArea(singleColumn: split.singleColumn)
                            // `minWidth` and the compressibility it buys are
                            // kept exactly as they were: the split threshold
                            // was measured against a master that gives way
                            // before the inspector does, and a fixed `width:`
                            // here would move the floor that test re-measures.
                            .frame(minWidth: 240, idealWidth: split.masterWidth,
                                   maxWidth: split.masterWidth)
                        Divider()
                        detail
                            .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity,
                                  alignment: .topLeading)
                    }
                } else if hb.selected != nil {
                    // Selection already lives in `HomebrewViewModel`, per
                    // segment, so a non-nil `selected` is the whole of what
                    // puts this screen up — nothing new to hold here, and
                    // widening past the threshold with a package selected
                    // lands on that same package beside the list rather than
                    // on nothing, because both branches read the one selection.
                    VStack(spacing: 0) {
                        backBar
                        Divider()
                        detail
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    // No selection and no room for a second column: the list
                    // alone, with the description back on the row — the one
                    // thing the package view was carrying for it.
                    listArea(singleColumn: split.singleColumn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Counts belong in a quiet bottom bar, like the other list screens;
            // the toolbar is for what you can do, not for what there is.
            Divider()
            HStack {
                Text(statusLine)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                Spacer()
            }
            // A caption is shorter than a button: without this the bar was
            // 38 pt where the other two list screens are 49, and the content
            // jumped when switching between them.
            .frame(minHeight: 25)
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
        }
        // **Two things on this page change what is mounted, and neither moved.**
        // Switching segment replaced one list with another in a single frame,
        // and below `HomebrewSplit`'s threshold a press on a row swapped the
        // whole pane for the package — the two biggest changes the page makes,
        // drawn as cuts. One token each, the same one the other list screens
        // use.
        //
        // `hb.selected == nil` and not `hb.selected`: what the narrow branch
        // turns on is whether *anything* is selected, so this is the value that
        // swaps the pane. Keyed on the selection itself, moving between two
        // packages beside the list would animate a pane that is not swapping.
        .animation(HelmMotion.interface, value: hb.segment)
        .animation(HelmMotion.interface, value: hb.selected == nil)
        // The bar is above the columns and a preference travels upward, so this
        // is where the page's own shape lands — one value, set by whichever of
        // the bar's two candidates `ViewThatFits` actually mounted.
        .onPreferenceChange(PageIsWideKey.self) { if let shape = $0 { pageIsWide = shape } }
    }

    /// **The segment switcher and Refresh, in whichever shape fits the pane.**
    ///
    /// The switcher is `.fixedSize()` and therefore as wide as its eight
    /// languages make it: measured 2026-09-16, zh 252 · en 302 · de 320 ·
    /// fr 388 · pt 404 · es 476 · ru 488 · ja 494 pt, with the bar needing
    /// `picker + 65.5` around it before `upgradeAll` took its slot. The narrowest pane a person can reach is
    /// **540** — `max(detailItem.minimumThickness, minSize.width −
    /// sidebarMaximum)` from `SettingsWindow.swift` — so Russian and Japanese
    /// do not fit, and nothing said so: SwiftUI centres the overflow, which put
    /// the picker at x = 7.5 where the page's inset is 20 and ran Refresh 13 pt
    /// past the edge. A hundred points narrower again — the same arithmetic on
    /// a smaller window — «Установленные» is cut off and Refresh is *outside*
    /// the pane, so the list cannot be reloaded at all.
    ///
    /// **`ViewThatFits` rather than a threshold constant**, and the difference
    /// is the eight languages. A number here would be one number for all of
    /// them: 559.5 is what Japanese needs and Chinese fits its segments in 317,
    /// so a constant tuned for the widest gates the menu on seven languages
    /// that never needed it — which is the house rule about a control gated
    /// above a width nobody reaches, read from the other end. `ViewThatFits`
    /// asks the control itself, in the language it is actually drawing, and the
    /// answer moves with the strings rather than with a comment.
    ///
    /// The fallback is a menu, not a compressed segmented control: a segmented
    /// control under pressure truncates its labels, and «Уста…» beside «Обно…»
    /// is four words nobody can tell apart.
    ///
    /// **And it decides the whole page's shape, not just the bar's.** Swept a
    /// point at a time on the real page, 2026-09-16, the segmented bar first
    /// fits at en/zh/de below 400 pt · fr 466 · pt 482 · es 554 · ru 566 ·
    /// ja 572, while `HomebrewSplit` dropped the inspector at 560 — so a
    /// Russian window dragged across 560…566 reorganised twice in six points
    /// and a Japanese one twice in twelve. (Those are the bar's widths before
    /// `upgradeAll` reserved its slot; with it, the one boundary below is
    /// es 581 · ru 593 · ja 599 and 560 elsewhere.) `.frame(minWidth:)` on the segmented
    /// candidate puts the split's own floor into that candidate's ideal width,
    /// so the one question `ViewThatFits` answers is «is this pane wide enough
    /// for the whole wide page» — `max(560, what the bar needs here)` — and
    /// `managerBody` reads the answer rather than measuring the width again.
    ///
    /// **What it costs, said plainly.** In the five languages whose bar fits
    /// under 540 — the narrowest pane a person can open — the switcher now
    /// becomes a menu between 540 and 560, where its segments would still have
    /// fitted. That band is the bottom 20 pt of everything reachable, the page
    /// is already in its one-column shape throughout it, and in exchange the
    /// narrow page is one page in all eight languages instead of two. The
    /// alternative was to move the split, and the split cannot be moved to meet
    /// a boundary that sits at a different width in every language.
    ///
    /// **The padding moved inside the candidates** so the number here is the
    /// pane's threshold and not the pane's threshold less its own insets: with
    /// the padding outside, `ViewThatFits` is offered `pane − 2 ×
    /// HelmLayout.formInset` and a floor written as 560 would have gated the
    /// page at 600.
    private var headerBar: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(.segmented)
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                .frame(minWidth: HomebrewSplit.masterAndInspector, alignment: .leading)
                .preference(key: PageIsWideKey.self, value: true)
            headerRow(.menu)
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                .preference(key: PageIsWideKey.self, value: false)
        }
    }

    /// One shape of the bar. Both are built here, from one `Picker` and one
    /// Refresh, so the two cannot drift into offering different things — the
    /// reason `detail` has exactly one builder per kind of subject.
    private func headerRow(_ style: SegmentPickerStyle) -> some View {
        HStack(spacing: HelmSpace.s5) {
            // Over `allCases`, not three rows spelled by hand: a segment
            // whose label was forgotten used to be a segment with no row at
            // all, reachable from nowhere and visible in no test.
            // `Segment.label` is the `switch` that cannot forget one.
            Picker(HelmA11y.whatToShow, selection: $hb.segment) {
                ForEach(HomebrewViewModel.Segment.allCases, id: \.self) { segment in
                    Text(segment.label).tag(segment)
                }
            }
            .modifier(style)
            .labelsHidden()
            // Its own width, not 300: the control asks 302 pt in English
            // and 494 in Japanese, so a fixed number clipped four
            // languages and centred the rest — which walked the row's left
            // edge from 20 pt to 75.5 while every row below it starts at 20.
            // It is also what `ViewThatFits` above measures: a picker free to
            // compress fits every pane and tells the bar nothing.
            .fixedSize()
            .onChange(of: hb.segment) { _, seg in
                Task { await refresh(seg) }
            }
            Spacer(minLength: 0)
            upgradeAll
            Button {
                Task { await refresh(hb.segment) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .helmSteadySpin(hb.running)
            }
            .buttonStyle(.borderless)
            .disabled(hb.running)
            .help(HbStr.refreshList)
            .accessibilityLabel(HbStr.refreshList)
        }
    }

    /// **«Обновить всё», in the bar where the page's other verbs are — and
    /// taking the same room in all four segments whether or not it is drawn.**
    ///
    /// It was a bar of its own between the header and the updates list: a
    /// second strip carrying one button, present in one segment, which is a
    /// row of chrome the page pays for in height every time Обновления is
    /// open. The action belongs beside Refresh.
    ///
    /// **Reserved rather than conditional, and that is the whole of the
    /// design.** `headerBar` puts `HomebrewSplit.masterAndInspector` into the
    /// segmented candidate's ideal width, so what the bar asks for is what
    /// decides whether the page draws two columns at all
    /// (`ThePageReorganisesOnceTests`). A control that appears in one segment
    /// would make that answer depend on the segment — and switching to
    /// Обновления at a pane in the band would drop the inspector in the one
    /// segment whose rows are things to act on. So both branches build the
    /// same control and only its visibility differs; the width is the same
    /// number in every segment, and the page has one boundary.
    ///
    /// **A glyph and not the word, which is the price of that.** Measured
    /// 2026-09-16 with the real button in all eight languages, the word is
    /// zh 76 · ja 87 · en 94 · pt 109 · ru 111 · es 116 · de 127 · fr 132 pt.
    /// Reserved in every segment, the word and its gap add to what the bar
    /// already needs — by that arithmetic about 676 pt in Russian and 670 in
    /// Spanish, not swept: a hundred points of window in which the inspector
    /// would disappear because of a button. The glyph costs a fraction of
    /// that, and this one *was* swept on the real page with the slot reserved:
    /// the boundary stays at 560 in en · zh · fr · de · pt and moves to
    /// es 581 · ru 593 · ja 599, from 560 · 566 · 572.
    ///
    /// The symbol is the one this module already draws for «there is an update
    /// here» — in the row's marker and on the package screen — so the bulk act
    /// and the single fact are said with one mark. It carries the word in
    /// `help` and in its accessibility label, which is what a glyph-only
    /// control owes.
    @ViewBuilder
    private var upgradeAll: some View {
        let offered = hb.segment == .updates && !hb.outdated.isEmpty
        let button = Button {
            hb.upgradeAll()
        } label: {
            Image(systemName: "arrow.up.circle")
        }
        .buttonStyle(.borderless)
        .disabled(hb.running)
        .help(HbStr.upgradeAll)
        .accessibilityLabel(HbStr.upgradeAll)

        if offered {
            button
        } else {
            // Keeps the slot and takes the control out of the tree a reader
            // walks: a disabled button nobody can reach is still something
            // VoiceOver stops on, in three segments where it means nothing.
            button.hidden()
        }
    }

    @ViewBuilder
    private func listArea(singleColumn: Bool) -> some View {
        switch hb.segment {
        case .installed: installedList(singleColumn: singleColumn)
        case .updates: updatesList(singleColumn: singleColumn)
        case .search: searchView(singleColumn: singleColumn)
        case .health: healthList(singleColumn: singleColumn)
        }
    }

    /// What `brew doctor` found and what `brew config` said, under one heading
    /// each, in one list.
    ///
    /// **Two kinds of thing on one list, and every sentence kept.** The three
    /// readings `brew doctor` can be in are still three — «Checking this Mac…»,
    /// «Nothing to fix» and «Homebrew did not answer» are the distinction this
    /// segment turns on, and an empty list that was *measured* is not the empty
    /// list nobody could take. What has changed is where that sentence goes: a
    /// Mac whose findings could not be read still has a configuration to draw,
    /// so the sentence becomes a row under its own heading instead of taking
    /// the whole pane. `HealthScreen.of` decides which of the two, and a test
    /// reads it rather than a `body`.
    ///
    /// No description line whatever the pane's width: a finding's body is prose, often
    /// several lines of it, and one clipped line of it in a row says less than
    /// nothing. The title is the row.
    @ViewBuilder
    private func healthList(singleColumn: Bool) -> some View {
        switch HealthScreen.of(hb.doctor, config: hb.configGroups) {
        case let .sentence(note):
            // The whole segment is this one sentence, so it is centred rather
            // than sitting in a list with nothing else in it.
            if note == .busy {
                HelmBusyState(Self.healthNote(note))
            } else {
                HelmEmptyState(message: Self.healthNote(note))
            }
        case let .groups(checkup, configuration):
            // `Section`, not rows with a heading drawn by hand: a section
            // header is not selectable, which is the whole of what a heading in
            // a selectable list has to be.
            //
            // **`header:` rather than a bare string, which is a different
            // question from that one.** `Section("…")` is still a `Section` and
            // still not selectable; what it also is, is the only place in the app
            // that lets macOS *draw* the heading — 13 pt semibold in sentence
            // case, which is the same weight as the rows under it and the exact
            // shape `HelmSectionTitle`'s own doc comment names as what the
            // redesign replaced. So this page had two list headings in the app's
            // voice (`configDetail`'s and the inspector's) and two in the
            // system's, on one screen. `LeftoversSettingsPage` is the same
            // construction to the line — `HelmSectionTitle` inside a
            // `Section(header:)` of an inset `List` — and `HelmSectionTitle` is
            // what every section heading in the app is set in bar one:
            // `OrphansView` builds its own header out of
            // `HelmText.sectionHeading`, which is the section *face* and a step
            // larger. `command grep -rn 'HelmSectionTitle\|HelmText.sectionHeading' Sources`
            // is the list; the majority is not close.
            List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
                Section(header: sectionHeader(HbStr.headingCheckup)) {
                    ForEach(checkup) { row in healthRow(row, singleColumn: singleColumn) }
                }
                if !configuration.isEmpty {
                    Section(header: sectionHeader(HbStr.headingConfiguration)) {
                        ForEach(configuration) { group in
                            HStack(spacing: HelmSpace.s3) {
                                Text(HbStr.configSectionName(group.section))
                                Spacer(minLength: 0)
                                goesToItsOwnScreen(singleColumn)
                            }
                            .helmListRow()
                            .helmOpensAScreen(singleColumn)
                        }
                    }
                }
            }
            // No inset of its own. It carried `.padding(.horizontal,
            // HelmSpace.s5)`, which put this page's rows 12 pt further in than
            // the rows of every other list in the app — and the row treatment
            // `helmListRow` exists to put this page *with* those two screens.
            // `.listStyle(.inset)` is where Uninstaller, Orphans, Disk,
            // Autopilot and Duplicates all stop.
            .listStyle(.inset)
        }
    }

    /// The heading over a group of rows, in the app's own voice rather than the
    /// system's.
    ///
    /// The trait is said here as well as by `Section(header:)`, for the reason
    /// `OrphansView` gives at its own header: the trait is a set, so saying it
    /// twice costs nothing and never saying it costs the rotor the only two
    /// landmarks this segment has.
    private func sectionHeader(_ title: String) -> some View {
        HelmSectionTitle(title).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func healthRow(_ row: HealthRow, singleColumn: Bool) -> some View {
        switch row {
        case let .issue(issue):
            issueRow(issue, singleColumn: singleColumn)
        case let .note(note):
            // **Not selectable, because there is nothing to select.** A note is
            // the sentence standing in for findings there are none of, and a
            // row that highlights and then describes nothing in the inspector
            // is a row that looks broken.
            HStack(spacing: HelmSpace.s3) {
                // **Waiting moves.** `HealthScreen.of` puts this sentence in a
                // row rather than in the centred `HelmBusyState` whenever
                // `brew config` has anything to draw beside it — which it
                // almost always does, because `refresh` asks it first on
                // purpose, and it is fast where `brew doctor` is the slowest
                // query in the module. So the ordinary Состояние wait was a
                // plain 36 pt text row with **no progress indicator anywhere on
                // the page**, while every other wait in this module and in the
                // app spins. The refusal keeps the still row it had: there is
                // nothing on its way to indicate.
                if note == .busy { ProgressView().controlSize(.small) }
                Text(Self.healthNote(note))
                    .foregroundStyle(HelmText.quiet)
            }
            .helmListRow()
            .selectionDisabled()
        }
    }

    /// The sentence each reading draws, apart from the views that draw it —
    /// the same reason `severityWord` is out here: which reading says which
    /// sentence is a decision a test can hold, and a `body` is not.
    static func healthNote(_ note: HealthNote) -> String {
        switch note {
        case .busy: return HbStr.examiningThisMac
        case .clean: return HbStr.nothingToFix
        case .unexaminable: return HbStr.couldNotExamine
        }
    }

    /// A row of the health list: the finding's title, and nothing else.
    /// Same shape as `pkgRow` — no button, at any width — since selecting is
    /// what reaches the one place an action ever draws.
    ///
    /// **The severity badge is not here, and that is a measurement rather than
    /// a preference.** The master column is pinned at 310 pt, so the title has
    /// about 286 pt whatever the window does; the badge took roughly 50 of them
    /// plus a step, and the two findings this Mac's own `brew doctor` produces
    /// read «Caution Calling `postflight` is depre…» and «Caution Some installed
    /// formulae are…» — cut mid-word to make room for a word that is the same on
    /// both rows. Moving it to the trailing edge was the other candidate and
    /// buys nothing: with a `Spacer` between them the title competes for the
    /// same width and truncates at the same character, only further left.
    ///
    /// **Where the severity went, and why nobody loses it.** `issueDetail`
    /// draws the same `HelmBadge` at full size beside the full title, one
    /// selection away and — above the threshold — on the same screen. That badge
    /// carries `severityWord`, so the difference between a `.danger` finding and
    /// a `.caution` one is a **word**, not a hue: it never lived in the tint,
    /// and a reader who cannot see colour reads it exactly as anyone else does.
    /// What this row drops, it drops for everybody equally.
    private func issueRow(_ issue: DoctorIssue, singleColumn: Bool) -> some View {
        HStack(spacing: HelmSpace.s3) {
            // One line, like `pkgRow`'s name and for the same reason: the row
            // is the handle and `issueDetail` beside it carries the whole
            // title.
            //
            // **It said two, and two was never what it drew.** Measured
            // 2026-09-15 with a 73-character title in a 286 pt column: the row
            // came out one line tall either way, because a `Text` in an
            // `HStack` beside a `Spacer` is compressed to one line and
            // truncated rather than allowed to wrap — `lineLimit(2)` permits a
            // second line and nothing here asks for one. So this is the number
            // that says what happens, and it is also the one that keeps saying
            // it if a future layout stops compressing.
            Text(issue.title).lineLimit(1)
            Spacer(minLength: 0)
            goesToItsOwnScreen(singleColumn)
        }
        .helmListRow()
        .helmOpensAScreen(singleColumn)
    }

    /// What the console says beside «Failed», when the engine knew more than an
    /// exit code.
    ///
    /// **A `switch` over every reason, with no `default:`.** This was an `if`
    /// against one reason, so a second one — a `brew doctor` fix the engine
    /// judged again and would not run — drew a bare «Failed» with nothing
    /// saying why, which is a refusal reaching the page as an empty fact.
    /// `.stopped` is nil because the arm above this one draws its own pill: the
    /// person asked for that end, and it is not a failure to explain.
    static func failureNote(_ reason: OpFailureReason?) -> String? {
        guard let reason else { return nil }
        switch reason {
        case .brewMissing: return HbStr.brewGone
        case .stopped: return nil
        case .fixRefused: return HbStr.fixNotRunnable
        }
    }

    /// The badge's word and the badge's tint, apart from the views that draw
    /// them: which severity reads as which word is a decision a test can hold,
    /// and a `body` is not somewhere a test can reach.
    /// The title of the question a press on Run raises, and the sentence under
    /// it — apart from the view that draws them, for `severityWord`'s reason:
    /// which act is asked about in which words is a decision a test can hold.
    ///
    /// nil is «this fix raises no question», which is `FixAsk.runsOnThePress`
    /// and never reaches `pendingFix` — `askToRunFix` sends that one straight
    /// to the engine. It is nil rather than an empty string so that the one
    /// caller cannot draw a dialog with no title if that ever stops being true.
    static func fixQuestion(_ fix: DoctorFix) -> String? {
        switch FixAsk.of(fix.argv) {
        case .runsOnThePress: return nil
        // The same words the Uninstall button's own dialog uses, naming the
        // same thing: it is the same act, reached by a different control.
        case let .uninstalls(name): return HbStr.confirmUninstall(name)
        // Nothing to name but the command, and naming nothing is how a dialog
        // becomes a reflex.
        case .unrecognised: return HbStr.confirmRunTheFix(Self.commandLine(fix))
        }
    }

    /// The second sentence, and only where there is one to say: a heading over
    /// a reassurance nobody checked is `stillNeededBy`'s own lesson.
    static func fixQuestionNote(_ fix: DoctorFix) -> String? {
        switch FixAsk.of(fix.argv) {
        case .uninstalls: return HbStr.uninstallIsPermanent
        case .runsOnThePress, .unrecognised: return nil
        }
    }

    /// The command as a person would type it, which is what the well shows and
    /// what a question about an unnamed command has to name. Spelled once here
    /// rather than at the two places that draw it.
    static func commandLine(_ fix: DoctorFix) -> String {
        (["brew"] + fix.argv).joined(separator: " ")
    }

    static func severityWord(_ severity: DoctorSeverity) -> String {
        switch severity {
        case .caution: return HbStr.severityCaution
        case .danger: return HbStr.severityDanger
        }
    }

    static func severityTint(_ severity: DoctorSeverity) -> Color {
        switch severity {
        case .caution: return HelmSignal.warning
        case .danger: return HelmSignal.danger
        }
    }

    private func installedList(singleColumn: Bool) -> some View {
        listOrEmpty(hb.installed, reading: hb.installedReading,
                    nothing: HbStr.noneInstalled, unanswerable: HbStr.couldNotList,
                    waiting: HbStr.packagesLoading) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask, singleColumn: singleColumn,
                   hasUpdate: hasUpdate(pkg.id),
                   desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList(singleColumn: Bool) -> some View {
        VStack(spacing: 0) {
            // No bar of its own any more: «Обновить всё» is in the page's own
            // bar, beside Refresh, and `upgradeAll` says why it is reserved
            // there rather than drawn only here.
            listOrEmpty(hb.outdated, reading: hb.outdatedReading,
                        nothing: HbStr.upToDate, unanswerable: HbStr.couldNotCheckForUpdates,
                        waiting: HbStr.checkingForUpdates) { pkg in
                // A pinned formula and a cask can both carry a badge here — the
                // parser does not refuse a `pinned` flag on a cask entry, even
                // though `brew pin` only ever sets one on a formula
                // (`BrewOutdatedParser.swift`) — so both may be drawn without
                // choosing between them.
                pkgRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask,
                       singleColumn: singleColumn, pinned: pkg.pinned,
                       desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
            }
        }
    }

    private func searchView(singleColumn: Bool) -> some View {
        VStack(spacing: 0) {
            HelmSearchField(text: $query, placeholder: HbStr.searchPlaceholder,
                            onSubmit: {
                                searching?.cancel()
                                searching = Task { await hb.search(query) }
                            })
                .frame(height: 22)
                .padding(.horizontal, HelmLayout.formInset)
                .padding(.top, HelmSpace.s5)
                .padding(.bottom, HelmSpace.s5)
            Divider()
            if SearchDisplay.state(query: query, reading: hb.searchReading) == .prompt {
                HelmEmptyState(message: HbStr.typeToSearch)
            } else {
                listOrEmpty(hb.searchHits, reading: hb.searchReading,
                            nothing: HbStr.noResults, unanswerable: HbStr.couldNotSearch,
                            waiting: HbStr.searching) { hit in
                    pkgRow(name: hit.name, detail: nil, isCask: hit.isCask, singleColumn: singleColumn,
                           alreadyInstalled: PackageStanding.installedVersion(of: hit.id,
                                                                              installed: hb.installed) != nil,
                           desc: singleColumn ? hb.description(name: hit.name, isCask: hit.isCask) ?? " " : nil)
                }
            }
        }
    }

    // MARK: - The inspector

    /// The one dispatcher over `InspectorState`, and the only thing either
    /// container mounts.
    ///
    /// Above `HomebrewSplit`'s threshold this sits beside the list, in
    /// `managerBody`'s `HStack`; below it, `managerBody` puts the same builder
    /// full width behind `backBar`, in place of the list. Neither call site
    /// passes it anything beyond what it already reads off `hb` — the width
    /// only decides which container it sits in, never what it draws, which is
    /// what keeps a wide reading and a narrow one from disagreeing about what
    /// one subject offers.
    ///
    /// It decides nothing itself: `InspectorState.of` answers what is being
    /// looked at, and each kind of subject has exactly one builder below.
    ///
    /// **The empty sentence belongs to the segment.** «Select a package» is
    /// wrong over a list of findings, and one key means one thing — a finding
    /// is not a package, and the languages that inflect the two differently are
    /// the ones a shared key would have read worst in.
    private var detail: some View {
        Group {
            switch InspectorState.of(segment: hb.segment, selected: hb.selected,
                                     installed: hb.installed, outdated: hb.outdated,
                                     loadedOutdated: hb.loadedOutdated,
                                     hits: hb.searchHits, issues: hb.issues,
                                     config: hb.configGroups,
                                     descriptions: hb.descriptions) {
            case .nothingSelected:
                HelmEmptyState(message: hb.segment == .health ? HbStr.selectAFindingOrASection
                                                              : HbStr.nothingSelected)
            case .nothingToSelect:
                // **Nothing, deliberately.** The list next to this already
                // carries the sentence for whichever of the three readings it
                // is in, and that sentence is the page's one account of the
                // fact; a second one here in the inspector's own words is the
                // defect this page has just been repaired of twice. What is
                // wrong with the invitation is not its wording — there is no
                // wording that makes «choose one» true of a list with nothing
                // in it — so the column describes nothing, which is what there
                // is to describe. It comes back the moment a row does.
                Color.clear
            case let .package(subject):
                packageDetail(subject)
            case let .issue(issue):
                issueDetail(issue)
            case let .configSection(group):
                configDetail(group)
            }
        }
    }

    /// **The one builder for what a package draws — there is no second one.**
    ///
    /// Scrolled, because the second tier is as long as the package makes it:
    /// openssl@3 answers with three tiles, a homepage, a tap, two notes, a
    /// dependency chip and four lines of caveats, and below `HomebrewSplit`'s
    /// threshold this has the console under it as well. A fixed column simply
    /// clipped the caveats.
    private func packageDetail(_ subject: InspectorSubject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                // **The action stands next to the name it acts on, not at the
                // pane's far edge.** It used to sit behind the `Spacer`, which
                // is the drawing's own arrangement and was right at the width
                // the drawing was made for — but nothing bounded this column,
                // so at the pane the app draws (measured 2026-09-15: 984 pt,
                // a 649 pt inspector) «Uninstall» was 549 pt from the package
                // name and read as belonging to the pane rather than to the
                // package. The `Spacer` stays, after the button: it is what
                // keeps the row left-packed once the column is bounded.
                HStack(spacing: HelmSpace.s3) {
                    Text(subject.name).font(HelmText.sectionHeading)
                    if subject.isCask { HelmBadge(HbStr.cask, tint: .purple) }
                    if !subject.version.isEmpty {
                        Text(subject.version).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    }
                    inspectorAction(subject)
                    Spacer(minLength: 0)
                }
                // The same fact the row's marker carries, said in words
                // here and with the same symbol — the one place
                // `InspectorSubject.updates` is read, since `.installed`'s
                // own action stays Uninstall either way.
                //
                // **And the thing it announces, offered where it is
                // announced.** Measured 2026-09-16 on the 984 pt pane: this
                // line sat 12 pt under a 75.5 × 24 Uninstall button and
                // nothing on the screen acted on it — the upgrade was a
                // segment away, reachable only by leaving the package. The
                // module has had the path all along, gated and tested; what
                // it did not have was the button beside the sentence.
                //
                // **The two actions are a row apart and that is the whole of
                // the ordering.** The destructive one keeps the title row,
                // where it belongs to the name; the constructive one sits with
                // the sentence it answers, `HelmSpace.s5` below. A press meant
                // for one cannot land on the other, and the uninstall question
                // is untouched. Weight is carried by ink rather than by
                // position: `destructive` marks Uninstall, and Upgrade is a
                // plain button, so the louder of the two is the one that
                // cannot be taken back.
                if case let .available(_, pinned) = subject.updates {
                    HStack(spacing: HelmSpace.s3) {
                        Label(HbStr.updateAvailable, systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(HelmSignal.warning)
                            .font(HelmText.rowDetail)
                        // A pinned formula is listed and not offered, here for
                        // the same reason `inspectorAction` gives one segment
                        // over: `brew upgrade` answers it with "…is pinned",
                        // so the button could only ever fail.
                        if pinned {
                            HelmBadge(HbStr.pinned)
                        } else {
                            upgradeAction(subject)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let desc = subject.desc {
                    Text(desc).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
                // **The second tier, and only when there is an answer.**
                // Everything above this line is a function of the lists the
                // page already holds, so it is on screen the moment a row
                // is clicked. `hb.info` is nil while `brew info` is out and
                // stays nil when it refused — and a refusal, a missing brew
                // and a document this build cannot read are one nil
                // (`HomebrewEngine.info`), none of which has measured
                // anything. So there is no spinner in place of the package
                // and no tile with nothing in it: the tier is absent.
                if let info = hb.info { PackageSecondTier(info: info, size: hb.size) }
            }
            .helmInspectorColumn()
        }
    }

    /// **The one builder for what a `brew doctor` finding draws.**
    ///
    /// Three shapes, and which one is drawn is `DoctorFix.kind`'s answer and
    /// not this view's: a fix the engine judged `.runnable` gets the command
    /// and a button that acts; a `.copyOnly` fix gets the command, a copy
    /// affordance and **no button that acts**; an issue with no fix at all gets
    /// neither, because there is nothing to say and a well with nothing in it
    /// is a promise this page cannot keep.
    ///
    /// Scrolled for the reason `packageDetail` is: a `brew doctor` body is
    /// prose of whatever length brew felt like, and the postflight block on
    /// this Mac is three lines one of which is a full path.
    private func issueDetail(_ issue: DoctorIssue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                HStack(spacing: HelmSpace.s3) {
                    HelmBadge(Self.severityWord(issue.severity),
                              tint: Self.severityTint(issue.severity))
                    Text(issue.title).font(HelmText.sectionHeading)
                    Spacer(minLength: 0)
                }
                // Brew's own words, kept as brew wrote them — the parser keeps
                // body lines verbatim on purpose (`DoctorParser.body`), and a
                // body line naming a path is somebody's path.
                Text(issue.body)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .textSelection(.enabled)
                if let fix = issue.fix { fixBlock(fix) }
            }
            .helmInspectorColumn()
        }
    }

    /// **The one builder for what a group of `brew config` lines draws.**
    ///
    /// The heading, the lines under it as they were read, and one action: the
    /// whole document on the pasteboard. Scrolled for the reason the two
    /// builders above are — nine lines under the Homebrew heading, each with a
    /// path in it, below `HomebrewSplit`'s threshold with the console under it.
    ///
    /// The key is drawn as Homebrew spells it and the value in a monospaced
    /// face: eight of the eighteen are a version, a path or a hash, which is
    /// what a reader compares character by character rather than reads as a
    /// word. The value is selectable, because a person who is not copying the
    /// whole document is copying exactly one of these.
    private func configDetail(_ group: ConfigGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                // A header to VoiceOver as well as to the eye: it introduces
                // the rows under it, so the rotor has to be able to jump to it
                // (`AHeadingIsAHeadingToTheRotorTests`).
                Text(HbStr.configSectionName(group.section))
                    .font(HelmText.sectionHeading)
                    .accessibilityAddTraits(.isHeader)
                // A `Grid`, so the key column is as wide as the widest key and
                // not a number written down here. The drawing fixes that column
                // at 150 pt; a constant would be a threshold nothing measures,
                // and while these keys are Homebrew's own and never translated,
                // Homebrew adds keys between releases — `Core cask tap` and
                // `Metal Toolchain` are both newer than the capture this was
                // designed against — so the column has to be able to grow.
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: HelmSpace.s5, verticalSpacing: HelmSpace.s3) {
                    ForEach(group.lines) { line in
                        GridRow {
                            Text(line.key)
                                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                            Text(line.value)
                                // The one spelling this module gives a monospaced
                                // face, settled on the shape the rest of the tree
                                // uses. `HelmText.rowDetail.monospaced()` drew the
                                // identical face — `rowDetail` *is* `.subheadline`
                                // — so this is vocabulary rather than a size:
                                // three spellings of one decision read as three
                                // decisions.
                                .font(.system(.subheadline, design: .monospaced))
                                .textSelection(.enabled)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }
                // **The document, not this group, and not Helm's reading of
                // it.** `BrewConfig.text` is what brew printed byte for byte;
                // the lines above are a reading regrouped under headings this
                // app invented, and a bug report asks for the first. Drawn only
                // when there is a document — a button that copies an empty
                // string is a button that silently does nothing.
                //
                // A pasteboard write from the view, the way `fixBlock` and
                // `LogView` already do it: nothing leaves this process, so
                // there is no engine command for it.
                if let text = hb.config?.text {
                    Button(HbStr.copyForABugReport) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
            }
            .helmInspectorColumn()
        }
    }

    /// The command, whose label says whose reading it is, and whatever this app
    /// may do with it.
    ///
    /// **No control here attributes the command to Homebrew.** Measured on this
    /// Mac (Homebrew 7.0.1, 2026-09-15): `brew doctor` printed 1,194 bytes and
    /// not one `brew …` command line, so `uninstall <name>` is Helm's reading
    /// of a heading brew printed and not a line brew wrote —
    /// `HbStr.helmReadsThisAs` and `HbStr.brewNamedNoCommand` are the two
    /// places that say so, and the second is drawn for both kinds of fix,
    /// because the provenance is a fact about the command rather than about the
    /// button beside it.
    ///
    /// The copy is a pasteboard write from the view, the way `KeysTable` and
    /// `LogView` already do it: there is no engine command for it, because
    /// nothing leaves this process.
    private func fixBlock(_ fix: DoctorFix) -> some View {
        let command = Self.commandLine(fix)
        return VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(HbStr.helmReadsThisAs).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            HStack(spacing: HelmSpace.s3) {
                Text(command)
                    // A text *style* rather than a frozen 11 pt, for the reason
                    // `PackageSecondTier`'s caveats block states two files away:
                    // `.subheadline` resolves to the same 11 at the default
                    // setting and follows the system text size from there, which
                    // a literal cannot. It is the spelling every deliberate
                    // monospaced face in the tree takes (`HelmExplainer`,
                    // `HostsTable`, `LayoutLists`).
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // `ctl` and not `card`: the design system's small field wells
                    // take the control corner and its block-sized ones the
                    // card's. This is one line of text, and at `card` it was the
                    // roundest well in the inspector — rounder than the fact
                    // tiles, the quiet notes and the multi-line caveats block
                    // beside it, every one of which is `ctl`, and as round as the
                    // 160 pt console. The smaller box had the bigger corner. The
                    // fill token's doc comment names a well of this kind as its
                    // call site and says nothing about radius, which is what the
                    // note here used to cite.
                    .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmSurface.wellFill))
                Button(HbStr.copyTheFix) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                if fix.kind == .runnable {
                    // **The destructive one, drawn and behaved as the
                    // destructive one it is.** Measured 2026-09-16: it sat 6 pt
                    // from Copy, at the same weight, with no role and no
                    // question — and the command behind it on this Mac is
                    // `brew uninstall periphery`, the same irreversible
                    // deletion the Uninstall button raises a dialog for. The
                    // role is what makes it read differently; `askToRunFix` is
                    // what makes it *behave* differently, and `FixAsk` decides
                    // which of the two commands on the allowlist that means —
                    // `brew cleanup` still runs on the press, because a cached
                    // download comes back.
                    //
                    // The step before it is `HelmSpace.s5` where the row's own
                    // is `s3`: a press meant for Copy that lands on this one is
                    // not a press anybody can take back.
                    //
                    // **And the role is kept without being trusted to show.**
                    // The gap and the question both landed and the weight did
                    // not: measured again on 2026-09-16, «Скопировать» and
                    // «Выполнить» sampled the *same* darkest pixel, `#303030`
                    // at 11.49:1 on the same `#EFEFEF` fill. `helmDestructive`
                    // carries what a person can actually see; the role stays
                    // because it is still what this button means.
                    Button(role: .destructive) { hb.askToRunFix(fix) } label: {
                        Text(HbStr.runTheFix).helmDestructive()
                    }
                    .disabled(hb.running)
                    .padding(.leading, HelmSpace.s5 - HelmSpace.s3)
                }
            }
            Text(HbStr.brewNamedNoCommand).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            if fix.kind == .copyOnly {
                Text(HbStr.helmDoesNotRunThis).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
        }
    }

    /// The narrow screen's way out of `packageDetail`, back to the list —
    /// `select(nil)` is the whole of it, the same setter the list's own
    /// deselect already calls, so there is nothing new to hold for this. Same
    /// shape as Disk's own `BreadcrumbBar` back control — a bordered glyph
    /// button, `.help` for a sighted press and `.accessibilityLabel` for
    /// VoiceOver, which is what a control with no word needs to be read at all.
    private var backBar: some View {
        HStack(spacing: HelmSpace.s3) {
            Button {
                hb.select(nil)
            } label: {
                Image(systemName: "chevron.backward")
            }
            .help(HbStr.back)
            .accessibilityLabel(HbStr.back)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// Looked up by `BrewKey` id and never by name — `docker` is both a
    /// formula and a cask, which is the defect `BrewKey` was written against.
    @ViewBuilder
    private func inspectorAction(_ subject: InspectorSubject) -> some View {
        switch subject.action {
        case .uninstall:
            Button {
                guard let pkg = hb.installed.first(where: { $0.id == subject.id }) else { return }
                // Every other destructive action in Helm asks first; this one
                // removed a cask — an app — on a single click.
                Task { await hb.askToUninstall(pkg) }
            } label: {
                Text(HbStr.uninstall).helmDestructive()
            }
            .disabled(hb.running)
        case .upgrade:
            upgradeAction(subject)
        case .install:
            Button(HbStr.install) {
                guard let hit = hb.searchHits.first(where: { $0.id == subject.id }) else { return }
                hb.install(hit)
            }
            .disabled(hb.running)
        case .pinned:
            // Still listed — somebody who pinned a formula still wants to know
            // a newer one exists — but not offered. `brew upgrade` answers a
            // pinned formula with "…is pinned", so the button could only ever
            // fail.
            HelmBadge(HbStr.pinned)
        }
    }

    /// **The one Upgrade button — the Обновления segment's action and the one
    /// beside «Update available» on Установленные are the same builder.**
    ///
    /// Two call sites, one body, for the reason `detail` gives at the top of
    /// this section: a package that offers an upgrade from one screen and a
    /// different upgrade from another is a defect with nothing to catch it.
    /// Looked up by `BrewKey` id and never by name — `docker` is both a formula
    /// and a cask.
    private func upgradeAction(_ subject: InspectorSubject) -> some View {
        Button(HbStr.upgrade) {
            guard let pkg = hb.outdated.first(where: { $0.id == subject.id }) else { return }
            hb.upgrade(pkg)
        }
        .disabled(hb.running)
    }

    /// Whether an installed package has an update waiting, for the row's dot.
    /// The same reading `InspectorState.of` takes for the same package, so the
    /// row and the inspector cannot disagree about one fact.
    private func hasUpdate(_ id: String) -> Bool {
        if case .available = PackageStanding.updates(for: id, outdated: hb.outdated,
                                                      loadedOutdated: hb.loadedOutdated) {
            return true
        }
        return false
    }

    // MARK: - Console

    private var console: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HStack(spacing: HelmSpace.s4) {
                statusPill
                Spacer()
                if hb.running {
                    // The only way out of a brew that will not finish — the
                    // module used to be dead until an app restart.
                    Button(HbStr.stop) { hb.stop() }.controlSize(.small)
                }
                Button(HbStr.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HelmSpace.s1) {
                        ForEach(Array(hb.consoleLines.enumerated()), id: \.offset) { i, line in
                            // The same spelling the fix command above takes, and
                            // for the same reason: a text style follows the
                            // system text size where a frozen 11 does not.
                            Text(line).font(.system(.subheadline, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: hb.consoleLines.count) { _, _ in
                    withAnimation(HelmMotion.interface) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: Self.consoleHeight)
            // `card` and not `ctl`, which is the other half of the fix command's
            // note above: this is a block-sized well and those take the card's
            // corner. The token's own doc comment names console output as its
            // call site.
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(HelmSurface.wellFill))
        }
        .padding(HelmSpace.s5)
    }

    /// **How tall the console is: ten lines of what `brew` printed.**
    ///
    /// It was a bare `160` with no reason at the line or anywhere else, and 160
    /// is on no ladder — the space ladder stops at 40 and the type scale is not
    /// a scale of heights. Ten lines is the derivation: `brew upgrade` announces
    /// each step with a `==>` line and fetches under it, so a window that holds
    /// fewer than a handful of those shows the fetch and not what it belongs to,
    /// while one twice this deep is the page it arrives into.
    ///
    /// **Computed, not held, and both halves of the arithmetic follow the system
    /// text size.** At the default setting `.subheadline` is 11 pt and SF Mono at
    /// 11 lays out on a 13 pt line, so ten of them with `HelmSpace.s1` between —
    /// the step the console's own stack uses — is 10 × 13 + 9 × 2 = 148, twelve
    /// short of the number that was written here. A `static let` would freeze at
    /// whatever the size was when the app launched, which is the reason
    /// `HelmMotion`'s reduce-motion flag is a computed property too: a person who
    /// raises their interface text size while Helm is open would otherwise get
    /// bigger lines in a box measured for the smaller ones.
    ///
    /// The face is asked for its own metrics rather than an `NSLayoutManager`,
    /// which allocates per access and would be doing it per line of output;
    /// measured on this Mac the two agree to within a twentieth of a point
    /// (12.955 against 13.0), and the line is rounded up for that reason.
    private static var consoleHeight: CGFloat {
        let face = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
        let line = (face.ascender - face.descender + face.leading).rounded(.up)
        return line * CGFloat(consoleLinesShown)
            + HelmSpace.s1 * CGFloat(consoleLinesShown - 1)
    }

    /// The ten. Its own constant so the derivation above has something to name
    /// and a test has something to multiply by.
    static let consoleLinesShown = 10

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            HStack(spacing: HelmSpace.s3) { ProgressView().controlSize(.small); Text(hb.op.label).font(HelmText.rowDetail) }
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end; a red octagon would call their own
            // press a defect.
            Label(HbStr.stopped, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
        case .failed:
            HStack(spacing: HelmSpace.s3) {
                Label(HbStr.failed, systemImage: "xmark.octagon.fill").foregroundStyle(HelmSignal.danger).font(HelmText.rowDetail)
                if let note = Self.failureNote(hb.op.reason) {
                    Text(note).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Row helpers

    /// A row of the master list — no button, at any width
    /// (`design/Main.dc.html:86-98`): `dot · name(ellipsis) · badge · trailing`.
    /// The one place an action ever draws is `packageDetail`, whether it sits
    /// beside this list or replaces it — selecting a row is what reaches it,
    /// which is the only way a selectable `List` row and a button never fight
    /// the same click.
    ///
    /// `desc` is passed only from the single-column branch, where there is no
    /// package view beside the row to carry it — the row has the whole pane
    /// to itself there, and keeps the description rather than dropping it,
    /// since nothing else on that screen says what the package is before it is
    /// selected. `nil` omits the second line entirely rather than reserving an
    /// empty one, since the split layout never re-flows a row that never draws
    /// a description at all.
    private func pkgRow(name: String, detail: String?, isCask: Bool, singleColumn: Bool,
                        pinned: Bool = false, alreadyInstalled: Bool = false,
                        hasUpdate: Bool = false, desc: String? = nil) -> some View {
        HStack(spacing: HelmSpace.s3) {
            if hasUpdate {
                // The only carrier of "an update exists" for this row, and a
                // glyph rather than a dot for two reasons it takes both to
                // settle. SwiftUI does not make a `Shape` an accessibility
                // element, so the `.accessibilityLabel` a `Circle` used to
                // carry here sat on nothing and VoiceOver read the row without
                // the fact; an `Image` is an element and the label lands on it.
                // And a dot has colour and no form, so the one reader who most
                // needs a second channel — somebody who sees the screen but not
                // the orange — had a marker that differs from "no marker" by
                // hue alone. The arrow is `packageDetail`'s own symbol for this
                // same fact, so the row and the package screen say it one way.
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(HelmSignal.warning)
                    .font(HelmText.rowDetail)
                    .accessibilityLabel(HbStr.updateAvailable)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: HelmSpace.s3) {
                    Text(name).lineLimit(1)
                    // Only when it says something: 46 of 47 rows were
                    // "formula", and a label with one value is an ornament. A
                    // pinned formula and a cask can both carry a badge here —
                    // see `updatesList`'s own comment on why that is
                    // representable even though `brew pin` never does it.
                    if isCask { HelmBadge(HbStr.cask, tint: .purple) }
                    if pinned { HelmBadge(HbStr.pinned) }
                    if alreadyInstalled { HelmBadge(HbStr.alreadyInstalled) }
                    if let detail { Text(detail).font(.caption2).foregroundStyle(HelmText.quiet) }
                }
                if let desc {
                    Text(desc).font(.caption2).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            goesToItsOwnScreen(singleColumn)
        }
        .helmListRow()
        .helmOpensAScreen(singleColumn)
    }

    /// **The mark that says a row leads somewhere, and only where it does.**
    ///
    /// Below `HomebrewSplit`'s threshold a press on a row replaces the list
    /// with that row's own screen; above it the same press moves the inspector
    /// beside the list and the pane does not change. So the chevron is drawn
    /// from the one fact that decides which of those happens, and never
    /// otherwise: a chevron over a row that opens nothing is a promise the
    /// wide page does not keep.
    ///
    /// `HelmText.separator` is the token for exactly this — "marks, never
    /// text", 3.07:1 light and 4.07:1 dark, over the 3:1 a mark that carries
    /// meaning answers to. It is hidden from the accessibility tree because it
    /// is not a control and says nothing the row does not: the row itself
    /// carries the hint, in `helmOpensAScreen`.
    @ViewBuilder
    private func goesToItsOwnScreen(_ singleColumn: Bool) -> some View {
        if singleColumn {
            Image(systemName: "chevron.forward")
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.separator)
                .accessibilityHidden(true)
        }
    }

    /// Which list a segment is showing, and therefore which one Refresh
    /// reloads. There were two answers: switching to Search reloaded nothing,
    /// while pressing Refresh on Search reloaded the installed list behind it.
    /// The switcher's answer is the right one — Search has nothing cached to
    /// refresh, and a button that quietly reloads a list you are not looking at
    /// is a button that did nothing.
    private func refresh(_ segment: HomebrewViewModel.Segment) async {
        switch segment {
        case .installed: await hb.refreshInstalled()
        case .updates: await hb.refreshOutdated()
        // Nothing cached to reload: the hits belong to a query, and reloading
        // the installed list behind a search is a button that did nothing.
        case .search: break
        // Both halves of this segment, and `brew config` first on purpose: it
        // is one fast local run where `brew doctor` is the slowest query in the
        // module, so asking it first puts the Configuration heading on screen
        // while the Checkup one is still saying what it is waiting for.
        case .health:
            await hb.refreshConfig()
            await hb.refreshDoctor()
        }
    }

    /// `T.ID == String`: every list here is keyed by a `BrewKey` id, which is
    /// also what `hb.selection` holds — no `String(describing:)` conversion
    /// needed at the boundary.
    ///
    /// **Three sentences for three states, and the third one is new.** This
    /// took one `empty:` that went nil while a query was out, which is two
    /// states in one optional and no room at all for the third: a `brew` that
    /// refused left the flag behind it down for ever, so the pane drew the
    /// spinner and «Reading the package list…» over a question nothing was
    /// going to answer, with no timeout anywhere in the UI. `ListScreen` is
    /// where the three are told apart.
    private func listOrEmpty<T: Identifiable, Row: View>(_ items: [T], reading: ListReading,
                                                         nothing: String, unanswerable: String,
                                                         waiting: String,
                                                         @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        Group {
            switch ListScreen.of(isEmpty: items.isEmpty, reading: reading) {
            case .nothing:
                HelmEmptyState(message: nothing)
            case .unanswerable:
                // The same still drawing as `.nothing` and a different
                // sentence: nothing is on its way, so nothing moves, and what
                // separates the two is the only thing that can — the words.
                HelmEmptyState(message: unanswerable)
            case .waiting:
                // `HelmBusyState()` is the bare spinner its own doc comment
                // names as one of the three shapes it exists to end; the caller
                // still has to say what is being waited on.
                HelmBusyState(waiting)
            case .rows:
                // A `List` with no selection has no focusable rows at all —
                // arrow keys did nothing. Selecting is also how the inspector
                // is reached, so this is the row's only door into the app now.
                // No `.onTapGesture`, no `.listRowBackground`: macOS draws the
                // system selection itself.
                List(items, selection: Binding(get: { hb.selected }, set: { hb.select($0) })) { item in
                    row(item)
                }
                // No inset of its own, for the reason `healthList`'s own list
                // gives: `.listStyle(.inset)` is where every other list in the
                // app stops, and 12 pt more of it put this page's rows further
                // in than theirs.
                .listStyle(.inset)
            }
        }
    }

}

/// **The inspector's one bound, and the whole of what keeps it from stretching.**
///
/// Every builder the inspector mounts ends on this instead of on a padding and
/// an `.infinity` frame of its own — which is what the three of them used to
/// end on, and the reason the pane the app actually draws handed a tile holding
/// `2.11.4` 308 pt and a sentence 625. `HelmLayout.readingColumn` carries the
/// number and the measurement behind it.
///
/// Read outwards: the content is capped at the reading column, the padding is
/// paid around that, and the outermost frame takes the pane's whole width so
/// the block is **centred** in it. The last of the three is not decoration —
/// SwiftUI hit-tests a scroll view's *content*, so a block that stopped at
/// 468 pt would leave the rest of the inspector dead to the wheel, which is the
/// half of this shape `helmSettingsColumn`'s own doc comment was written about.
///
/// **`.top`, not `.topLeading`, and the two halves of that are separate
/// decisions.** Horizontally the block is centred, because once it is capped the
/// pane is wider than it: measured 2026-09-16 at the pane the app draws, the
/// bounded column sat at 347…791 of a 335…984 inspector, which is 193 pt of
/// nothing down one side and none down the other — a column shoved into a
/// corner rather than a column. Vertically it stays at the top, because a detail
/// pane fills from the top and centring would float a two-line finding in the
/// middle of the pane.
///
/// Centring costs nothing where there is nothing to centre: below
/// `HomebrewSplit`'s threshold the inspector is narrower than the cap, so the
/// block already fills it and both readings are the same number — measured at
/// the threshold's own 268 pt pane, 304…548 before and after. It is not a
/// margin: the width of the content never changes, only where the slack falls.
///
/// Private to this file: one module draws it, and the house's rule is that a
/// thing two modules draw moves to `HelmUI` rather than that everything starts
/// there.
/// **The two shapes the segment switcher takes, as a modifier rather than a
/// value.** `PickerStyle`'s conformers are different types, so the style cannot
/// be held in a `let` and handed to one `Picker`; written as two `Picker`s
/// behind an `if`, the control would be two views rather than one, and SwiftUI
/// interpolates between two states of one view and never between two views.
private enum SegmentPickerStyle: ViewModifier {
    case segmented
    case menu

    @ViewBuilder
    func body(content: Content) -> some View {
        switch self {
        case .segmented: content.pickerStyle(.segmented)
        case .menu: content.pickerStyle(.menu)
        }
    }
}

private extension View {
    func helmInspectorColumn() -> some View {
        frame(maxWidth: HelmLayout.readingColumn, alignment: .topLeading)
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// **One row of either list on this page: how tall it is, and what does not
/// divide it from the next one.**
///
/// The height is `HelmSpace.s7` where it was 34 — a number off the ladder, and
/// one that a `List`'s own row insets then took to a 42 pt step for a single
/// line of content, measured 2026-09-15 on both of this page's lists. A step
/// that long over one line of text reads as a settings form rather than as a
/// list of things.
///
/// **And the separator goes with it.** macOS draws one per row across the whole
/// column, which at this step is a rule every few lines in a 310 pt column of
/// short names; the approved drawing has a hairline at a twentieth of that
/// weight, which macOS's is not and cannot be made into. What separates one row
/// from the next instead is the row's own content and the selection macOS draws
/// under it — and in the health list the two `Section` headers, which carry the
/// structure the rules were standing in for. Hiding them also puts this page
/// with the app's other two list screens rather than against them:
/// `OrphansView` and `DiskResultView` hide theirs already, and Homebrew was the
/// one list still drawing rules.
private extension View {
    func helmListRow() -> some View {
        frame(minHeight: HelmSpace.s7)
            .listRowSeparator(.hidden)
    }

    /// **What a row promises when pressing it changes the whole pane.**
    ///
    /// The chevron beside the row is a mark and not an element
    /// (`goesToItsOwnScreen` says why), so without this the single-column list
    /// reads to VoiceOver exactly as the two-column one does — same rows, same
    /// names, and no word anywhere about the press replacing the list. A hint
    /// is the right channel for it: it is read after the row's own name, it is
    /// skipped by anyone who has hints off, and it does not become part of the
    /// row's name the way a label would.
    ///
    /// Nothing at all above the threshold, rather than a hint saying something
    /// milder: there the press moves the inspector beside the list, which is a
    /// selection and is what macOS already announces for a selectable row.
    @ViewBuilder
    func helmOpensAScreen(_ singleColumn: Bool) -> some View {
        if singleColumn {
            accessibilityHint(HbStr.opensItsOwnScreen)
        } else {
            self
        }
    }
}

/// **The mark a control that destroys something carries, spelled once.**
///
/// `role: .destructive` is not it, and this page is where that was measured
/// rather than assumed. On a 984 pt pane in light appearance, 2026-09-16: the
/// darkest pixel of «Скопировать»'s label was `#303030` on the button's own
/// `#EFEFEF` fill, 11.49:1 — and of «Выполнить», a `role: .destructive`
/// bordered button 12 pt away, exactly `#303030` at exactly 11.49:1. On this
/// macOS the role changes what a button *does* in a menu and nothing at all
/// about what it draws, so the only marked thing about it was the source.
/// `GeneralSettingsPage` had already found this out for a form row — "the role
/// reaches menus and dialogs, not form rows" — and this is the same sentence
/// about a bordered button.
///
/// **On the label, and deliberately not on the button.** The same token handed
/// to the *button* is SwiftUI's tint channel and macOS fills the whole control
/// with it — a pale red button, which is the louder mark and was measured too.
/// It fails where it matters least often and worst: `disabled` while a `brew`
/// runs, the tinted control dimmed to `#F1CBCA` on `#F9EEEE`, **1.31:1**, a
/// word gone rather than a word greyed. On the label the fill lightens to
/// `#F7F7F7` and the word stays legible at 3.60:1.
///
/// Nor `.borderedProminent` with a danger tint: in a window that is not key —
/// a settings pane behind a sheet, and every still this house verifies by
/// photograph — it drew a `#EFEFEF` fill under a `#FFFFFF` label, 1.1:1.
///
/// **What it measures on the surface it is actually on**, which is the button's
/// own fill and not the white pane behind it. Light: `#D9584D` on `#EFEFEF`,
/// 3.35:1 where its neighbour reads 11.49:1. Dark: `#F16B60` on `#3F3F3F`,
/// 3.52:1 where its neighbour reads 8.40:1. The two labels are no longer one
/// ink in either appearance, which is what
/// `TheDestructiveControlIsMarkedInInkTests` reads back.
///
/// **And the shortfall is named rather than hidden.** `HelmSignal.danger` is
/// specified at 4.52:1 and that is against white; a bordered button's fill is
/// six per cent darker, which puts the pure token at 3.94:1 there and the
/// antialiased rendering at the 3.35:1 above — under the 4.5:1 the token was
/// chosen for. Every styling that clears it needs either a control that is not
/// a button (a borderless label on the white pane measures the token's own
/// 4.52:1) or a second, darker danger for text in `HelmSignal`. Neither is
/// this page's to decide.
extension View {
    func helmDestructive() -> some View { foregroundStyle(HelmSignal.danger) }
}
