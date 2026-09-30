import AppKit
import SwiftUI
import HelmUI
import Module_Homebrew_Engine

// The three `Identifiable` conformances that used to sit here are on the models
// themselves now, spelled once through `BrewKey` — the same key the description
// cache is read by, which is the half that has to agree with the row.

struct HomebrewSettingsPage: View {
    @ObservedObject private var hb: HomebrewViewModel

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
        // **The console arrives by taking its height off everything above it**
        // (`ThePageMovesRatherThanCutsTests` measures the travel), and it used
        // to do that in one frame: the first install of the session put a
        // divider and the well under the page, and the list, the status bar and
        // whatever row the eye was on jumped up together. One token, on
        // the fact that decides it — the same one the other list screens use
        // (`UninstallerSettingsPage`, which carries three of these).
        //
        // `showsConsole` and not `hb.consoleLines.count`: the lines arriving
        // scroll, which `console` already animates, and re-running the page's
        // layout per line of `brew` output is a different thing entirely.
        // The band stands on the manager's own bands or on the install screen,
        // never on a scroll view, so it is lit from the first frame
        // (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
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
                       message: HbStr.notInstalledBody()) {
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
            // The split is asked of the pane, not of the window: `HomebrewSplit`
            // carries the measured threshold, and a `private var` inside `body`
            // would be out of a test's reach (`HomebrewSplit.swift`'s own reason).
            //
            // **The width decides the container, `detail` decides the
            // content.** Above the threshold the list and the subject sit side
            // by side; below it, selecting a row replaces the list with that
            // same view at full width, with `backBar` above it to return —
            // there is exactly one builder per kind of subject, called from
            // both places, so a wide inspector and a narrow screen cannot
            // drift into offering two different things for one of them.
            GeometryReader { proxy in
                let split = HomebrewSplit(availableWidth: proxy.size.width)
                if hb.segment == .health {
                    // **Not a master and a subject, at any width.** Состояние
                    // is one page whose findings open where they stand
                    // (`HomebrewHealthPage`), so the split is not asked and
                    // no selection exists to put a back bar over.
                    listArea(singleColumn: false)
                } else if split.showsInspector {
                    // **No stack spacing — the list meets the divider.** The
                    // owner's own choice, shown a screenshot of the list
                    // falling short of its own block: an equal `HelmSpace.s5`
                    // either side of `Divider()` left the master column 12 pt
                    // short of the line it was supposed to run to, and only
                    // the list's own side of that gap was to close. So the
                    // stack itself carries none, `HomebrewSplit.masterWidth`
                    // hands the master column the 12 pt the gap used to
                    // spend, and the 12 pt on the inspector's side moves into
                    // `detail`'s own leading padding below — the distance
                    // from the divider to the inspector's content is
                    // unchanged, only where it is spent has moved
                    // (`TheGapBesideTheListClosesOnlyThereTests`).
                    HStack(spacing: 0) {
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
                            // The gap the stack's own spacing used to spend
                            // between the divider and this column — kept here
                            // rather than in the stack, so it stays on the
                            // inspector's side alone.
                            .padding(.leading, HelmSpace.s5)
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
        // **The page's controls, in the window's own `NSToolbar`
        // (`SettingsToolbar`), through the contract every module page shares**
        // (`HelmWindowToolbar.swift` in `HelmUI`). The SwiftUI-bridge-era
        // `ToolbarContent` this replaced, and the `switcherFits`/`paneWidth`
        // machinery it decided a narrower shape from, are gone — deleted
        // 2026-09-23 together with `TheSwitcherGivesWayBeforeRefreshTests`,
        // the test that was their only remaining reader. **Which zone gives
        // way first when the bar is tight is no longer left to AppKit's own
        // overflow order**: `SettingsToolbar`'s own fold mechanism collapses
        // the tabs to a one-item capsule with a menu (`HelmToolbarSwitcher`'s
        // `compact`) before a search field opening would otherwise squeeze
        // the whole strip into the toolbar's «»» menu, and only the
        // near-simultaneous-overflow floor still falls back to that menu at
        // all.
        //
        // **Upgrade all leaves the actions capsule off Обновления rather than
        // being dimmed on every segment** (`isVisible`) — the owner's revised
        // order, 2026-09-22: it used to enter and leave the old bridged
        // `ToolbarItemGroup` and move the segmented control the person had
        // just pressed (measured at 37 pt in one frame), which mounting it
        // disabled on every segment was written to avoid. The capsule
        // (`HelmToolbarActionsCapsule`, `HelmUI/DesignSystem/HelmToolbarActions.swift`)
        // replaced a per-action `NSToolbarItem` with one custom-view item
        // reserving the full width of every declared action: Refresh, always
        // visible, stays exactly still while Upgrade All's own glass morphs
        // in and out of it, which is what closed the smaller jump a reviewer
        // had measured — Refresh and the search field still shifting by the
        // hidden item's own width — that hiding a *separate* item left open.
        .helmWindowToolbar(HelmPageToolbarContent(
            tabs: HomebrewViewModel.Segment.allCases.map {
                HelmToolbarTab(id: $0.rawValue, title: $0.label, symbol: $0.symbol)
            },
            selectedTab: Binding(
                get: { hb.segment.rawValue },
                set: { hb.segment = HomebrewViewModel.Segment(rawValue: $0) ?? hb.segment }),
            actions: [
                HelmToolbarAction(id: "upgradeAll", title: HbStr.upgradeAll,
                                  symbol: "arrow.down.to.line",
                                  isEnabled: !hb.running && !hb.outdated.isEmpty,
                                  isVisible: hb.segment == .updates) {
                    hb.upgradeAll()
                },
                HelmToolbarAction(id: "refresh", title: HbStr.refreshList,
                                  symbol: "arrow.clockwise", isEnabled: !hb.running) {
                    Task { await refresh(hb.segment) }
                }
            ],
            // **On every tab, and the view model owns the query now** — moved
            // out of this page's own `@State` 2026-09-24, the owner's
            // decision: typing filters whichever list is on screen, and
            // `HomebrewViewModel.queryMoved` starts the pause toward an
            // automatic `brew search` when that filter finds nothing. Return
            // is `searchNow()`, which asks at once, with no pause and no
            // minimum length, unless that word is already answered or still
            // out — a refusal earns nothing kept, so Return asks again then.
            search: HelmToolbarSearch(
                prompt: HbStr.searchPlaceholder,
                text: Binding(get: { hb.query }, set: { hb.query = $0 })) {
                hb.searchNow()
            }
        ), token: HomebrewDescriptor.id.rawValue)
        // On the page rather than on the picker: a toolbar item's view is
        // hosted by the window's toolbar and its lifetime is the toolbar's,
        // so a change handler hung on it is not something this page can
        // count on being mounted when the segment moves.
        .onChange(of: hb.segment) { _, segment in
            Task { await refresh(segment) }
        }
    }

    @ViewBuilder
    private func listArea(singleColumn: Bool) -> some View {
        switch hb.segment {
        case .installed: installedList(singleColumn: singleColumn)
        case .updates: updatesList(singleColumn: singleColumn)
        // No columns and no inspector: the tab is one page (`HomebrewHealthPage`),
        // which `managerBody` mounts before it asks the split anything.
        case .health: HomebrewHealthPage(hb: hb)
        }
    }

    /// The heading over a group of rows, in the app's own voice rather than the
    /// system's.
    ///
    /// The header trait is carried by `HelmSectionTitle` itself, so the rotor
    /// keeps the landmark over the "Available to install" rows without a
    /// second statement of it here.
    private func sectionHeader(_ title: String) -> some View {
        HelmSectionTitle(title)
    }

    /// The sentence a package list's own section draws instead of its rows,
    /// or nil when `screen` says to draw the rows themselves — apart from
    /// `packageList`'s `body` for `severityWord`'s reason: which reading
    /// says which sentence is a decision a test can hold. `notes` are the
    /// three sentences each call site already carries (`installedList`'s
    /// "No packages installed.", `updatesList`'s "Everything is up to date.",
    /// and the two refusals beside them); `.noMatches` earns the one sentence
    /// every tab shares, since a query hiding every row says the same thing
    /// on both.
    static func ownListNote(_ screen: ListScreen,
                            notes: (nothing: String, unanswerable: String, waiting: String))
        -> (text: String, busy: Bool)? {
        switch screen {
        case .rows: return nil
        case .noMatches: return (HbStr.noMatches, false)
        case .nothing: return (notes.nothing, false)
        case .unanswerable: return (notes.unanswerable, false)
        case .waiting: return (notes.waiting, true)
        }
    }

    /// **Not selectable, because there is nothing to select.** A note is
    /// the sentence standing in for rows there are none of, and a row that
    /// highlights and then describes nothing in the inspector is a row that
    /// looks broken. Shared by both package tabs' empty rows and by the
    /// "Available to install" section's own three sentences — one builder,
    /// so a note row cannot drift into three shapes across the page.
    private func noteRow(_ text: String, busy: Bool = false) -> some View {
        HStack(spacing: HelmSpace.s3) {
            if busy { ProgressView().controlSize(.small) }
            Text(text).foregroundStyle(HelmText.quiet)
        }
        .helmListRow()
        .selectionDisabled()
    }

    /// **The "Available to install" section's own three sentences, and its
    /// rows.** Shared by both package tabs' `listOrEmpty`, the only place it is
    /// drawn: Состояние has no such section.
    ///
    /// `marksUpdates` reserves the update mark's slot on Установленные so a
    /// hit's name lines up with the installed rows above it — `pkgRow`'s own
    /// reason for taking `false` rather than nil there.
    @ViewBuilder
    private func availableRows(_ section: AvailableSection, hits: [SearchHit],
                               singleColumn: Bool, marksUpdates: Bool) -> some View {
        switch section {
        case .searching: noteRow(HbStr.searching, busy: true)
        case .nothingFound: noteRow(HbStr.noResults)
        case .unanswerable: noteRow(HbStr.couldNotSearch)
        case .found:
            ForEach(hits) { hit in
                pkgRow(name: hit.name, detail: nil, isCask: hit.isCask, singleColumn: singleColumn,
                      hasUpdate: marksUpdates ? false : nil,
                      desc: singleColumn ? hb.description(name: hit.name, isCask: hit.isCask) ?? " " : nil)
            }
        }
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
    ///
    /// Takes the whole state, not the reason alone, because `installerFailed`
    /// names the installer's exit code and the code is on the state.
    static func failureNote(_ op: OpState, language: AppLanguage = AppLanguage.current) -> String? {
        guard let reason = op.reason else { return nil }
        switch reason {
        case .brewMissing: return HbStr.brewGone(language: language)
        case .stopped: return nil
        case .fixRefused: return HbStr.fixNotRunnable(language: language)
        case .toolsNotInstalled: return HbStr.toolsNotInstalled(language: language)
        case .authorizationDeclined: return HbStr.authorizationDeclined(language: language)
        case .prefixNotPrepared: return HbStr.prefixNotPrepared(language: language)
        case .installerFailed: return HbStr.installerFailed(code: op.exitCode, language: language)
        }
    }

    /// The running pill's words: what is waited for while the operation waits,
    /// the operation's name otherwise — the engine's label as the engine wrote
    /// it (`upgrade wget`, in English in every language), except for the
    /// install of Homebrew itself, which `HbStr.operationName` words in the
    /// person's language.
    /// Static, so a test can reach it without a view.
    static func pillTitle(for op: OpState, language: AppLanguage = AppLanguage.current) -> String {
        op.waiting == nil ? HbStr.operationName(op.label, language: language)
                          : HbStr.waitingForTools(language: language)
    }

    /// Stop's title while the operation is the wait for Apple's tools: the
    /// press ends the waiting and leaves Apple's window to finish. Static, so a
    /// test can reach it without a view.
    static func stopTitle(for op: OpState) -> String {
        op.waiting == .commandLineTools ? HbStr.stopWaiting : HbStr.stop
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

    /// **What the Run button says: whether a question comes before the act.**
    ///
    /// The ellipsis is the Mac's own mark for a control that opens something
    /// rather than doing it, and `FixAsk` is what knows which of the two this
    /// press is — so the mark is read off the same answer that decides whether
    /// the dialog is raised, and cannot claim a question that never comes.
    /// `brew cleanup` runs on the press and keeps the bare word.
    static func runLabel(_ fix: DoctorFix) -> String {
        switch FixAsk.of(fix.argv) {
        case .runsOnThePress: return HbStr.runTheFix
        case .uninstalls, .unrecognised: return HbStr.runTheFixAsking
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

    /// The word on a finding's badge — **and nil for a caution, which has no
    /// badge.** A caution is what nearly every finding is, and a pill saying so
    /// on each row said the same word on all of them; only the severity that
    /// stands out is worded. No `default:` on either switch: a third severity
    /// has to be a build error here, where the decision is made.
    static func severityWord(_ severity: DoctorSeverity) -> String? {
        switch severity {
        case .caution: return nil
        case .danger: return HbStr.severityDanger
        }
    }

    /// The badge's ink, nil exactly where `severityWord` is: a finding with no
    /// badge has no tint to draw.
    static func severityTint(_ severity: DoctorSeverity) -> Color? {
        switch severity {
        case .caution: return nil
        case .danger: return HelmSignal.danger
        }
    }

    /// The window toolbar's own search field filters this list as it is
    /// typed into (`HomebrewViewModel.shownInstalled`), and the "Available to
    /// install" section appears under it when the filter finds nothing and
    /// the pause has run its course, or after Return.
    private func installedList(singleColumn: Bool) -> some View {
        listOrEmpty(hb.installed, shown: hb.shownInstalled, reading: hb.installedReading,
                    nothing: HbStr.noneInstalled, unanswerable: HbStr.couldNotList,
                    waiting: HbStr.packagesLoading,
                    columns: ListColumns(leading: HbStr.columnPackage, trailing: HbStr.tileVersion,
                                         marksUpdates: true),
                    singleColumn: singleColumn, section: hb.section, hits: hb.shownHits) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask, singleColumn: singleColumn,
                   hasUpdate: hasUpdate(pkg.id),
                   desc: singleColumn ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList(singleColumn: Bool) -> some View {
        VStack(spacing: 0) {
            // No bar of its own any more: «Обновить всё» is in the window's
            // own toolbar beside Refresh, declared on `managerBody`'s
            // `.helmWindowToolbar` — visible on this very segment, hidden
            // everywhere else.
            listOrEmpty(hb.outdated, shown: hb.shownOutdated, reading: hb.outdatedReading,
                        nothing: HbStr.upToDate, unanswerable: HbStr.couldNotCheckForUpdates,
                        waiting: HbStr.checkingForUpdates,
                        columns: ListColumns(leading: HbStr.columnPackage, trailing: HbStr.tileVersion,
                                             marksUpdates: false),
                        singleColumn: singleColumn, section: hb.section, hits: hb.shownHits) { pkg in
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
    /// **Only the two package tabs have one.** Состояние is a page whose rows
    /// open in place (`HomebrewHealthPage`), so this is never mounted there and
    /// `InspectorState.of` answers `.nothingToSelect` if it is ever asked.
    ///
    /// **The current tab's own list, after the filter, not the raw answer.**
    /// `InspectorState.of`'s own emptiness check answers off
    /// `hb.installed`/`hb.outdated`, which is the
    /// *unfiltered* Cellar — so a query that hid every row still saw a
    /// non-empty list and invited a choice beside a master saying «Nothing in
    /// this list matches.», a sentence with nothing left to pick. Read once
    /// here rather than inline in the `switch` below, because `detail` is
    /// where the invitation is drawn and the emptiness it is about belongs one
    /// property up from that, beside the other reader of `hb.segment`.
    private var shownEmpty: Bool {
        switch hb.segment {
        case .installed: return hb.shownInstalled.isEmpty
        case .updates: return hb.shownOutdated.isEmpty
        case .health: return true // no inspector on this tab, so nothing to invite a choice of
        }
    }

    private var detail: some View {
        Group {
            switch InspectorState.of(segment: hb.segment, selected: hb.selected,
                                     installed: hb.installed, outdated: hb.outdated,
                                     loadedOutdated: hb.loadedOutdated,
                                     hits: hb.shownHits,
                                     descriptions: hb.descriptions,
                                     shownEmpty: shownEmpty) {
            case .nothingSelected:
                HelmEmptyState(message: HbStr.nothingSelected)
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
                Text(HbStr.uninstallAsking).helmDestructive()
            }
            .disabled(hb.running)
        case .upgrade:
            upgradeAction(subject)
        case .install:
            Button(HbStr.install) {
                guard let hit = hb.shownHits.first(where: { $0.id == subject.id }) else { return }
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
                    Button(Self.stopTitle(for: hb.op)) { hb.stop() }.controlSize(.small)
                }
                Button(HbStr.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
            }
            ConsoleScroll(rows: hb.consoleRows, sequence: hb.consoleSequence)
            // **The inset is outside the scroll view, so its clip sits at the
            // inset.** Padding inside the scrolled content scrolls away with
            // it: the first line was off the top edge at rest only, and once
            // the console scrolled, a line partly cut by the top was cut at the
            // box's edge, its ink a point or two from it. With the padding out
            // here the visible text region is inset from the box on all four
            // sides in every scroll position, and a partly scrolled line is
            // clipped at the inset. The well's fill and corners are on the
            // outer box, below.
            .padding(Self.consoleInset)
            .frame(height: Self.consoleHeight)
            // `card` and not `ctl`: this page's own choice for a block-sized
            // well, not a rule of the design system, which draws its own
            // multi-line well (`helmFieldWell()`) with the control corner.
            // The fix command's one-line field takes the control corner
            // here too. The well's fill,
            // `HelmSurface.wellFill`, is the token whose own doc comment names
            // console output.
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
    /// **The line is what SwiftUI lays out, asked of SwiftUI.** Ten of them with
    /// `HelmSpace.s1` between — the step the console's own stack uses — plus
    /// `consoleInset` above and below. The line used to be read off `NSFont`'s
    /// ascender, descender and leading, which at the default text size is 13 pt,
    /// while SwiftUI sets the same face on a 14 pt line: the pitch drawn was 16
    /// and the formula counted 15, so the box held nine whole lines and the
    /// tenth was cut by the bottom edge with the inset gone.
    ///
    /// **Computed, not held, and it follows the system text size.** A `static
    /// let` would freeze at whatever the size was when the app launched, which is
    /// the reason `HelmMotion`'s reduce-motion flag is a computed property too: a
    /// person who raises their interface text size while Helm is open would
    /// otherwise get bigger lines in a box measured for the smaller ones.
    private static var consoleHeight: CGFloat {
        consoleLine * CGFloat(consoleLinesShown)
            + HelmSpace.s1 * CGFloat(consoleLinesShown - 1)
            + consoleInset * 2
    }

    /// What a console line is drawn in — one declaration, read by the rows and
    /// by the measurement of their height, so the box cannot be sized for a
    /// face the rows are not set in.
    static let consoleFont = Font.system(.subheadline, design: .monospaced)

    /// One line's height, measured the way `SidebarComposerSheet` measures its
    /// note: a hosting controller asked what the text needs (`sizeThatFits`),
    /// which is SwiftUI's own answer and not a second account of it. A
    /// controller per read would be built per line of output, since the page
    /// redraws for each, so the reading is kept against the point size it was
    /// taken at and taken again when the system text size moves — the key is
    /// the size, so the cache cannot go stale the way a `static let` would.
    private static var consoleLine: CGFloat {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        if let held = measuredLine, held.size == size { return held.height }
        let height = NSHostingController(rootView: Text("M").font(consoleFont))
            .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            .height
        measuredLine = (size, height)
        return height
    }

    private static var measuredLine: (size: CGFloat, height: CGFloat)?

    /// **How far the text sits from the box on every side.**
    ///
    /// `HelmSpace.s4`, the step between rows of one list: the monospaced lines
    /// were drawn flush to the well's edges, the first glyph on the left edge
    /// and the first line on the top. The box is taller by twice this, so the
    /// ten lines the derivation above promises are still ten with the inset
    /// taken off the top and the bottom.
    static let consoleInset = HelmSpace.s4

    /// The ten. Its own constant so the derivation above has something to name
    /// and a test has something to multiply by.
    static let consoleLinesShown = 10

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            // Waiting names what it waits for: the label is the operation's own
            // words («install Homebrew»), which say nothing about a window that
            // may be behind this one.
            HStack(spacing: HelmSpace.s3) {
                ProgressView().controlSize(.small)
                Text(Self.pillTitle(for: hb.op)).font(HelmText.rowDetail)
            }
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end; a red octagon would call their own
            // press a defect.
            Label(HbStr.stopped, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .authorizationDeclined:
            // A question answered no: neutral, with the sentence beside it.
            HStack(spacing: HelmSpace.s3) {
                Label(HbStr.cancelled, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
                if let note = Self.failureNote(hb.op) {
                    Text(note).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
            }
        case .failed:
            HStack(spacing: HelmSpace.s3) {
                Label(HbStr.failed, systemImage: "xmark.octagon.fill").foregroundStyle(HelmSignal.danger).font(HelmText.rowDetail)
                if let note = Self.failureNote(hb.op) {
                    Text(note).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Row helpers

    /// A row of the master list — no button, at any width:
    /// `mark · name · badges … version · chevron`. (No path to the drawing: it
    /// is the owner's scratch and untracked, so a line number into it is a
    /// citation no checkout can follow, and it was redrawn since.)
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
                        pinned: Bool = false,
                        hasUpdate: Bool? = nil, desc: String? = nil) -> some View {
        HStack(spacing: HelmSpace.s3) {
            // **nil is «this list never marks updates», and draws no column at
            // all** — the search hits, and the updates list, where every row is
            // outdated and a mark on each would be an ornament. A `Bool` is
            // «this list marks them», and then every row keeps the slot whether
            // or not its own package has an update: rendered 2026-09-16 on the
            // installed list, the marked row's name started a mark's width to
            // the right of every other name in the column, so the one package
            // that wanted attention was the one whose name did not line up.
            // A leading column is the shape Mail's unread dot has always had.
            if let hasUpdate {
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
                Image(systemName: Self.updateMarkSymbol)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning)
                    .accessibilityLabel(HbStr.updateAvailable)
                    // Kept in the layout and taken out of both readings when
                    // there is nothing to say: invisible, and not an element
                    // VoiceOver stops on to read «Update available» over a
                    // package that has none.
                    .opacity(hasUpdate ? 1 : 0)
                    .accessibilityHidden(!hasUpdate)
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
                }
                if let desc {
                    Text(desc).font(.caption2).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // **A column, not a word after the name.** Inline, every version
            // began wherever its name happened to end, so a list of them could
            // not be read down — and «26.8.2 → 26.9.0» is exactly what a person
            // scans the updates list for. At the trailing edge they line up
            // under the column's own heading (`columnHeader`), in figures that
            // do not jump as they change.
            if let detail {
                Text(detail).font(HelmText.figureFont).foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            goesToItsOwnScreen(singleColumn)
        }
        .helmListRow()
        .helmOpensAScreen(singleColumn)
    }

    /// The update mark's symbol — named once because the heading over the
    /// installed list reserves exactly its width (`columnHeader`), and a
    /// heading that reserved a different glyph's would put «Package» a point or
    /// two off the names under it. The symbol and not a built view: the row's
    /// mark has to stay an `Image` at its own call site, which is what
    /// `TheRowsUpdateMarkerIsMoreThanAColourTests` reads.
    static let updateMarkSymbol = "arrow.up.circle.fill"

    /// **The heading over a list's columns: what the names are, and what the
    /// figure at the trailing edge is.**
    ///
    /// A `Section` header inside the `List` rather than a strip above it, which
    /// is the whole of how it lines up: the list insets its headers and rows by
    /// one amount, so nothing here measures an inset. The one thing a header cannot know is
    /// what a row puts at its two edges, so it reserves those widths with the
    /// same views, hidden: the update mark's slot on the installed list, and
    /// the chevron in the single-column pane, which would otherwise push every
    /// version a chevron's width left of «Version».
    ///
    /// In the house's section voice (`HelmSectionTitle`), and marked a header
    /// for the rotor, as `sectionHeader` is.
    private func columnHeader(_ columns: ListColumns, singleColumn: Bool) -> some View {
        HStack(spacing: HelmSpace.s3) {
            if columns.marksUpdates {
                Image(systemName: Self.updateMarkSymbol).font(HelmText.rowDetail).hidden()
            }
            HelmSectionTitle(columns.leading)
            Spacer(minLength: 0)
            if let trailing = columns.trailing { HelmSectionTitle(trailing) }
            goesToItsOwnScreen(singleColumn).hidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    /// reloads. Search is not a case here any more — a `brew search` in
    /// flight is not "cached" the way a package list is, and Refresh has
    /// never reached it; `searchNow()` on the toolbar's own field is the
    /// door to asking brew again.
    private func refresh(_ segment: HomebrewViewModel.Segment) async {
        switch segment {
        case .installed: await hb.refreshInstalled()
        case .updates: await hb.refreshOutdated()
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
    /// **Four sentences for four states, and the fourth is new.** This took
    /// one `empty:` that went nil while a query was out, which is two states
    /// in one optional and no room at all for a third: a `brew` that refused
    /// left the flag behind it down for ever, so the pane drew the spinner and
    /// «Reading the package list…» over a question nothing was going to
    /// answer, with no timeout anywhere in the UI. `.noMatches` is the fourth,
    /// added with the field that filters every tab: rows exist and a query
    /// hides all of them, which is neither an empty answer nor a refusal.
    ///
    /// `shown` is `items` with the query applied — the two are equal when
    /// there is no query, which is what keeps every existing reading of the
    /// three original states unchanged. `section`/`hits` are the "Available
    /// to install" block that may sit under the rows; nil/`[]` draws nothing.
    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], shown: [T], reading: ListReading,
        nothing: String, unanswerable: String, waiting: String,
        columns: ListColumns, singleColumn: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // **The section forces the list shape, even over a list that is
        // itself completely empty.** `ListScreen.of` alone would still read a
        // genuinely empty `installed` as `.nothing` whatever the query says —
        // this Mac's own zero-package fixture drew the same «No packages
        // installed.» sentence whether a search was answering, waiting or
        // refusing, before the section moved inside the `List` this branch
        // draws now. A section is only ever non-nil once a needle has
        // actually been asked about (`AvailableSection.of`), so this cannot
        // force the list shape over an untyped field.
        let screen = ListScreen.of(isEmpty: items.isEmpty, shownIsEmpty: shown.isEmpty,
                                   reading: reading)
        let listShape = ListScreen.forcesListShape(section: section, screen: screen)
        // **One call to `packageList`, not two.** It used to sit once inside
        // this `if` and once in its `else`, so SwiftUI read them as two
        // different views at two different positions in the tree — moving
        // between "no section" and "a section just appeared" tore the table
        // down and rebuilt it, on every keystroke that flipped which branch
        // was taken, which is exactly the identity CLAUDE.md says SwiftUI
        // never interpolates across. `screen` now travels into the one call
        // site instead, and `packageList` reads the sentence for its own
        // reading out of it — the note this list draws for a waiting or
        // refused query no longer disappears the moment the section takes
        // over the shape.
        return Group {
            if listShape {
                packageList(shown, screen: screen, notes: (nothing, unanswerable, waiting),
                           columns: columns, singleColumn: singleColumn,
                           section: section, hits: hits, row: row)
            } else if screen == .waiting {
                // `HelmBusyState()` is the bare spinner its own doc comment
                // names as one of the three shapes it exists to end; the
                // caller still has to say what is being waited on.
                HelmBusyState(waiting)
            } else if screen == .unanswerable {
                // The same still drawing as `.nothing` and a different
                // sentence: nothing is on its way, so nothing moves, and what
                // separates the two is the only thing that can — the words.
                HelmEmptyState(message: unanswerable)
            } else {
                HelmEmptyState(message: nothing)
            }
        }
    }

    /// The one `List` every package tab draws — its own rows or the sentence
    /// its own reading earns, and the "Available to install" section under
    /// them when there is one. The only call site `listOrEmpty` has, for the
    /// reason stated there: two would be two views to SwiftUI.
    ///
    /// **`screen` decides the first section's row, not `shown.isEmpty`
    /// alone.** A bare emptiness check read every non-row state — still
    /// waiting on `brew`, a refused query, an honestly empty answer — as the
    /// same «Nothing in this list matches.», which is the module's own
    /// "refused list is not an empty one" rule broken a second time, this
    /// time by the section rather than by a missing reading.
    private func packageList<T: Identifiable, Row: View>(
        _ shown: [T], screen: ListScreen, notes: (nothing: String, unanswerable: String, waiting: String),
        columns: ListColumns, singleColumn: Bool,
        section: AvailableSection?, hits: [SearchHit],
        @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        // A `List` with no selection has no focusable rows at all — arrow
        // keys did nothing. Selecting is also how the inspector is reached,
        // so this is the row's only door into the app now. No
        // `.onTapGesture`, no `.listRowBackground`: macOS draws the system
        // selection itself.
        List(selection: Binding(get: { hb.selected }, set: { hb.select($0) })) {
            Section(header: columnHeader(columns, singleColumn: singleColumn)) {
                if let note = Self.ownListNote(screen, notes: notes) {
                    noteRow(note.text, busy: note.busy)
                } else {
                    ForEach(shown) { item in row(item) }
                }
            }
            if let section {
                Section(header: sectionHeader(HbStr.availableToInstall)) {
                    availableRows(section, hits: hits, singleColumn: singleColumn,
                                 marksUpdates: columns.marksUpdates)
                }
            }
        }
        // **Striped, and no inset of its own.** These two lists are rows of
        // one shape and a great many of them, which is what a stripe is for: it
        // keeps the eye on a row while it crosses from a name to a version at
        // the far edge, and it puts the page with the other striped lists —
        // Uninstaller, Orphans and Leftovers stop at
        // `helmStripedList(rowPitch:)`; Disk, Autopilot and Duplicates stay
        // plain. The Health tab is not one of them any more: its rows are
        // paragraphs, one to three of them, with nothing to cross
        // (`HomebrewHealthPage`). The list carried `.padding(.horizontal,
        // HelmSpace.s5)` once, which put this page's rows 12 pt further in than
        // the rows of every other list in the app.
        .helmStripedList(rowPitch: HelmSpace.s8)
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
private extension View {
    func helmInspectorColumn() -> some View {
        frame(maxWidth: HelmLayout.readingColumn, alignment: .topLeading)
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// **One row of either package list on this page: what does not divide it from
/// the next one.**
///
/// The height is the list's own, not the row's: both lists pass
/// `HelmSpace.s8` as `helmStripedList(rowPitch:)`, which is the minimum height
/// of every row in them and the step the stripe repeats at under the last one,
/// so the two cannot be two numbers. It was `frame(minHeight: HelmSpace.s7)`
/// on the row, which a `List`'s own row insets took to 36 pt for a single line
/// of content (measured on both lists, 2026-09-29); the step is 40 now, the
/// ladder's nearest to that. Before that it was 34, off the ladder, which the
/// insets took to 42 — a step that long over one line of text reads as a
/// settings form rather than as a list of things.
///
/// **The separator is hidden.** macOS draws one per row across the whole
/// column, which at this step is a rule every few lines in a 310 pt column of
/// short names; the approved drawing has a hairline at a twentieth of that
/// weight, which macOS's is not and cannot be made into. What separates one row
/// from the next now is the alternating fill `helmStripedList(rowPitch:)` turns on for
/// both of them, and the `Section` headers over them, which carry the structure
/// the rules were standing in for. Hiding
/// the separator also puts this page with the app's other striped list
/// screens rather than against them: `OrphansView`, Uninstaller and Leftovers
/// all hide theirs on the row, and Homebrew was the one list still drawing
/// rules.
private extension View {
    func helmListRow() -> some View {
        listRowSeparator(.hidden)
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

/// What a package list's heading names, and whether the rows under it keep
/// the update mark's slot — the three facts `columnHeader` needs and nothing
/// else, so the three call sites spell them in one place each.
struct ListColumns {
    let leading: String
    let trailing: String?
    let marksUpdates: Bool
}

/// **The console's lines and the rule that follows them.** A struct of its own,
/// not a property of the page, so that its `followsConsole` lives exactly as
/// long as the scroll view does: the page keeps the console off the screen
/// while there is nothing to say, and a person who scrolled up in one run's
/// output must not find the next run's not followed.
private struct ConsoleScroll: View {
    let rows: [HomebrewViewModel.ConsoleRow]
    /// `HomebrewViewModel.consoleSequence`: how many lines have ever arrived,
    /// so the newest line's identity is one less than this.
    let sequence: Int
    @State private var followsConsole = true
    /// Starts at the end, which is where a page mounted over lines opens —
    /// mounting is what coming back to the page, or a window returning from
    /// hidden, is. A short console still sits at the top of its box: an edge
    /// position moves nothing when there is nothing to scroll.
    @State private var position = ScrollPosition(edge: .bottom)
    /// What the hold below reads and never draws, so it is a reference and not
    /// a `@State` value: writing it must not redraw `HomebrewViewModel.consoleLimit` rows.
    @State private var book = Book()

    /// **The facts the hold needs between one arrival and the next.**
    /// `heights` is each row's measured height by its number; `firstID` the
    /// oldest row drawn when the last arrival was answered; `offset` where the
    /// scroll view stood.
    private final class Book {
        var heights: [Int: CGFloat] = [:]
        var firstID: Int?
        var offset: CGFloat = 0
    }

    /// The offset and the furthest the offset can go.
    struct Reach: Equatable {
        let offset: CGFloat
        let end: CGFloat
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                // Each row is its line's number and not its index: at the limit
                // an arrival drops the first line and every index moves up by
                // one, so an index is a different line's identity every time.
                ForEach(rows) { row in
                    // A text style follows the system text size where a frozen
                    // 11 does not (the same reason the fix command's field
                    // names its font by style). Held once because the box
                    // around this is measured in it.
                    Text(row.text).font(HomebrewSettingsPage.consoleFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            book.heights[row.id] = height
                        }
                }
            }
            // The offered width, whether or not a line has arrived: a stack
            // takes the width of its widest child, so with no rows (a run that
            // has not printed yet, a failure with no line, a console just
            // cleared) it was 0 and the box drew as its insets alone, then
            // jumped to full width with the first line.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        .onAppear { book.firstID = rows.first?.id }
        // **Follows the sequence, which moves with every arrival, never the
        // count.** At `HomebrewViewModel.consoleLimit` an arrival drops one
        // line and adds one, so the count stays where it is for ever and a
        // follow keyed to it went quiet at line number `consoleLimit`.
        //
        // **Following is a jump to the end and not an animated scroll.** Lines
        // arrive faster than an animation runs, and one restarted per arrival
        // trailed the end by thousands of points until the stream thinned; a
        // jump per arrival lands on the newest line each time.
        //
        // **A person who has scrolled up keeps the line they are reading.**
        // At the bound each arrival drops the oldest rows from the top, so an
        // offset that holds still lets the text slide down the box one row per
        // arrival. The rows dropped were measured while they were drawn, so
        // the offset is lowered by their heights and the spacing between them,
        // in the update that dropped them. When the line being read is among
        // the dropped, the offset would go below the top and stops at it: the
        // oldest lines that are left, not the end, which nobody asked for.
        .onChange(of: sequence) { _, _ in
            let first = rows.first?.id
            defer { book.firstID = first }
            if followsConsole {
                position.scrollTo(edge: .bottom)
            } else if let first, let was = book.firstID, first > was {
                var trimmed: CGFloat = 0
                for id in was..<first {
                    trimmed += (book.heights.removeValue(forKey: id) ?? 0) + HelmSpace.s1
                }
                position.scrollTo(y: max(0, book.offset - trimmed))
            }
        }
        // **Whether the person has scrolled up, read off the offset's own
        // moves.** A line arriving grows the content and leaves the offset
        // alone, so growth never reads as leaving the end; the follow's own
        // scroll only ever moves the offset down, so a move up while the
        // follow is on is the person leaving. The hold above moves the offset
        // up as well, but it runs only when `followsConsole` is already off,
        // so reading its move as leaving changes nothing; and reaching the end
        // again is the person coming back.
        .onScrollGeometryChange(for: Reach.self) { geometry in
            Reach(offset: geometry.contentOffset.y,
                  end: max(0, geometry.contentSize.height - geometry.containerSize.height))
        } action: { old, new in
            book.offset = new.offset
            guard new.offset != old.offset else { return }
            if new.offset < old.offset - 0.5 { followsConsole = false }
            if new.offset >= new.end - 1 { followsConsole = true }
        }
    }
}
