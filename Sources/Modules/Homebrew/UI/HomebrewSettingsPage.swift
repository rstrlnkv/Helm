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

    init(vm: ModuleViewModel) { hb = HomebrewViewModel.shared(vm: vm) }

    var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                managerBody
            } else {
                installScreen
            }
            // `.failed` as well, and that is not cosmetic: an operation the
            // engine refused before it launched anything writes no console
            // line, so a refusal with an empty console had no console to be
            // drawn in and reached the page as nothing at all.
            if !hb.consoleLines.isEmpty || hb.running || hb.op.phase == .failed {
                Divider()
                console
            }
        }
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
        // (`LeavingThePageRetiresAnUninstallAskTests`). This page also carries
        // `.helmIdlesOffScreen()`, so hiding the app or occluding the Settings
        // window unmounts this subtree and fires this too — dismissing a
        // confirmation dialog the person had left standing on screen rather
        // than leaving it to act later on a reading taken before the
        // interruption, which is the right call for the app's only
        // irreversible deletion.
        .onDisappear { hb.cancelUninstall() }
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
        // A count that has not arrived is not a count of zero. The list reloads
        // after every operation, and for that second the line read
        // "0 packages · 0 updates · 0 casks" over a machine with 53 of them.
        guard hb.loadedInstalled else { return HbStr.packagesLoading }
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
                .pickerStyle(.segmented).labelsHidden()
                // Its own width, not 300: the control asks 226.5 pt in English
                // and 370.5 in Japanese, so a fixed number clipped four
                // languages and centred the rest — which walked the row's left
                // edge from 20 pt to 75.5 while every row below it starts at 20.
                .fixedSize()
                .onChange(of: hb.segment) { _, seg in
                    Task { await refresh(seg) }
                }
                Spacer(minLength: 0)
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
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
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
                if HomebrewSplit(availableWidth: proxy.size.width).showsInspector {
                    HStack(spacing: HelmSpace.s5) {
                        listArea(showsDesc: false)
                            .frame(minWidth: 240, idealWidth: 310, maxWidth: 310)
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
                    listArea(showsDesc: true)
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
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func listArea(showsDesc: Bool) -> some View {
        switch hb.segment {
        case .installed: installedList(showsDesc: showsDesc)
        case .updates: updatesList(showsDesc: showsDesc)
        case .search: searchView(showsDesc: showsDesc)
        case .health: healthList()
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
    /// No description line and no `showsDesc`: a finding's body is prose, often
    /// several lines of it, and one clipped line of it in a row says less than
    /// nothing. The title is the row.
    @ViewBuilder
    private func healthList() -> some View {
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
            // a selectable list has to be, and macOS draws it.
            List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
                Section(HbStr.headingCheckup) {
                    ForEach(checkup) { row in healthRow(row) }
                }
                if !configuration.isEmpty {
                    Section(HbStr.headingConfiguration) {
                        ForEach(configuration) { group in
                            Text(HbStr.configSectionName(group.section))
                                .helmListRow()
                        }
                    }
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, HelmSpace.s5)
        }
    }

    @ViewBuilder
    private func healthRow(_ row: HealthRow) -> some View {
        switch row {
        case let .issue(issue):
            issueRow(issue)
        case let .note(note):
            // **Not selectable, because there is nothing to select.** A note is
            // the sentence standing in for findings there are none of, and a
            // row that highlights and then describes nothing in the inspector
            // is a row that looks broken.
            Text(Self.healthNote(note))
                .foregroundStyle(HelmText.quiet)
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

    /// A row of the health list: the severity as a badge, then the title.
    /// Same shape as `pkgRow` — no button, at any width — since selecting is
    /// what reaches the one place an action ever draws.
    private func issueRow(_ issue: DoctorIssue) -> some View {
        HStack(spacing: HelmSpace.s3) {
            HelmBadge(Self.severityWord(issue.severity),
                      tint: Self.severityTint(issue.severity))
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
        }
        .helmListRow()
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

    private func installedList(showsDesc: Bool) -> some View {
        listOrEmpty(hb.installed, empty: hb.loadedInstalled ? HbStr.noneInstalled : nil,
                    busy: HbStr.packagesLoading) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask,
                   hasUpdate: hasUpdate(pkg.id),
                   desc: showsDesc ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList(showsDesc: Bool) -> some View {
        VStack(spacing: 0) {
            if !hb.outdated.isEmpty {
                HStack {
                    Spacer()
                    Button(HbStr.upgradeAll) { hb.upgradeAll() }.disabled(hb.running)
                }.padding(8)
                Divider()
            }
            listOrEmpty(hb.outdated, empty: hb.loadedOutdated ? HbStr.upToDate : nil,
                        busy: HbStr.checkingForUpdates) { pkg in
                // A pinned formula and a cask can both carry a badge here — the
                // parser does not refuse a `pinned` flag on a cask entry, even
                // though `brew pin` only ever sets one on a formula
                // (`BrewOutdatedParser.swift`) — so both may be drawn without
                // choosing between them.
                pkgRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask,
                       pinned: pkg.pinned,
                       desc: showsDesc ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
            }
        }
    }

    private func searchView(showsDesc: Bool) -> some View {
        VStack(spacing: 0) {
            HelmSearchField(text: $query, placeholder: HbStr.searchPlaceholder,
                            onSubmit: {
                                searching?.cancel()
                                searching = Task { await hb.search(query) }
                            })
                .frame(height: 22)
                .padding(.horizontal, HelmLayout.formInset)
                .padding(.top, 12)
                .padding(.bottom, HelmSpace.s5)
            Divider()
            if SearchDisplay.state(query: query, hasHits: !hb.searchHits.isEmpty) == .prompt {
                HelmEmptyState(message: HbStr.typeToSearch)
            } else {
                listOrEmpty(hb.searchHits, empty: HbStr.noResults, busy: HbStr.searching) { hit in
                    pkgRow(name: hit.name, detail: nil, isCask: hit.isCask,
                           alreadyInstalled: PackageStanding.installedVersion(of: hit.id,
                                                                              installed: hb.installed) != nil,
                           desc: showsDesc ? hb.description(name: hit.name, isCask: hit.isCask) ?? " " : nil)
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
                if case .available = subject.updates {
                    Label(HbStr.updateAvailable, systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .font(HelmText.rowDetail)
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
                if let info = hb.info { PackageSecondTier(info: info, sizeBytes: hb.size) }
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
                                .font(HelmText.rowDetail.monospaced())
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
        let command = (["brew"] + fix.argv).joined(separator: " ")
        return VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(HbStr.helmReadsThisAs).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            HStack(spacing: HelmSpace.s3) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The token's own doc comment names a well of this kind as
                    // its call site; the console above uses the same fill.
                    .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                        .fill(HelmSurface.wellFill))
                Button(HbStr.copyTheFix) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                if fix.kind == .runnable {
                    // The press hands the engine the argv and nothing else:
                    // `HomebrewEngine.runDoctorFix` reads the installed list
                    // again and judges it again, so what this starts is not
                    // what this page judged.
                    Button(HbStr.runTheFix) { hb.runDoctorFix(fix) }
                        .disabled(hb.running)
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
            Button(HbStr.uninstall) {
                guard let pkg = hb.installed.first(where: { $0.id == subject.id }) else { return }
                // Every other destructive action in Helm asks first; this one
                // removed a cask — an app — on a single click.
                Task { await hb.askToUninstall(pkg) }
            }
            .disabled(hb.running)
        case .upgrade:
            Button(HbStr.upgrade) {
                guard let pkg = hb.outdated.first(where: { $0.id == subject.id }) else { return }
                hb.upgrade(pkg)
            }
            .disabled(hb.running)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
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
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: hb.consoleLines.count) { _, _ in
                    withAnimation(HelmMotion.interface) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: 160)
            // The token's own doc comment names console output as its call site.
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(HelmSurface.wellFill))
        }
        .padding(12)
    }

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(hb.op.label).font(HelmText.rowDetail) }
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end; a red octagon would call their own
            // press a defect.
            Label(HbStr.stopped, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
        case .failed:
            HStack(spacing: 6) {
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
    private func pkgRow(name: String, detail: String?, isCask: Bool,
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
                HStack(spacing: 6) {
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
        }
        .helmListRow()
    }

    /// `empty` is nil while the first query is still out: "nothing installed"
    /// must not be shown to someone who is simply waiting for the list.
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
    private func listOrEmpty<T: Identifiable, Row: View>(_ items: [T], empty: String?, busy: String,
                                                         @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        Group {
            if items.isEmpty, let empty {
                HelmEmptyState(message: empty)
            } else if items.isEmpty {
                // `HelmBusyState()` is the bare spinner its own doc comment
                // names as one of the three shapes it exists to end; the caller
                // still has to say what is being waited on.
                HelmBusyState(busy)
            } else {
                // A `List` with no selection has no focusable rows at all —
                // arrow keys did nothing. Selecting is also how the inspector
                // is reached, so this is the row's only door into the app now.
                // No `.onTapGesture`, no `.listRowBackground`: macOS draws the
                // system selection itself.
                List(items, selection: Binding(get: { hb.selected }, set: { hb.select($0) })) { item in
                    row(item)
                }
                .listStyle(.inset)
                .padding(.horizontal, HelmSpace.s5)
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
/// the block sits at its leading edge. The last of the three is not decoration
/// — SwiftUI hit-tests a scroll view's *content*, so a block that stopped at
/// 468 pt would leave the rest of the inspector dead to the wheel, which is the
/// half of this shape `helmSettingsColumn`'s own doc comment was written about.
///
/// Private to this file: one module draws it, and the house's rule is that a
/// thing two modules draw moves to `HelmUI` rather than that everything starts
/// there.
private extension View {
    func helmInspectorColumn() -> some View {
        frame(maxWidth: HelmLayout.readingColumn, alignment: .topLeading)
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
}
