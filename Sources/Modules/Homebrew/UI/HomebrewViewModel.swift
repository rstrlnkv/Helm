import Foundation
import HelmRuntime
import HelmUI
import Module_Homebrew_Engine

/// What the model asks of the engine: its readings, every press as one `perform`,
/// and one stream of what the engine says.
///
/// A reading answers nil where the engine could not, a timed-out query above all,
/// and each caller says what it does with that: the lists keep their last answer,
/// the inspector draws nothing, the doctor reads as refused. A missing brew is nil
/// to `readInfo`, `readDoctor`, `readConfig` and `readDependents` of a formula
/// (a cask's dependents are `[]` without asking), and an empty answer to the
/// list readings. The members are named
/// apart from the engine's own synchronous ones (`HomebrewEngine.listInstalled`
/// and the rest, internal): an `async` requirement is met by a sync method of the
/// same name, and a blocking call would then run wherever the caller's task is.
protocol HomebrewWork: AnyObject, Sendable {
    /// The last line, state and brew location, then every one after them in order; registered before it returns.
    func stream() -> AsyncStream<HomebrewNews>
    func readStatus() async -> BrewStatus
    func readInstalled() async -> [BrewPackage]?
    func readOutdated() async -> [OutdatedPackage]?
    /// `stillWanted` is asked between batches, from any thread; false stops the
    /// batches not yet launched.
    func readDescriptions(of names: [String], isCask: Bool,
                          stillWanted: @escaping @Sendable () -> Bool) async -> [String: String]
    func find(_ query: String) async -> [SearchHit]?
    func readDependents(of package: PackageRef) async -> [String]?
    func readInfo(about package: PackageRef) async -> PackageInfo?
    func measure(_ package: PackageRef, version: String) async -> Int?
    func readDoctor() async -> [DoctorIssue]?
    func readConfig() async -> BrewConfig?
    /// Returns at once; what happens arrives on `stream()`.
    func perform(_ act: HomebrewAct)
}

extension HomebrewEngine: HomebrewWork {}

/// What the dependents read of the pending uninstall came to. `.read([])` is
/// an answer, «nothing needs it»; `.unread` is a query that gave none.
enum DependentsReading: Equatable {
    case notAsked
    case read([String])
    case unread
}

/// `LatestRequest` behind a lock: the search counter is taken on the main
/// actor and asked from the engine's thread between `brew desc` batches, so
/// there is one counter and one answer, not a copy kept in step.
private final class SharedLatestRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request = LatestRequest()
    func take() -> Int { lock.lock(); defer { lock.unlock() }; return request.take() }
    func isLatest(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return request.isLatest(token) }
}

@MainActor public final class HomebrewViewModel: ObservableObject {
    private let work: any HomebrewWork
    private var events: StreamFollower?
    /// Set by `stop()`, once. A closed model reaches no work (`door`) and hears
    /// nothing more.
    private(set) var closed = false
    /// The one way to the engine. A closed model has none, so no call site can forget.
    private var door: (any HomebrewWork)? { closed ? nil : work }

    private let updateBeforeChecking: UpdateBeforeChecking
    /// What the Updates tab's row shows: whether the next `brew outdated` may refresh the catalogue first.
    @Published private(set) var refreshesBeforeChecking: Bool

    func setRefreshesBeforeChecking(_ on: Bool) {
        updateBeforeChecking.isOn = on
        refreshesBeforeChecking = on
    }

    @Published private(set) var status = BrewStatus(installed: false, brewPath: nil)
    /// Whether `status` is an answer of the engine's and not the seed of
    /// `HomebrewNews.brew`; the seed applies only while this is false.
    private var statusRead = false
    @Published private(set) var installed: [BrewPackage] = []
    /// What happened to the last `brew list`: not asked, waiting, answered or
    /// refused (`ListReading`). A refusal is a state of its own, or the page
    /// would spin over it for ever.
    @Published private(set) var installedReading: ListReading = .notAsked
    /// Whether there is an installed list to speak from, for the readers that
    /// only need that much — the status line's counts and the fix judge.
    /// Derived, so it cannot go stale beside the reading.
    var loadedInstalled: Bool { installedReading == .answered }
    @Published private(set) var outdated: [OutdatedPackage] = []
    /// `installedReading`'s twin for `brew outdated`.
    @Published private(set) var outdatedReading: ListReading = .notAsked
    @Published private(set) var searchHits: [SearchHit] = []
    /// `installedReading`'s twin for `brew search`. A search is two `brew
    /// search` runs and takes seconds; without this the pane would say
    /// «nothing found» while still asking, identical to a true zero and to a
    /// refusal.
    @Published private(set) var searchReading: ListReading = .notAsked
    /// The last of what `brew` said, not all of it. 1000 is `LogTail`'s bound
    /// and this is the same problem: a running record somebody reads the end of.
    static let consoleLimit = 1000
    @Published private(set) var consoleLines: [String] = []
    /// **How many lines the console has ever been given; the newest one's
    /// identity is one less.** Never reset, not by `clearConsole` and not by
    /// the trim: a full console keeps `consoleLines.count` at `consoleLimit`
    /// for ever, so anything that follows the tail by its count has stopped
    /// following at line number `consoleLimit`. The line at index `i` is number
    /// `consoleSequence - consoleLines.count + i`, which is what the page gives
    /// each row as its identity, and the newest is `consoleSequence - 1`.
    @Published private(set) var consoleSequence = 0

