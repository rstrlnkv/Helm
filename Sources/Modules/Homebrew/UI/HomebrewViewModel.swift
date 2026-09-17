import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewViewModel: ObservableObject {
    private let client: TransportClient
    private var eventsTask: Task<Void, Never>?
    private let vm: ModuleViewModel

    @Published public private(set) var status = BrewStatus(installed: false, brewPath: nil)
    @Published public private(set) var installed: [BrewPackage] = []
    /// What happened to the last `brew list` — which is three things and not
    /// two. This was a `Bool`, and the state it could not hold is a refusal:
    /// the flag stayed down for ever and the page spun over it (`ListReading`).
    @Published private(set) var installedReading: ListReading = .notAsked
    /// Whether there is an installed list to speak from, for the readers that
    /// only need that much — the status line's counts and the fix judge.
    /// Derived rather than stored beside the reading, for the reason `issues`
    /// is derived from `doctor`: two fields are two accounts of one answer, and
    /// the one that goes stale is the one a page reads.
    public var loadedInstalled: Bool { installedReading == .answered }
    @Published public private(set) var outdated: [OutdatedPackage] = []
    /// `installedReading`'s twin for `brew outdated`.
    @Published private(set) var outdatedReading: ListReading = .notAsked
    @Published public private(set) var searchHits: [SearchHit] = []
    /// `installedReading`'s twin for `brew search` — **and the one the page had
    /// nothing at all for.** A search is two `brew search` runs, measured at
    /// about nine seconds, and for those nine seconds the results pane said
    /// «Ничего не найдено.»: the answer to the question, drawn while it was
    /// still being asked and pixel-identical to a true zero and to a refusal.
    /// `HbStr.searching` was translated into all eight languages and drawn
    /// nowhere, because the branch that would have drawn it was unreachable by
    /// construction.
    @Published private(set) var searchReading: ListReading = .notAsked
    /// The last of what `brew` said, not all of it. 1000 is `LogTail`'s bound
    /// and this is the same problem: a running record somebody reads the end of.
    public static let consoleLimit = 1000
    @Published public private(set) var consoleLines: [String] = []
    @Published public private(set) var op: OpState = .idle
    /// The uninstall a person is being asked about, and what the Cellar said
    /// still needs it. They move together: the names are read for *this* press
    /// and are cleared with it, so a second dialog can never draw the first
    /// one's answer. It lives here rather than in the page's `@State` because
    /// the reading is asked for over the transport and arrives after the press.
    @Published public private(set) var pendingUninstall: BrewPackage?
    @Published public private(set) var dependentsOfPending: [String] = []
    /// Package descriptions keyed by "f:name" / "c:name", fetched in batches
    /// after a list or search loads.
    @Published public private(set) var descriptions: [String: String] = [:]

    /// What `brew info --json=v2` knows about **the package selected now**, or
    /// nil because nothing is selected, the query has not answered yet, or it
    /// answered nil.
    ///
    /// Those three are one value on purpose: the page's second tier is drawn
    /// from an answer or not drawn at all. The engine folds a refusal, a
    /// missing brew and a document this build cannot read into the same nil
    /// (`HomebrewEngine.info`) — and none of the three has measured anything, so
    /// a `PackageInfo` of empty fields standing in for "not answered" would be
    /// the page stating facts about a Cellar nobody read. The first tier —
    /// name, version, description, action — is a function of the lists this
    /// object already holds and never waits on this.
    ///
    /// Internal rather than `public`, for the reason `segment` gives: nothing
    /// outside `Module_Homebrew_UI` reads it, and `public` in this tree means
    /// "another target uses this".
    @Published private(set) var info: PackageInfo?

    /// How much disk **the package selected now** occupies — or that a walk for
    /// it is out right now, or that there is nothing to say.
    ///
    /// **Three states rather than an optional, and the middle one is the whole
    /// reason.** `brew info` carries no size in either direction, so this is a
    /// walk of the package's own Cellar directory and it lands after the rest of
    /// the inspector — the one wait in the tier long enough that arriving with
    /// no warning reads as a tile appearing out of nowhere. An `Int?` could not
    /// say that: «nothing is selected», «a walk is out» and «the walk answered
    /// nothing» were one nil, so the page could not tell a measurement that is
    /// happening from one that is not. `SizeReading` carries the difference;
    /// this field is where it is known.
    ///
    /// `.measuring` is written immediately before the ask goes out and only for
    /// a package `brew info` said is installed, so it can never stand over a
    /// package nothing is walking. Every move of the subject puts it back to
    /// `.notMeasured` (`refillInfo`), including while an older walk is still in
    /// flight — that answer is then dropped by its token rather than drawn.
    ///
    /// **Never `.measured(0)`.** The engine folds a missing keg, a directory
    /// that would not open and a cask into nil (`HomebrewEngine.size`), which
    /// lands here as `.notMeasured`, because a zero in a tile is not a gap on
    /// the page — it is a measurement, and it says the package occupies nothing.
    @Published private(set) var size: SizeReading = .notMeasured

    /// Which ask an answer belongs to, so an older one is dropped rather than
    /// drawn over a newer package.
    ///
    /// The third `LatestRequest` in this file, for the third reading that
    /// arrives after the screen may have moved. Clicking down a list of fifty
    /// rows leaves fifty `brew info` runs out behind a 90 s deadline, and
    /// whichever answered last used to be the one on screen — under whatever
    /// heading the person had reached by then.
    private var infoAsks = LatestRequest()

    /// The ask in flight. Held so a superseded one can be dropped rather than
    /// left to resume into a screen that has moved on, and read by
    /// `TheInspectorDoesNotWaitForInfoTests` to await the answer it is about to
    /// drop — a guard about arrival order cannot be written against work it
    /// has no handle on.
    private(set) var infoAsk: Task<Void, Never>?

    /// Which list the page is showing, and therefore which selection below
    /// applies. Internal, not `public` — nothing outside this target reads
    /// it (`public` here means "another target uses this").
    enum Segment: String, Hashable, CaseIterable, Sendable {
        case installed, updates, search, health

        /// The word on the picker, beside the case it names.
        ///
        /// **The list of segments and the list of labels are one list.** The
        /// picker used to spell three `Text(…).tag(…)` rows by hand, so a case
        /// added to this enum drew no row at all: the segment existed, every
        /// `switch` in the page had an arm for it, and there was no way to
        /// reach it. A `switch` with no `default:` makes forgetting a label a
        /// build error instead, and
        /// `ARefusedDoctorIsNotAHealthyMacTests` names all four.
        var label: String {
            switch self {
            case .installed: return HbStr.segInstalled
            case .updates: return HbStr.segUpdates
            case .search: return HbStr.segSearch
            case .health: return HbStr.segHealth
            }
        }

        /// The glyph the toolbar switcher draws for this segment when it is
        /// set to show glyphs. Updates keeps the module's own «an update
        /// exists» symbol, the one Upgrade-all already carries.
        var symbol: String {
            switch self {
            case .installed: return "shippingbox"
            case .updates: return "arrow.up.circle"
            case .search: return "magnifyingglass"
            case .health: return "stethoscope"
            }
        }
    }
    /// Written by the segmented picker's own binding, which never goes through
    /// `select(_:)` — so this half of the subject carries its own retirement.
    @Published var segment: Segment = .installed {
        didSet { if segment != oldValue { subjectMoved() } }
    }

    /// What is selected in each segment, as a `BrewKey` id.
    ///
    /// Per segment, because the three lists hold different things: the
    /// package being read in Установленные is not the hit being read in
    /// Поиск, and coming back to a segment should find what was left there.
    @Published private(set) var selection: [Segment: String] = [:] {
        didSet { if selection[segment] != oldValue[segment] { subjectMoved() } }
    }

    /// The current segment's selection, or nil when nothing is selected.
    var selected: String? { selection[segment] }

    /// `nil` as well as an id: `List(selection:)` writes `nil` when the
    /// person clicks the empty space below the rows, and a setter that
    /// cannot take it turns a deselect into a selection that never goes away.
    func select(_ id: String?) { selection[segment] = id }

    /// The page has stopped describing the package an uninstall was asked
    /// about, so the ask is retired — including one still out over the wire.
    ///
    /// **The subject of an ask is the pair `(segment, selection[segment])`**,
    /// because that pair is what `packageDetail` draws and the Uninstall button
    /// is raised from what it drew. Three gestures move off a package without
    /// pressing Cancel and without leaving the page — Back on the narrow
    /// screen, a click on another row, and the segmented picker — and none of
    /// the three is a later press, so `LatestRequest` does not retire the query
    /// on its own and the answer arrived to raise the app's only irreversible
    /// deletion over a list, a different package or a different segment
    /// (`MovingOffThePackageRetiresAnUninstallAskTests`). Both fields observe
    /// this rather than each gesture: the two are the only writers of the pair,
    /// and a fourth gesture cannot forget to call it.
    ///
    /// Unconditional once the value has actually moved, and that is the point:
    /// a query still in flight has set nothing yet, so a guard on
    /// `pendingUninstall != nil` would pass over exactly the case this exists
    /// for. `cancelUninstall` retires the token as well as the dialog.
    ///
    /// The second reader of this pair is the `brew info` fill, and it is here
    /// for the same reason the retirement is: the subject moves through two
    /// write points and three gestures, and a fill hung off `select(_:)` alone
    /// would leave the segmented picker landing on a remembered selection with
    /// the *previous* segment's package described under it. Both halves of
    /// "stop describing the old package" and "start describing the new one"
    /// happen at the one place the pair is known to have moved.
    private func subjectMoved() {
        cancelUninstall()
        refillInfo()
    }

    /// Drops whatever the second tier was showing and asks about the package
    /// the page is describing now — or about nothing, when nothing is selected.
    ///
    /// **Cleared before the ask, unconditionally.** The facts belong to the
    /// package that was selected when they were read; keeping them across a
    /// move draws openssl@3's licence and homepage under the heading wget for
    /// as long as the new query takes. A refusal leaves it cleared, which is
    /// the same sentence said by a different route.
    private func refillInfo() {
        infoAsk?.cancel()
        info = nil
        // And the figure beside it, for the reason the facts are cleared: a
        // size belongs to the package it was walked for, and openssl@3's
        // 41 MB left standing under the heading wget is a measurement of the
        // wrong thing — the most believable kind of wrong, because it is a
        // real figure about *something*.
        //
        // All the way back to `.notMeasured`, never to `.measuring`: at this
        // line nothing has been asked for the new package yet, and «counting»
        // over a walk that has not been started is the same false promise as a
        // figure nobody measured.
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
        func ref(_ name: String, _ isCask: Bool) -> PackageRef {
            PackageRef(name: name, isCask: isCask)
        }
        switch segment {
        case .installed:
            return installed.first { $0.id == id }.map { ref($0.name, $0.isCask) }
        case .updates:
            return outdated.first { $0.id == id }.map { ref($0.name, $0.isCask) }
        case .search:
            return searchHits.first { $0.id == id }.map { ref($0.name, $0.isCask) }
        // A finding is not a package: there is no `brew info` to ask about it,
        // and `InspectorState.of` draws its second tier from nothing. Returning
        // nil here is what keeps a click on an issue from spending a `brew
        // info` run on a name that is not one.
        case .health:
            return nil
        }
    }

    /// Asks, then assigns only if this is still the ask the page is waiting on.
    ///
    /// The token, not a comparison of names: every move of the subject takes a
    /// token, so `isLatest` answers "is the page still describing the package
    /// this was asked about" in one reading, including the case where the
    /// person moved away and came back — a second ask is out, and this one's
    /// answer is not the one to draw.
    private func loadInfo(_ ref: PackageRef, token: Int) async {
        let answer: PackageInfo? = await client.request(HomebrewCommand.info, encoding: ref)
        guard infoAsks.isLatest(token) else { return }
        // Assigned including nil: a refusal is what the page must show nothing
        // for, and this is the line that says so.
        info = answer

        // **Then the walk, on the same token and never before this line.** The
        // size is the one fact in the inspector that nothing can tell us — it
        // is a walk of a directory (`HomebrewEngine.size`) — so it is asked
        // after the tier it joins has been drawn, and only for a package that
        // is actually on this Mac: a search hit has no keg, and asking about
        // one would spend a walk to learn that.
        //
        // The version comes from the answer above rather than from the list,
        // because it is the version the engine remembers the figure against —
        // reading it from anywhere else would let a figure be filed under a
        // number `brew info` never said.
        guard let version = answer?.installedVersion, !version.isEmpty else { return }
        // **Said before the ask, and it is the ask that earns it.** This line
        // and the one under it are one gesture: the tile says a walk is running
        // exactly while a walk is running, so there is no state in which the
        // page claims to be counting and nothing is. A package with no installed
        // version never reaches here, which is why a search hit gets no tile
        // instead of a promise about a keg that does not exist.
        size = .measuring
        let measured: Int? = await client.request(
            HomebrewCommand.size,
            encoding: PackageSizeRequest(name: ref.name, isCask: ref.isCask, version: version))
        // The same token, asked again: the walk is the longest wait in the
        // inspector, so the screen is likelier to have moved under it than
        // under anything else here. Returning here leaves nothing behind —
        // whatever moved the subject already wrote `.notMeasured`, and this
        // answer belongs to a package nobody is looking at.
        guard infoAsks.isLatest(token) else { return }
        // A refusal is `.notMeasured` and not a lingering «counting»: the walk
        // is over, there is no figure, and the tile goes rather than sitting
        // there for ever saying something is still happening.
        size = measured.map(SizeReading.measured) ?? .notMeasured
    }

    /// Drops `segment`'s selection when its package is no longer in `ids`.
    ///
    /// One segment per call, at the assignment that just replaced *that*
    /// list — a reconcile run against a list that did not change is a silent
    /// way to lose a selection. A list is replaced under a standing
    /// selection for the most ordinary reasons: an uninstall in a terminal,
    /// an upgrade finishing, a second search. A selection that survives its
    /// package leaves the inspector describing something that is gone, with
    /// buttons that would act on it.
    private func reconcile(_ segment: Segment, against ids: Set<String>) {
        guard let id = selection[segment], !ids.contains(id) else { return }
        selection[segment] = nil
    }

    /// One instance per host view model, for the app's lifetime.
    ///
    /// Leaving the page in Settings tears down the subtree and its
    /// `@StateObject`; coming back builds a new one and re-runs `.task`. On a
    /// fresh instance `descriptions` is empty, so returning to Homebrew re-ran
    /// `brew list --versions` twice and a `brew desc` batch over every package
    /// installed — every visit, for a list that had not changed.
    ///
    /// Keyed to the view model it was built against, not merely "exists", for
    /// the reason `DiskViewModel.shared` gives: turning the module off drops
    /// the engine, and a cache held past that is talking to a corpse.
    private static var cached: HomebrewViewModel?
    public static func shared(vm: ModuleViewModel) -> HomebrewViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = HomebrewViewModel(vm: vm)
        cached = created
        // The descriptor's id, not the word typed again: a module id written by
        // hand is tied to the thing it names or it is a comment.
        ModuleUICache.dropWhenDisabled(HomebrewDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        // Held only to start the loop below — it was a stored property nothing
        // read after `init`.
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await e in events {
                guard let self else { break }   // page closed: stop consuming
                self.handle(e)
            }
        }
    }

    /// Ends the event loop, which unregisters the transport subscriber. The
    /// `guard` above already released the view model; without this the task
    /// itself waited for an event that may never come.
    deinit { eventsTask?.cancel() }

    /// What the page asks for on appear — and it asks whether brew is there
    /// every time.
    ///
    /// **Whether Homebrew is installed is not a property of this process.** It
    /// is a file on disk that `FSBrewLocator` re-reads at every call, and it
    /// changes under the app for the most ordinary reasons there are: somebody
    /// follows brew.sh in a terminal, or runs Homebrew's own uninstaller, with
    /// this window open beside it. A `loadedStatus` flag latched by the first
    /// visit meant brew appearing was noticed never and brew vanishing was
    /// noticed never, for the life of the process — `HomebrewSettingsPage.body`
    /// branches on `status.installed` and on nothing else, and the only other
    /// path that re-read the status was `refreshAfterOp`, which needs an
    /// operation to have run: the one thing you cannot do from the install
    /// screen you are stuck on.
    ///
    /// The guard stays where it was earned, on the *expensive* half. Asking the
    /// locator is two `isExecutableFile` calls; asking brew is `brew list
    /// --versions` twice and a `brew desc` batch over every package installed.
    /// And the packages belong to *a* brew, not to the app: a Homebrew
    /// uninstalled and installed again between two visits — or moved from
    /// `/usr/local` to `/opt/homebrew` — is a new Cellar, and the rows of the
    /// one that is gone each carry an Uninstall button the engine now refuses.
    public func loadIfNeeded() async {
        await refreshStatus()
        guard status.installed, !loadedInstalled || listedBrew != status.brewPath else { return }
        await refreshInstalled()
    }

    /// The brew the installed list was last read from.
    private var listedBrew: String?

    public var running: Bool { op.phase == .running }

    // MARK: - Events

    /// The enum, not the two literals the engine also types out — see
    /// `HomebrewEvent`. A name that stops matching here empties the console and
    /// says nothing about why.
    private func handle(_ e: EngineEvent) {
        switch HomebrewEvent(rawValue: e.name) {
        case .opLog:
            consoleLines.append(String(decoding: e.payload, as: UTF8.self))
            // Bounded, the way `LogTail` is. Nothing trimmed this: it is
            // cleared by pressing Clear and by starting an install, so on the
            // ordinary path — upgrade, upgrade again, search — it only grew,
            // for the life of the app, since this view model is cached per host
            // view model. The engine keeps stderr on purpose because a console
            // should show what the tool says, and a `brew` command passes 64 KB
            // of deprecation warnings without trying. Each line is also a view:
            // the page renders a `ForEach` over the whole array and scrolls on
            // every count change, so the cost is paid twice.
            //
            // From the front, which is what a terminal's scrollback does: the
            // end is the half a person is reading.
            if consoleLines.count > Self.consoleLimit {
                consoleLines.removeFirst(consoleLines.count - Self.consoleLimit)
            }
        case .opState:
            guard let s = try? JSONDecoder().decode(OpState.self, from: e.payload) else { return }
            op = s
            // `.failed` as well as `.done`: a failed operation is not a no-op on
            // the machine. `brew upgrade` walks the outdated list and exits
            // non-zero when one package fails to build — everything before it is
            // already upgraded, so the pre-operation lists are stale either way.
            if s.phase == .done || s.phase == .failed { Task { await self.refreshAfterOp() } }
        case .none:
            break
        }
    }

    /// The status too, and it is not a nicety: installing Homebrew is one of
    /// the operations that ends here, and `status.installed` is the only thing
    /// `HomebrewSettingsPage.body` branches on. Refreshing the package lists
    /// but not the status left somebody who had just installed Homebrew looking
    /// at the install screen, with the only way forward being to close Settings
    /// and open it again. Now that the view model outlives the page, closing
    /// Settings no longer papers over it either.
    private func refreshAfterOp() async {
        await refreshStatus()
        await refreshInstalled()
        await refreshOutdated()
        // And what `brew doctor` said, but **only if it has ever been asked**.
        // An operation changes the machine the findings are about — running a
        // fix is the clearest case, since the issue it answers is the one that
        // should now be gone — so a kept reading is the page offering a fix for
        // something already fixed. `brew doctor` is the slowest query in the
        // module, though, and asking it after every install on behalf of
        // somebody who has never opened this segment is a minute of `brew` for
        // an answer nobody is waiting for; `.notAsked` is exactly that person.
        if doctor != .notAsked { await refreshDoctor() }
        // And what `brew config` said, on the same terms and for the same
        // reason: `installBrew` is one of the operations that ends here and it
        // rewrites every line of that document, while `upgrade` of Homebrew
        // itself moves the version and the checkout. Only when it has ever been
        // read — a person who has never opened this segment is not waiting for
        // an answer, and this is a `brew` run per operation.
        if config != nil { await refreshConfig() }
        // And what `brew info` said, which an upgrade rewrites: the first tier
        // takes its version from the list above, so a kept answer left the
        // heading reading 3.7.0 with the tile under it still saying 3.6.4 — one
        // screen carrying two accounts of one package. Last, so the ask goes
        // out against the selection the reconciles above have settled on.
        //
        // **And the Cellar walk that now hangs off it, deliberately.** This
        // line runs after every finished operation, so a directory walk is paid
        // here too — one package's Cellar directory, and only while something
        // is selected. That is the cost worth paying rather than avoiding: an
        // install, an upgrade and a `brew doctor` fix each rewrite the very keg
        // the figure was walked from, so a kept figure is the second account of
        // one package this comment already exists about. The engine drops every
        // remembered figure at the same moment (`HomebrewEngine.size`), so this
        // ask really does re-measure rather than read back what the operation
        // invalidated.
        refillInfo()
    }

    // MARK: - Queries

    public func refreshStatus() async {
        status = await client.request(HomebrewCommand.status) ?? status
        // Carried once: the engine's marker is consumed by the read, so only
        // the first status after an interrupted quit says it — into the
        // console, the surface that already narrates operations.
        if let label = status.interruptedOp {
            consoleLines.append(HbStr.interruptedAtQuit(label))
        }
    }
    /// No `?? []` on any list reply: an empty reply is "the module could not
    /// answer" — a hung brew cut off at the runner's deadline — and it used to
    /// replace a real package list with "No packages installed." The last
    /// answer stays; the log names the outcome; Refresh stays live for a retry.
    public func refreshInstalled() async {
        installedReading = .waiting
        guard let answer: [BrewPackage] = await client.request(HomebrewCommand.listInstalled)
        else {
            // The last answer stays, and so does the reading that describes it:
            // rows on screen are an answer somebody got, and a refusal on top of
            // them is a thing for the log rather than a sentence over a list
            // that is still true. With nothing behind it there is nothing to
            // keep, and the pane says so instead of waiting for ever.
            installedReading = installed.isEmpty ? .unanswerable : .answered
            return
        }
        installed = answer
        reconcile(.installed, against: Set(answer.map(\.id)))
        installedReading = .answered
        listedBrew = status.brewPath
        await loadDescriptions(formulae: installed.filter { !$0.isCask }.map(\.name),
                               casks: installed.filter(\.isCask).map(\.name))
    }
    /// What `brew doctor` said, and **which of the three things it said**.
    ///
    /// A named reason per outcome rather than one array read three ways, for
    /// the rule the port's own doc comment carries: "no issues" and "the
    /// question could not be put" are the same empty array and must never be
    /// the same sentence on screen. A machine nobody could examine is not a
    /// healthy machine, and «Nothing to fix» over a refused query is the app
    /// telling somebody their Mac is fine on the strength of a `brew` that
    /// never answered.
    @Published private(set) var doctor: DoctorReading = .notAsked

    /// The issues to draw, which only an `.examined` reading has. Computed
    /// rather than stored beside `doctor`: two fields are two accounts of one
    /// answer, and the one that goes stale is the one a page reads.
    var issues: [DoctorIssue] { doctor.issues }

    /// What `brew config` last answered — the lines the Configuration heading
    /// is drawn from, **and the document «Copy for a bug report» puts on the
    /// pasteboard**. nil until it has been asked, which is every launch:
    /// `loadIfNeeded` does not ask, the segment's own refresh does.
    @Published private(set) var config: BrewConfig?

    /// Those lines as the three groups the list draws a row each for. Computed
    /// rather than stored beside `config`, for the reason `issues` is: two
    /// fields are two accounts of one answer.
    var configGroups: [ConfigGroup] { ConfigGroup.grouping(config?.lines ?? []) }

    /// **Everything the health list can have selected — findings *and*
    /// configuration groups.**
    ///
    /// The segment's list holds two kinds of thing and `reconcile` takes one
    /// set of ids, so a reconcile that knew only the findings dropped the
    /// person's selection every time the other half was re-read — and a refused
    /// `brew doctor` deselected the configuration group they were reading,
    /// which has nothing to do with `brew doctor` at all.
    private var healthSelectableIDs: Set<String> {
        Set(issues.map(\.id)).union(configGroups.map(\.id))
    }

    /// What `brew config` says about this Homebrew and this Mac.
    ///
    /// **A refusal keeps the last answer**, which is the opposite of
    /// `refreshDoctor` one method down and deliberate: a `brew doctor` reading
    /// *is* the claim about the machine's health, so stale findings under a
    /// failed reading state that those are still what is wrong. A configuration
    /// makes no such claim — it is the module's own `installed`/`outdated` rule
    /// ("no `?? []` on any list reply"), where the last answer is still a true
    /// thing about a machine that has almost certainly not moved.
    func refreshConfig() async {
        guard let answer: BrewConfig = await client.request(HomebrewCommand.config) else { return }
        config = answer
        reconcile(.health, against: healthSelectableIDs)
    }

    /// **A refusal replaces the issues rather than keeping them.** The other
    /// three lists keep their last answer when a query is refused, because a
    /// stale package list is still a list of packages and the page says nothing
    /// about it either way. This one is different in kind: the list *is* the
    /// claim about the machine's health, and holding two issues on screen under
    /// a reading that failed states that those two are still what is wrong. The
    /// honest answer is that nothing is known right now, and the page says so.
    /// Internal, not `public`: nothing outside `Module_Homebrew_UI` calls it,
    /// and `public` in this tree means "another target uses this". Its public
    /// neighbours predate that rule being applied to this file.
    func refreshDoctor() async {
        // **The installed list first, because the verdict is about it.**
        // `DoctorFixCandidate.judging` decides `.runnable` against what is on
        // this Mac, and opening this segment on a fresh launch finds that list
        // unread — every fix would then read `.copyOnly` because the page has
        // no Cellar rather than because the name is not in it. A list that
        // refuses leaves `loadedInstalled` false and every fix copy-only, which
        // is the safe direction and the honest one: Helm withholds the button it
        // has no reading to justify.
        if !loadedInstalled { await refreshInstalled() }
        guard let answer: [DoctorIssue] = await client.request(HomebrewCommand.doctor) else {
            doctor = .refused
            // Against everything the list still holds, not against nothing: the
            // configuration groups are on this list too and a refused `brew
            // doctor` says nothing about them, so sweeping them out here took
            // away the group the person was reading.
            reconcile(.health, against: healthSelectableIDs)
            return
        }
        // The parser always answers `fix: nil` — a command read out of a tool's
        // output is data until it has been judged — so this is where a body
        // becomes a candidate and the candidate gets a verdict. The verdict
        // decides what is *drawn*; `HomebrewEngine.runDoctorFix` takes its own
        // against a list read at the press, which is what decides what runs.
        let installedNames = installed.map(\.name)
        doctor = .examined(answer.map { DoctorFixCandidate.judging($0, installed: installedNames) })
        reconcile(.health, against: healthSelectableIDs)
    }

    /// The fix a person is being asked about, or nil because nothing is being
    /// asked. Beside `pendingUninstall` and for its reason: the page's own
    /// `@State` would answer nobody, and which press raised which question is
    /// the whole of what a test has to be able to see.
    @Published private(set) var pendingFix: DoctorFix?

    /// The press on Run, which is not the same thing as running it.
    ///
    /// `FixAsk` decides — `brew cleanup` goes straight to the engine, and
    /// anything that takes a package off this Mac raises the question the
    /// Uninstall button has raised since somebody noticed it removed an
    /// application on a single click. The judgement is `FixAsk.of`'s and not
    /// this method's, so a test reads it without a `body` in the way.
    func askToRunFix(_ fix: DoctorFix) {
        switch FixAsk.of(fix.argv) {
        case .runsOnThePress: runDoctorFix(fix)
        case .uninstalls, .unrecognised: pendingFix = fix
        }
    }

    /// Closes the question without running anything. Called by the dialog's
    /// Cancel and by the page going away, for `cancelUninstall`'s reason: this
    /// object outlives the page, and a question left standing is one the next
    /// visit opens with.
    func cancelFix() { pendingFix = nil }

    /// The press on the dialog Run raised. The only door to a destructive fix.
    func confirmFix() {
        guard let fix = pendingFix else { return }
        pendingFix = nil
        runDoctorFix(fix)
    }

    /// Sends one `brew doctor` fix to the engine, which judges it again before
    /// it runs anything.
    ///
    /// **Private: `askToRunFix` is the door.** It was the page's own call site,
    /// so a fix that removes a package for good went on a single click while
    /// every other irreversible deletion in Helm asked first.
    ///
    /// The argv goes over the wire as it was drawn, and that is deliberate:
    /// this side does not re-read the Cellar and does not re-judge, because a
    /// second judgement here would be a second one against the same stale
    /// reading. `HomebrewEngine.runDoctorFix` reads the installed list at the
    /// press and refuses anything `DoctorFix.judge` will not admit — including
    /// the case this design exists for, a package uninstalled in a terminal
    /// between the draw and the press.
    private func runDoctorFix(_ fix: DoctorFix) {
        client.fire(HomebrewCommand.doctorFix, encoding: fix.argv)
    }

    public func refreshOutdated() async {
        outdatedReading = .waiting
        guard let answer: [OutdatedPackage] = await client.request(HomebrewCommand.outdated)
        else {
            outdatedReading = outdated.isEmpty ? .unanswerable : .answered
            return
        }
        outdated = answer
        reconcile(.updates, against: Set(answer.map(\.id)))
        outdatedReading = .answered
    }
    /// `loadedInstalled`'s twin, derived from `outdatedReading` for the same
    /// reason. `loadIfNeeded` deliberately never asks `brew outdated`, so this
    /// is false on every launch until somebody opens the segment — which is
    /// what `AStatusLineDoesNotInventZeroUpdatesTests` holds.
    public var loadedOutdated: Bool { outdatedReading == .answered }

    /// Which search the hits belong to, so an older answer cannot land on a
    /// newer one — and so a search nobody is waiting for any more stops
    /// spending `brew` runs on descriptions.
    ///
    /// **A counter rather than a latch**, for the reason `LatestRequest` gives:
    /// the second search exists because the person typed something else, and
    /// refusing it would leave the screen showing the results of a word they
    /// have moved on from. What has to be dropped is the older *answer*.
    ///
    /// Duplicates and Leftovers had this and Homebrew did not, which is what
    /// made a Return key expensive: `search` runs two `brew search` calls in
    /// sequence — measured at about nine seconds — and then a `brew desc` per
    /// kind, and the page put every press on its own unbounded `Task`. Ten
    /// presses were ten of those at once; the crash report that started this
    /// shows ten threads inside one `brew` call and nine more waiting on a
    /// pipe, with the twenty-first launch the one that raised.
    private var searches = LatestRequest()

    public func search(_ q: String) async {
        let mine = searches.take()
        // **The old hits go before the new query is sent.** They belong to the
        // word that was typed over, and holding them for the nine seconds this
        // takes is the results of one search drawn under another — which is
        // also what left the busy sentence with nothing to stand over.
        searchHits = []
        reconcile(.search, against: [])
        searchReading = .waiting
        guard let hits: [SearchHit] = await client.request(HomebrewCommand.search,
                                                           payload: Data(q.utf8))
        else {
            // Only for the press still being waited on: a refusal for a word
            // the person has typed over must not put its sentence over a newer
            // search's results.
            if searches.isLatest(mine) { searchReading = .unanswerable }
            return
        }
        // The hits first: a stale answer must not replace what a newer search
        // has already drawn.
        guard searches.isLatest(mine) else { return }
        searchHits = hits
        searchReading = .answered
        reconcile(.search, against: Set(hits.map(\.id)))
        await loadDescriptions(formulae: searchHits.filter { !$0.isCask }.map(\.name),
                               casks: searchHits.filter(\.isCask).map(\.name),
                               token: mine)
    }

    public func description(name: String, isCask: Bool) -> String? {
        descriptions[BrewKey.of(name: name, isCask: isCask)]
    }

    /// Only what is not held yet, one `brew desc` call per kind.
    ///
    /// Every key here goes through `BrewKey`. The prefix used to be written out
    /// at each of these five places and at the three row identities, and the two
    /// halves have to agree exactly: a description stored under a key no row
    /// asks for is a row with no description and nothing in any log.
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
              let found: [String: String] = await client.request(
                  HomebrewCommand.descriptions,
                  encoding: DescriptionsRequest(names: wanted, isCask: isCask))
        else { return }
        // A description is keyed by the package it describes, so a late batch
        // is not *wrong* — but writing it republishes the whole dictionary and
        // redraws a list the person is no longer looking at.
        guard token.map(searches.isLatest) ?? true else { return }
        for (name, text) in found { descriptions[BrewKey.of(name: name, isCask: isCask)] = text }
    }

    // MARK: - Operations (fire-and-forget; progress via events)

    public func install(_ hit: SearchHit) {
        client.fire(HomebrewCommand.install,
                    encoding: PackageRef(name: hit.name, isCask: hit.isCask))
    }
    /// Which press the dialog belongs to, so an older query cannot raise one.
    ///
    /// The same counter `search` keeps, for the reason `LatestRequest` gives,
    /// and here the act it guards is the app's only irreversible deletion.
    /// Nothing is disabled while this query is out — the page's `disabled`
    /// tracks long operations, not queries — so two presses put two queries in
    /// flight and the last continuation to resume used to win: the answer for a
    /// package pressed and abandoned would raise its own confirmation dialog, or
    /// swap the title and the list under somebody reading them.
    private var uninstallAsks = LatestRequest()

    /// Asks the Cellar what still needs this package, then raises the dialog.
    ///
    /// The reading is taken here, one press before the act, because that is the
    /// last moment at which it is true: the answer is about a Cellar that a
    /// terminal beside this window can change. A refusal — brew hung, brew gone
    /// — leaves the list empty and the dialog says only what it always said;
    /// it must not invent a reassurance out of a query that never answered.
    public func askToUninstall(_ pkg: BrewPackage) async {
        let mine = uninstallAsks.take()
        let answer: [String]? = await client.request(
            HomebrewCommand.dependents,
            encoding: PackageRef(name: pkg.name, isCask: pkg.isCask))
        // Both halves or neither, and only for the press still being waited on:
        // the package named in the title and the names under it are one reading
        // of one Cellar, and a dialog carrying two presses' worth is a sentence
        // about a package that is not the one about to be deleted.
        guard uninstallAsks.isLatest(mine) else { return }
        dependentsOfPending = answer ?? []
        pendingUninstall = pkg
    }

    /// Closes the dialog and abandons whatever reading is still out — a token
    /// taken and dropped, which is how `LatestRequest` retires work in flight.
    /// Without that line a query for an earlier press comes back to a screen
    /// with nothing on it and puts a confirmation there by itself.
    public func cancelUninstall() {
        _ = uninstallAsks.take()
        pendingUninstall = nil
        dependentsOfPending = []
    }

    /// Sends the uninstall the dialog was raised for, and clears the reading
    /// with it.
    ///
    /// The only door in this target to `brew uninstall`: a row's button asks
    /// (`askToUninstall`) and this is the press on the dialog it raised, so the
    /// deletion cannot be reached without the sentence saying what it takes
    /// with it. The `uninstall(_:)` that used to sit beside it was a second,
    /// unconfirmed one, with no caller left outside this type.
    public func confirmUninstall() {
        guard let pkg = pendingUninstall else { return }
        cancelUninstall()
        client.fire(HomebrewCommand.uninstall,
                    encoding: PackageRef(name: pkg.name, isCask: pkg.isCask))
    }
    public func upgrade(_ pkg: OutdatedPackage) {
        client.fire(HomebrewCommand.upgrade, payload: Data(pkg.name.utf8))
    }
    public func upgradeAll() { client.fire(HomebrewCommand.upgradeAll) }
    public func installBrew() { consoleLines.removeAll(); client.fire(HomebrewCommand.installBrew) }
    /// Ends the running operation; the engine reports the exit as `.stopped`.
    public func stop() { client.fire(HomebrewCommand.stop) }

    public func clearConsole() { consoleLines.removeAll() }
}