    /// A console line with the number it was given, for the page's rows.
    struct ConsoleRow: Identifiable {
        let id: Int
        let text: String
    }

    /// The lines as the page draws them: each under its own number, so a row
    /// keeps its identity while the trim moves it up the array.
    var consoleRows: [ConsoleRow] {
        let first = consoleSequence - consoleLines.count
        return consoleLines.enumerated().map { ConsoleRow(id: first + $0.offset, text: $0.element) }
    }
    @Published private(set) var op: OpState = .idle
    /// The uninstall a person is being asked about, and what the Cellar said
    /// still needs it. They move together: the names are read for *this* press
    /// and are cleared with it, so a second dialog can never draw the first
    /// one's answer. Held here, not in the page's `@State`, because the reading
    /// arrives after the press.
    @Published private(set) var pendingUninstall: BrewPackage?
    @Published private(set) var dependentsOfPending: DependentsReading = .notAsked
    /// Package descriptions keyed by "f:name" / "c:name", fetched in batches
    /// after a list or search loads.
    @Published private(set) var descriptions: [String: String] = [:]

    /// What `brew info --json=v2` knows about **the package selected now**, or
    /// nil because nothing is selected, the query has not answered yet, or it
    /// answered nil.
    ///
    /// Those three are one value on purpose: the page's second tier is drawn
    /// from an answer or not drawn at all. The engine folds a refusal, a
    /// missing brew and a document this build cannot read into the same nil
    /// (`HomebrewEngine.info`), and a `PackageInfo` of empty fields would state
    /// facts about a Cellar nobody read. The first tier — name, version,
    /// description, action — comes from the lists and never waits on this.
    @Published private(set) var info: PackageInfo?

    /// How much disk **the package selected now** occupies — or that a walk for
    /// it is out right now, or that there is nothing to say.
    ///
    /// **Three states rather than an optional.** `brew info` carries no size,
    /// so this is a walk of the package's Cellar directory that lands after the
    /// rest of the inspector. An `Int?` would fold «nothing is selected», «a
    /// walk is out» and «the walk answered nothing» into one nil, and the page
    /// could not show a measurement that is happening.
    ///
    /// `.measuring` is written immediately before the ask goes out and only for
    /// a package `brew info` said is installed, so it can never stand over a
    /// package nothing is walking. Every move of the subject puts it back to
    /// `.notMeasured` (`refillInfo`), including while an older walk is still in
    /// flight — that answer is then dropped by its token rather than drawn.
    ///
    /// **Never `.measured(0)`.** The engine folds a missing keg, a directory
    /// that would not open and a cask into nil (`HomebrewEngine.size`), which
    /// lands here as `.notMeasured`, because a zero in a row is not a gap on
    /// the page — it is a measurement, and it says the package occupies nothing.
    @Published private(set) var size: SizeReading = .notMeasured

    /// Which ask an answer belongs to, so an older one is dropped rather than
    /// drawn over a newer package. Clicking down a list leaves one `brew info`
    /// run out per row, and they answer in any order.
    private var infoAsks = LatestRequest()

    /// The ask in flight. Held so a superseded one can be dropped rather than
    /// left to resume into a screen that has moved on.
    private(set) var infoAsk: Task<Void, Never>?

    /// Which list the page is showing, and therefore which selection below
    /// applies.
    enum Segment: String, Hashable, CaseIterable, Sendable {
        /// Nothing stores a `Segment`, so a case may be removed outright.
        case installed, updates, health

        /// The word on the picker, beside the case it names. A `switch` with no
        /// `default:` makes a case without a label a build error.
        var label: String {
            switch self {
            case .installed: return HbStr.segInstalled
            case .updates: return HbStr.segUpdates
            case .health: return HbStr.segHealth
            }
        }

        /// The glyph the header row's tab draws when the tabs are labelled by glyphs (`HelmHeaderTab.symbol`).
        /// Updates keeps the module's own "an update exists" symbol.
        var symbol: String {
            switch self {
            case .installed: return "shippingbox"
            case .updates: return "arrow.up.circle"
            case .health: return "stethoscope"
            }
        }
    }
    /// Written by the segmented picker's own binding, which never goes through
    /// `select(_:)` — so this half of the subject carries its own retirement.
    ///
    /// **Re-evaluates the automatic search on the way in, not only the
    /// selection.** A word already typed can go unmatched on one tab and
    /// matched on another — `shownOutdated` is empty where `shownInstalled` is
    /// not — so switching tabs is a second place `scheduleAutomaticSearch`
    /// has to run, on top of the pause that starts it after typing.
    ///
    /// **Through the pause, never a direct `ask(_:)`.** The tab just entered
    /// may not have loaded yet (`loadIfNeeded` never asks `brew outdated`), and
    /// an unloaded list's emptiness is not "the word matches nothing". The
    /// pause gives the tab's own refresh the chance to land before
    /// `searchAfterPause` re-reads the list; `refreshInstalled` and
    /// `refreshOutdated` restart it too.
    @Published var segment: Segment = .installed {
        didSet {
            guard segment != oldValue else { return }
            reconcileVisible()
            if let q = ListFilter.needle(query) { scheduleAutomaticSearch(for: q) } else { pause?.cancel() }
            subjectMoved()
        }
    }

    /// What is selected in each segment, as a `BrewKey` id.
    ///
    /// Per package segment, because the two lists hold different things: what
    /// is selected in Установленные is not what is selected in Обновления, and
    /// coming back to a segment should find what was left there. Состояние
    /// selects nothing: its findings open in `HomebrewHealthPage`.
    @Published private(set) var selection: [Segment: String] = [:] {
        didSet { if selection[segment] != oldValue[segment] { subjectMoved() } }
    }

    /// The current segment's selection, or nil when nothing is selected.
    var selected: String? { selection[segment] }

    /// `nil` as well as an id: `List(selection:)` writes `nil` when the
    /// person clicks the empty space below the rows, and a setter that
    /// cannot take it turns a deselect into a selection that never goes away.
    func select(_ id: String?) { selection[segment] = id }

    // MARK: - The search field, on every tab

    /// **The header row's search field, on all three tabs.** Held here and not
    /// in the page's `@State`, so the query survives the page being unmounted
    /// when the window hides.
    @Published var query = "" {
        didSet { if query != oldValue { queryMoved() } }
    }

    /// The pause between the last keystroke and an automatic search for a
    /// word the local filter found nothing for (the owner's choice).
    static let searchPause: Duration = .milliseconds(700)
    /// Not `let`: a test shortens this.
    var searchPause = HomebrewViewModel.searchPause

    /// The shortest word that starts an automatic search on its own. One
    /// letter matches thousands of packages, a `brew desc` batch over all of
    /// them for one keystroke; two narrow it to a batch a person can wait
    /// through. Return carries no floor.
    static let shortestAutomaticQuery = 2

    /// The word `searchHits`/`searchReading` belong to, or nil before
    /// anything has been asked. Read by `AvailableSection.of` to tell a
    /// current answer from a stale one, and by `ownListShowsNothing(for:)` so
    /// a word already asked is not asked again on every keystroke or tab
    /// change.
    @Published private(set) var searchedQuery: String?

    /// The task counting down to an automatic search — cancelled by the next
    /// keystroke, by Return, and by the query going empty.
    private var pause: Task<Void, Never>?

    /// At most one `brew search` chain out at a time: the rule (ARCHITECTURE.md § Running other programs) of "never an
    /// unbounded launch behind a control pressable repeatedly", and
    /// typing is such a control. `queuedSearch` holds only the latest word
    /// typed while a chain is out; an older one in between is never asked.
    private var searchOut = false
    private var queuedSearch: String?

    /// Two things: reconcile the selection against what the new query still
    /// shows, then either retire everything (an emptied field) or hand the
    /// word to `scheduleAutomaticSearch`, which drops whatever pause was
    /// running and starts a fresh one only when the local filter on the
    /// current tab has nothing.
    ///
    /// **Never clears a held answer on its own.** A mismatch between `query`
    /// and `searchedQuery` already hides the section (`AvailableSection.of`),
    /// so going back to a word already searched shows it again without a
    /// second `brew search` — only an emptied field retires the answer
    /// outright, below.
    private func queryMoved() {
        reconcileVisible()
        guard let q = ListFilter.needle(query) else {
            pause?.cancel()
            _ = searches.take()
            searchReading = .notAsked
            searchedQuery = nil
            // `ask(_:)` re-reads the field before running a dequeued word;
            // this keeps the queue from naming a word the field no longer holds.
            queuedSearch = nil
            return
        }
        scheduleAutomaticSearch(for: q)
    }

    /// `scheduleAutomaticSearch` for the word the field holds now, when it holds
    /// one — what `refreshInstalled`, `refreshOutdated` (answer or refusal) and
    /// the retiring of a refused search do, since each can make the word newly
    /// qualify.
    private func rearmSearch() {
        if let q = ListFilter.needle(query) { scheduleAutomaticSearch(for: q) }
    }

    /// Starts the pause toward an automatic search for `q`, when the trigger
    /// rule allows it — shared by `queryMoved()` and by `segment`'s own
    /// `didSet`, and by every list refresh that can make a word newly
    /// qualify once its own tab has actually loaded.
    private func scheduleAutomaticSearch(for q: String) {
        pause?.cancel()
        guard ownListShowsNothing(for: q) else { return }
        let delay = searchPause
        pause = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.searchAfterPause(q)
        }
    }

    /// Fires when the pause elapses. `q` is the payload — the word that was
    /// in the field when the pause started — and the reading is re-read here
    /// rather than trusted from before the sleep (a reading taken
    /// before an `await` is not the reading to act on, ARCHITECTURE.md § The gates): the list may have
    /// loaded, or a description may have arrived, during those 700 ms.
    private func searchAfterPause(_ q: String) {
        guard ListFilter.needle(query) == q, ownListShowsNothing(for: q) else { return }
        ask(q)
    }

    /// **The trigger rule, stated once.** At least two characters, the
    /// current tab's own filtered list empty, and not a word already asked —
    /// asked both after the pause and again on a tab change, so a word that
    /// matches nothing on Состояние but something on Установленные does not
    /// spend a second `brew search` just because the tab moved.
    ///
    /// **An unread or still-loading tab is never "empty".** `shownInstalled`
    /// and `shownOutdated` read `[]` before their list has answered, the same
    /// `[]` a genuinely empty answer leaves, and a cold `brew outdated` outlasts
    /// the pause. `refreshInstalled` and `refreshOutdated` call
    /// `scheduleAutomaticSearch` again on completion, so the tab's first real
    /// answer re-asks this question.
    private func ownListShowsNothing(for q: String) -> Bool {
        guard q.count >= Self.shortestAutomaticQuery, q != searchedQuery else { return false }
        switch segment {
        case .installed:
            guard installedReading != .notAsked, installedReading != .waiting else { return false }
            return shownInstalled.isEmpty
        case .updates:
            guard outdatedReading != .notAsked, outdatedReading != .waiting else { return false }
            return shownOutdated.isEmpty
        case .health:
            // The "Available to install" section is not drawn on Health, so a
            // `brew search` from here would never be shown. The pause starts
            // when the person moves to a tab that draws it.
            return false
        }
    }

    /// Return's own door — no minimum length, and asked even when the local
    /// filter already has matches: somebody typing `python` for `python@3.13`
    /// has to be able to ask past what is already on screen. A word already
    /// answered or still waiting is not asked twice; a refused one is asked
    /// again, since a refusal earns nothing kept.
    func searchNow() {
        pause?.cancel()
        // Return on Состояние filters and asks nothing, for the reason
        // `ownListShowsNothing` gives for the pause.
        guard segment != .health else { return }
        guard let q = ListFilter.needle(query) else { return }
        if q == searchedQuery, searchReading == .waiting || searchReading == .answered { return }
        ask(q)
    }

    /// The one door to `search(_:)` that both the pause and Return go
    /// through, and the single-flight gate over it. A press while a chain is
    /// already out queues the newest word only — an older one typed in
    /// between is dropped along with its own `brew search` — and marks the
    /// section `.waiting` immediately, so "Searching…" names the word that
    /// will actually be asked next rather than the one still in flight.
    private func ask(_ q: String) {
        guard !searchOut else {
            queuedSearch = q
            _ = searches.take()
            searchedQuery = q
            searchHits = []
            searchReading = .waiting
            return
        }
        searchOut = true
        Task { [weak self] in
            guard let self else { return }
            await self.search(q)
            self.searchOut = false
            // The queued word is a payload; the field is a reading, asked again
            // after the `await`, so a word erased or typed over spends no
            // `brew search`.
            if let queued = self.queuedSearch {
                self.queuedSearch = nil
                if ListFilter.needle(self.query) == queued {
                    self.ask(queued)
                } else if self.searchedQuery == queued {
                    // Dropping the word undoes what queuing claimed for it
                    // (`searchedQuery`, `.waiting`), or "Searching…" stands
                    // over a question nobody will put and no door leads back
                    // in. Only if no later chain has claimed the field since.
                    self.searchedQuery = nil
                    self.searchReading = .notAsked
                    self.rearmSearch()
                }
            }
        }
    }

    /// The page has stopped describing the package an uninstall was asked
    /// about, so the ask is retired — including one still out at the engine.
    ///
    /// **The subject is the pair `(segment, selection[segment])`**, because
    /// that pair is what `packageDetail` draws and the Uninstall button is
    /// raised from it. Back, a click on another row and the segmented picker
    /// all move off a package without a press that `LatestRequest` would see,
    /// so the fields that write the pair call this, not each gesture
    /// (`MovingOffThePackageRetiresAnUninstallAskTests`).
    ///
    /// Unconditional once the value has moved: a query still in flight has set
    /// nothing yet, so a guard on `pendingUninstall != nil` would miss it.
    /// `cancelUninstall` retires the token as well as the dialog. The `brew
    /// info` fill hangs here for the same reason.
    private func subjectMoved() {
        cancelUninstall()
        refillInfo()
    }

    /// Drops whatever the second tier was showing and asks about the package
    /// the page is describing now — or about nothing, when nothing is selected.
    ///
    /// **Cleared before the ask, unconditionally.** The facts belong to the
    /// package they were read for; kept across a move, they stand under the
    /// next package's heading while its query runs.
    private func refillInfo() {
        infoAsk?.cancel()
        info = nil
        // The size too, and to `.notMeasured`, not `.measuring`: nothing has
        // been asked for the new package yet.
        size = .notMeasured
        let mine = infoAsks.take()
        guard let ref = selectedPackage else { infoAsk = nil; return }
        infoAsk = Task { [weak self] in await self?.loadInfo(ref, token: mine) }
    }

    /// The selected package as the engine names one, read from the same list
    /// `InspectorState.of` reads for the same segment — so a selection the
    /// inspector draws nothing for costs no `brew` run either, and the two
    /// cannot disagree about which package is on screen.
    private var selectedPackage: PackageRef? {
        guard let id = selected else { return nil }
        // The package tabs fall back to the "Available to install" section
        // under them; Health has neither section nor selection.
        let own: PackageRef?
        switch segment {
        case .installed:
            own = installed.first { $0.id == id }.map { PackageRef(name: $0.name, isCask: $0.isCask) }
        case .updates:
            own = outdated.first { $0.id == id }.map { PackageRef(name: $0.name, isCask: $0.isCask) }
        case .health:
            return nil
        }
        return own ?? shownHits.first { $0.id == id }.map { PackageRef(name: $0.name, isCask: $0.isCask) }
    }

    /// Asks, then assigns only if this is still the ask the page is waiting on.
    ///
    /// The token, not a comparison of names: a person who moved away and came
    /// back has a second ask out, and this one's answer is not the one to draw.
    private func loadInfo(_ ref: PackageRef, token: Int) async {
        let answer = await door?.readInfo(about: ref)
        guard infoAsks.isLatest(token) else { return }
        // Assigned including nil: a refusal draws nothing.
        info = answer

        // **Then the walk (`HomebrewEngine.size`), on the same token,** after
        // the tier it joins is drawn, and only for an installed package: a
        // search hit has no keg. The version is the one `brew info` said,
        // the one the engine files the figure against.
        guard let version = answer?.installedVersion, !version.isEmpty else { return }
        // `.measuring` is set only right before a walk goes out.
        size = .measuring
        let measured = await door?.measure(ref, version: version)
        // Asked again: whatever moved the subject already wrote `.notMeasured`.
        guard infoAsks.isLatest(token) else { return }
        // A refusal is `.notMeasured`, not a lingering «counting».
        size = measured.map(SizeReading.measured) ?? .notMeasured
    }

    /// Drops `segment`'s selection when its package is no longer in `ids`.
    ///
    /// One segment per call, at the assignment that just replaced *that*
    /// list. A selection that survives its package leaves the inspector
    /// describing something that is gone, with buttons that would act on it.
    private func reconcile(_ segment: Segment, against ids: Set<String>) {
        guard let id = selection[segment], !ids.contains(id) else { return }
        selection[segment] = nil
    }

    /// Everything the current tab actually shows, filter and section
    /// together — the ids `List(selection:)` can land on right now.
    var visibleIDs: Set<String> {
        let own: Set<String>
        switch segment {
        case .installed: own = Set(shownInstalled.map(\.id))
        case .updates: own = Set(shownOutdated.map(\.id))
        // Nothing on Состояние can be selected: no list, no section.
        case .health: return []
        }
        return own.union(shownHits.map(\.id))
    }

    /// **A row a query has just hidden stops being selected,** so
    /// `askToUninstall` cannot raise its dialog over a row the list no longer
    /// shows. `reconcile(_:against:)` runs when a list is replaced; this, when
    /// the filter moves. `selection`'s `didSet` retires an ask still out.
    /// Erasing the query does not bring a dropped selection back.
    private func reconcileVisible() {
        guard let id = selection[segment], !visibleIDs.contains(id) else { return }
        selection[segment] = nil
    }

    // MARK: - What each tab actually shows

    /// `installed`, filtered by `query` against the name and — once it has
    /// loaded — the description.
    var shownInstalled: [BrewPackage] {
        PackageStanding.matching(ListFilter.needle(query), installed, descriptions: descriptions)
    }
    /// `outdated`'s twin.
    var shownOutdated: [OutdatedPackage] {
        PackageStanding.matching(ListFilter.needle(query), outdated, descriptions: descriptions)
    }
    /// What `AvailableSection.of` says the "Available to install" section
    /// should draw right now — nil when nothing belongs there, which is most
    /// of the time: no query, nothing asked yet, or an answer that belongs to
    /// a word the person has since typed over.
    ///
    /// **Fed the already-excluded hits, not the raw answer,** so a word whose
    /// every hit is installed reads `.nothingFound`, not a `.found` heading
    /// with nothing under it.
    var section: AvailableSection? {
        AvailableSection.of(query: query, searchedQuery: searchedQuery, reading: searchReading,
                            available: PackageStanding.notInstalled(searchHits, installed: installed))
    }

    /// The hits the section actually draws — `searchHits` with what is
    /// already on this Mac filtered out, **by id and never by name**: `docker`
    /// is both a formula and a cask, and an installed formula must not hide an
    /// offered cask of the same name. Computed, so an installed hit leaves
    /// here when `refreshAfterOp` re-reads the Cellar and keeps its id: on
    /// Installed it appears in the list above, still selected.
    var shownHits: [SearchHit] {
        section == .found ? PackageStanding.notInstalled(searchHits, installed: installed) : []
    }

    /// Architecture/Homebrew.md § The model.
    ///
    /// - Parameter updateBeforeChecking: the setting the Updates tab's row shows and
    ///   writes; the engine of the same module reads it at each `outdated`. Read here,
    ///   so a model built at activation shows what is stored now.
    init(work: any HomebrewWork, updateBeforeChecking: UpdateBeforeChecking = .inMemory) {
        self.work = work
        self.updateBeforeChecking = updateBeforeChecking
        refreshesBeforeChecking = updateBeforeChecking.isOn
        events = StreamFollower(work.stream(), owner: self) { $0.handle($1) }
    }

    /// The host calls this before the engine's `deactivate()` (Architecture/Homebrew.md § The model).
    ///
    /// The three tokens are retired as well, because a nil from a closed door
    /// must not read as an answer: `askToUninstall` with nil raises the dialog
    /// with an empty list.
    func stop() {
        closed = true
        events?.cancel()
        pause?.cancel(); infoAsk?.cancel()
        _ = searches.take(); _ = infoAsks.take()
        queuedSearch = nil
        cancelUninstall(); cancelFix()
    }

    /// What the page asks for on appear — and it asks whether brew is there
    /// every time.
    ///
    /// **Whether Homebrew is installed is not a property of this process.**
    /// It is a file `FSBrewLocator` re-reads at every call, and somebody may
    /// install or uninstall brew in a terminal with this window open. Asking
    /// the locator is two `isExecutableFile` calls, so it is asked every time.
    ///
    /// The guard sits on the expensive half: `brew list --versions` twice and
    /// a `brew desc` batch. The packages belong to *a* brew: one reinstalled
    /// or moved between visits is a new Cellar, and the old rows would carry
    /// Uninstall buttons the engine refuses.
    func loadIfNeeded() async {
        await refreshStatus()
        guard status.installed, !loadedInstalled || listedBrew != status.brewPath else { return }
        await refreshInstalled()
    }

    /// The brew the installed list was last read from.
    private var listedBrew: String?

    var running: Bool { op.phase == .running }

    // MARK: - Events

    private func handle(_ item: HomebrewNews) {
        switch item {
        case .line(let line):
            say(line)
            // Bounded from the front by `say`, the way `LogTail` is: only Clear
            // and the Homebrew install empty it, stderr is kept, and every
            // line is also a view.
        case .brew(let path):
            // Only a seed, and only while nothing has been read
            // (Architecture/Homebrew.md § The model).
            if !statusRead { status = BrewStatus(installed: path != nil, brewPath: path) }
        case .busy:
            say(HbStr.anotherOperationRunning())
        case .state(let s):
            // Before `op` changes, because the line is about the step between
            // the two states.
            if let line = Self.consoleLine(from: op, to: s) { say(line) }
            op = s
            // `.failed` as well as `.done`: `brew upgrade` exits non-zero when
            // one package fails, with everything before it already upgraded.
            if s.phase == .done || s.phase == .failed { Task { await self.refreshAfterOp() } }
        }
    }

    /// The console line a step between two operation states earns, in words the
    /// engine does not have: it names the state (`OpState.waiting`) and the words
    /// are the page's, in the person's language.
    ///
    /// Entering the wait, leaving it into running, and leaving it by the
    /// person's Stop each earn a line; the last because the entering line
    /// promised Helm carries on by itself, and a stop does not clear the
    /// console. Any other step says nothing.
    static func consoleLine(from old: OpState, to new: OpState,
                            language: AppLanguage = AppLanguage.current) -> String? {
        if old.waiting == nil, new.waiting == .commandLineTools, new.phase == .running {
            return HbStr.toolsWaitingConsole(language: language)
        }
        if old.waiting != nil, new.waiting == nil, new.phase == .running {
            return HbStr.toolsArrivedConsole(language: language)
        }
        if old.waiting != nil, new.phase == .failed, new.reason == .stopped {
            return HbStr.toolsWaitStoppedConsole(language: language)
        }
        return nil
    }

    /// The status too: installing Homebrew ends here, and `status.installed`
    /// is the only thing `HomebrewSettingsPage.body` branches on.
    private func refreshAfterOp() async {
        await refreshStatus()
        await refreshInstalled()
        await refreshOutdated()
        // What `brew doctor` said, **only if it has ever been asked**: an
        // operation (a fix above all) changes what the findings are about, but
        // it is the slowest query, and `.notAsked` is nobody waiting.
        if doctor != .notAsked { await refreshDoctor() }
        // `brew config` on the same terms: `installBrew` and an upgrade of
        // Homebrew rewrite it.
        if config != nil { await refreshConfig() }
        // `brew info` and the Cellar walk, which an operation rewrites; last,
        // against the selection the reconciles above settled on. The engine
        // drops its remembered sizes at the same moment (`HomebrewEngine.size`).
        refillInfo()
    }

    // MARK: - Queries

    func refreshStatus() async {
        if let read = await door?.readStatus() {
            status = read
            statusRead = true
        }
        // Carried once: the engine's marker is consumed by the read, so only
        // the first status after an interrupted quit says it — into the
        // console, the surface that already narrates operations.
        if let label = status.interruptedOp {
            say(HbStr.interruptedAtQuit(label))
        }
    }
    /// No `?? []` on any list reply: nil is "the module could not answer",
    /// and the last answer stays (Architecture/Homebrew.md § Homebrew).
    func refreshInstalled() async {
        installedReading = .waiting
        guard let answer = await door?.readInstalled()
        else {
            // Rows on screen keep their reading; with nothing behind them the
            // pane says it could not answer instead of waiting for ever.
            installedReading = installed.isEmpty ? .unanswerable : .answered
            // A refusal is a reading too: a word typed during `.waiting` armed
            // no pause, and nothing else re-arms it.
            rearmSearch()
            return
        }
        installed = answer
        // `shownHits` as well: a hit selected in the section is not in
        // `installed`, and the section did not move.
        reconcile(.installed, against: Set(answer.map(\.id)).union(shownHits.map(\.id)))
        installedReading = .answered
        listedBrew = status.brewPath
        reconcileVisible()
        rearmSearch()
        await loadDescriptions(formulae: installed.filter { !$0.isCask }.map(\.name),
                               casks: installed.filter(\.isCask).map(\.name))
    }
    /// What `brew doctor` said, and **which of the three things it said**.
    ///
    /// A named reason per outcome: "no issues" and "could not be asked" must
    /// never be the same sentence. A machine nobody could examine is not a
    /// healthy one.
    @Published private(set) var doctor: DoctorReading = .notAsked

    /// What `brew config` last answered — the lines the configuration card
    /// is drawn from, **and the document «Copy for a bug report» puts on the
    /// pasteboard**. nil until it has been asked, which is every launch:
    /// `loadIfNeeded` does not ask, the segment's own refresh does.
    @Published private(set) var config: BrewConfig?

    /// Those lines as the three groups the configuration card draws.
    var configGroups: [ConfigGroup] { ConfigGroup.grouping(config?.lines ?? []) }

    /// What `brew config` says about this Homebrew and this Mac.
    ///
    /// **A refusal keeps the last answer**, the lists' rule. `refreshDoctor`
    /// does the opposite because its findings are a claim about health; a
    /// configuration makes none.
    func refreshConfig() async {
        guard let answer = await door?.readConfig() else { return }
        config = answer
    }

    /// **A refusal replaces the issues rather than keeping them.** Unlike the
    /// package lists, the findings *are* the claim about the machine's health,
    /// and kept under a failed reading they say those are still what is wrong.
    ///
    /// **One reading is out at a time.** A press while one is out asks for one more
    /// when it lands and returns: ten presses are at most two `brew doctor` children,
    /// and the second starts after the first has answered, so the reading after an
    /// operation is never answered by one that began before the operation ended.
    func refreshDoctor() async {
        if doctorInFlight { doctorAgain = true; return }
        doctorInFlight = true
        defer { doctorInFlight = false; doctorAgain = false }
        repeat {
            doctorAgain = false
            await readDoctorOnce()
        } while doctorAgain && !closed
    }

    private var doctorInFlight = false
    private var doctorAgain = false

    private func readDoctorOnce() async {
        // **The installed list first, because the verdict is about it**
        // (`DoctorFixCandidate.judging`). A refused list leaves every
        // `uninstall` fix copy-only: no button without a reading to justify it.
        if !loadedInstalled { await refreshInstalled() }
        guard let answer = await door?.readDoctor() else {
            doctor = .refused
            return
        }
        // The parser answers `fix: nil`; here a body is judged. This verdict
        // decides what is drawn; `HomebrewEngine.runDoctorFix` judges again at
        // the press, and that decides what runs.
        let installedNames = installed.map(\.name)
        doctor = .examined(answer.map { DoctorFixCandidate.judging($0, installed: installedNames) })
    }

    /// The fix a person is being asked about, or nil because nothing is being
    /// asked. Held here, as `pendingUninstall` is, so a test can see which
    /// press raised which question.
    @Published private(set) var pendingFix: DoctorFix?

    /// The press on Run, which is not the same thing as running it.
    ///
    /// `FixAsk.of` decides which question is raised: anything that takes a
    /// package off this Mac raises the Uninstall button's question.
    ///
    /// An `uninstall <name>` fix reads what depends on the package first, through
    /// `askAboutRemoving` — the same reading, and the same list under the same
    /// sentence, as the Uninstall button's dialog. A fix names one package, so
    /// there is one list.
    func askToRunFix(_ fix: DoctorFix) async {
        switch FixAsk.of(fix.argv) {
        case let .uninstalls(name):
            // A doctor heading names a formula; a cask's dependents are `[]` anyway.
            await askAboutRemoving(PackageRef(name: name, isCask: false)) { self.pendingFix = fix }
        case .unrecognised: pendingFix = fix
        }
    }

    /// Closes the question without running anything, on Cancel and when the
    /// page goes away (this object outlives the page). Also abandons a
    /// dependents read still out and clears the list; `confirmFix` relies on
    /// both.
    func cancelFix() {
        _ = uninstallAsks.take()
        pendingFix = nil
        dependentsOfPending = .notAsked
    }

    /// The press on the dialog Run raised. The only door to a destructive fix.
    func confirmFix() {
        guard let fix = pendingFix else { return }
        cancelFix()
        runDoctorFix(fix)
    }

    /// Sends one `brew doctor` fix to the engine, which judges it again before
    /// it runs anything.
    ///
    /// **Private: `askToRunFix` is the door,** so a fix that removes a package
    /// is asked first like every other irreversible deletion.
    ///
    /// The argv goes as drawn: a second judgement here would use the same
    /// stale reading. `HomebrewEngine.runDoctorFix` reads the installed list at
    /// the press and refuses what `DoctorFix.judge` will not admit.
    private func runDoctorFix(_ fix: DoctorFix) {
        door?.perform(.doctorFix(argv: fix.argv))
    }

    func refreshOutdated() async {
        outdatedReading = .waiting
        guard let answer = await door?.readOutdated()
        else {
            outdatedReading = outdated.isEmpty ? .unanswerable : .answered
            // `refreshInstalled`'s reason: a refusal is a reading.
            rearmSearch()
            return
        }
        outdated = answer
        // `shownHits` unioned in for `refreshInstalled`'s reason.
        reconcile(.updates, against: Set(answer.map(\.id)).union(shownHits.map(\.id)))
        outdatedReading = .answered
        reconcileVisible()
        rearmSearch()
    }
    /// `loadedInstalled`'s twin. `loadIfNeeded` never asks `brew outdated`,
    /// so this is false until somebody opens the segment.
    var loadedOutdated: Bool { outdatedReading == .answered }

    /// Which search the hits belong to, so an older answer cannot land on a
    /// newer one — and so a search nobody is waiting for any more stops
    /// spending `brew` runs on descriptions.
    ///
    /// **A counter rather than a latch**, for the reason `LatestRequest`
    /// gives: what has to be dropped is the older *answer*, not the newer
    /// search. The bound on searches out is `ask(_:)`'s.
    private let searches = SharedLatestRequest()

    func search(_ q: String) async {
        let mine = searches.take()
        // **The old hits go before the new query is sent:** they belong to
        // the word that was typed over.
        searchedQuery = q
        searchHits = []
        reconcileVisible()
        searchReading = .waiting
        guard let hits = await door?.find(q)
        else {
            // Only for the press still being waited on.
            if searches.isLatest(mine) { searchReading = .unanswerable }
            return
        }
        // The hits first: a stale answer must not replace what a newer search
        // has already drawn.
        guard searches.isLatest(mine) else { return }
        searchHits = hits
        searchReading = .answered
        reconcileVisible()
        await loadDescriptions(formulae: searchHits.filter { !$0.isCask }.map(\.name),
                               casks: searchHits.filter(\.isCask).map(\.name),
                               token: mine)
    }

    /// Only what is not held yet, one `brew desc` call per kind.
    ///
    /// Every key goes through `BrewKey`, the same as the row identities: a
    /// description under a key no row asks for is silently lost.
    /// `token` is the search these names came from, or nil for a list that
    /// belongs to no search — the installed packages, which nothing supersedes.
    ///
    /// **Checked between the two calls, not only before them.** They run in
    /// sequence and each is a `brew` run of its own, so a search abandoned
    /// while the first is out would otherwise still pay for the second.
    private func loadDescriptions(formulae: [String], casks: [String],
                                  token: Int? = nil) async {
        await load(formulae, isCask: false, token: token)
        guard token.map(searches.isLatest) ?? true else { return }
        await load(casks, isCask: true, token: token)
    }

    private func load(_ names: [String], isCask: Bool, token: Int? = nil) async {
        let wanted = names.filter { descriptions[BrewKey.of(name: $0, isCask: isCask)] == nil }
        guard !wanted.isEmpty,
              let found = await door?.readDescriptions(
                of: wanted, isCask: isCask,
                stillWanted: { [searches] in token.map(searches.isLatest) ?? true })
        else { return }
        // A description is keyed by the package it describes, so a late batch
        // is not *wrong* — but writing it republishes the whole dictionary and
        // redraws a list the person is no longer looking at.
        guard token.map(searches.isLatest) ?? true else { return }
        for (name, text) in found { descriptions[BrewKey.of(name: name, isCask: isCask)] = text }
    }

    // MARK: - Operations (fire-and-forget; progress via events)

    func install(_ hit: SearchHit) {
        door?.perform(.install(PackageRef(name: hit.name, isCask: hit.isCask)))
    }
    /// Which press the dialog belongs to, so an older query cannot raise one.
    ///
    /// Nothing is disabled while this query is out, so two presses put two
    /// queries in flight; without this the answer for an abandoned press
    /// could raise its own dialog, or swap the list under somebody reading it.
    private var uninstallAsks = LatestRequest()

    /// Asks the Cellar what still needs this package, then raises the dialog.
    ///
    /// Read one press before the act, the last moment it is true. A refusal
    /// reads `.unread` and the dialog says so, rather than reassure.
    func askToUninstall(_ pkg: BrewPackage) async {
        await askAboutRemoving(PackageRef(name: pkg.name, isCask: pkg.isCask)) { self.pendingUninstall = pkg }
    }

    /// The one place a confirmation for `brew uninstall` is built, for both
    /// doors: reads the dependents, and only then calls `raise`, which sets the
    /// dialog's own pending value. `dependentsOfPending` is shared by the two
    /// dialogs, so each draws the same "still needed by" content.
    private func askAboutRemoving(_ ref: PackageRef, raise: () -> Void) async {
        guard !closed else { return }
        let mine = uninstallAsks.take()
        let answer = await door?.readDependents(of: ref)
        // Both halves or neither, and only for the press still being waited on.
        guard uninstallAsks.isLatest(mine) else { return }
        dependentsOfPending = answer.map(DependentsReading.read) ?? .unread
        raise()
    }

    /// Closes the dialog and abandons whatever reading is still out — a token
    /// taken and dropped, so an earlier press's query cannot raise a dialog
    /// by itself.
    func cancelUninstall() {
        _ = uninstallAsks.take()
        pendingUninstall = nil
        dependentsOfPending = .notAsked
    }

    /// Sends the uninstall the dialog was raised for, and clears the reading
    /// with it.
    ///
    /// One of two doors to `brew uninstall`, the other `confirmFix`; both are
    /// reached only through a dialog `askAboutRemoving` raised.
    func confirmUninstall() {
        guard let pkg = pendingUninstall else { return }
        cancelUninstall()
        door?.perform(.uninstall(PackageRef(name: pkg.name, isCask: pkg.isCask)))
    }
    func upgrade(_ pkg: OutdatedPackage) {
        door?.perform(.upgrade(name: pkg.name))
    }
    func upgradeAll() { door?.perform(.upgradeAll) }
    func installBrew() {
        guard !closed else { return }
        consoleLines.removeAll()
        door?.perform(.installBrew)
    }
    /// The page's Stop button. Ends the running operation; the engine reports
    /// the exit as `.stopped`. (`stop()` is the seam's: it closes the model.)
    func stopOperation() { door?.perform(.stop) }

    func clearConsole() { consoleLines.removeAll() }

    /// The one door a console line comes in by: it takes the next number and
    /// keeps the newest `consoleLimit`. Numbered before the trim, so the
    /// newest line's number moves on every arrival however full the console is.
    private func say(_ line: String) {
        consoleLines.append(line)
        consoleSequence += 1
        if consoleLines.count > Self.consoleLimit {
            consoleLines.removeFirst(consoleLines.count - Self.consoleLimit)
        }
    }
}
