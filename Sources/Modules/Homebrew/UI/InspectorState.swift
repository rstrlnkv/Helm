import Foundation
import HelmUI
import Module_Homebrew_Engine

/// What the inspector draws, decided without a view.
///
/// **Two of the three tabs have an inspector; Состояние does not.** Its findings
/// open in place in a card of their own and its configuration opens the same
/// way (`HomebrewHealthPage`), so there is nothing to select there and nothing
/// for this type to describe: `.health` answers `.nothingToSelect`, which the
/// page never mounts.
///
/// `AvailableSection.of` is the shape this follows: the page asks a value type
/// what it is looking at, and the decision is held by a test rather than by a
/// screenshot. Everything here is a function of what the page already has — no
/// query of its own, and nothing that can be waited on.
///
/// Internal, not `public` — nothing outside `Module_Homebrew_UI` reads this
/// (`public` in this tree means "another target uses this").
enum InspectorState: Equatable {
    /// **There are rows, and none of them is picked.** The invitation, and the
    /// only reading it is honest under.
    case nothingSelected
    /// **There is nothing to pick.** The list beside this is empty — because
    /// the query is still out, because it answered nothing, or because it could
    /// not be put at all — and «Select a package» over it invites a choice
    /// nobody can make. Measured 2026-09-16 on a 984 pt pane: the invitation
    /// occupied 515 of 984 pt, 52 % of the pane, beside a master saying
    /// Homebrew had not answered; at its worst, on a Состояние whose findings
    /// *and* configuration both refused, one unselectable sentence on the left
    /// and an invitation on the right.
    ///
    /// **One case for all three of waiting, empty and refused, and that is the
    /// point.** The list's own three sentences are `ListScreen`'s job and they
    /// differ; the inspector's answer to all three is the same, because what
    /// makes the invitation wrong is that the list holds nothing, not why. Two
    /// accounts of one fact on one screen is what the page is being repaired
    /// of — the inspector repeating the master's sentence in its own words
    /// would be a third.
    case nothingToSelect
    case package(InspectorSubject)
    /// `hits` is what the "Available to install" section under whichever list
    /// is on screen actually draws (`HomebrewViewModel.shownHits`) — already
    /// filtered to what is not on this Mac, by id — so both package segments
    /// fall back to it the same way and neither needs its own "already
    /// installed" reading any more (`PackageStanding.notInstalled` is where
    /// that exclusion happens once). The health segment never gets this far:
    /// it answers `.nothingToSelect` before `hits` is read.
    ///
    /// `shownEmpty` is nil for a caller with no filter of its own — every
    /// existing test keeps the two-list reading below byte for byte. The
    /// page passes its own segment's filtered emptiness once a query is in
    /// the field: `installed`/`outdated` stay the *full*
    /// lists here regardless, because a lookup by id and the update fact a
    /// selected package's row carries (`PackageStanding.updates`) are correct
    /// off the full list whenever `selected` is reachable at all — dropping a
    /// row from the shown lists always drops its selection first
    /// (`reconcileVisible`) — and only the *emptiness* question needs the
    /// filtered count: a list a query has emptied is not the same fact as a
    /// Cellar with nothing in it, and "Select a package" over the first is
    /// exactly the invitation `.nothingToSelect` exists to withhold.
    static func of(segment: HomebrewViewModel.Segment,
                   selected: String?,
                   installed: [BrewPackage],
                   outdated: [OutdatedPackage],
                   loadedOutdated: Bool,
                   hits: [SearchHit],
                   descriptions: [String: String],
                   shownEmpty: Bool? = nil) -> InspectorState {
        // **Asked before the selection is, and of the same lists the master
        // draws.** A pane with nothing in it cannot have something picked out
        // of it, so a stale `selected` left over from a list that has since
        // emptied is not a reason to go on offering the invitation either.
        // `hits` counts on the two package tabs, since the section it
        // describes sits under those and not under Состояние.
        //
        // **Состояние first, and whatever it is holding.** It has no inspector
        // (see the type's own comment), so a selection left on it is not
        // something this could describe, and a hit the section drew there —
        // it no longer draws one — is not one to offer an install for.
        if segment == .health { return .nothingToSelect }
        let empty: Bool
        if let shownEmpty {
            empty = shownEmpty && hits.isEmpty
        } else {
            switch segment {
            case .installed: empty = installed.isEmpty && hits.isEmpty
            case .updates: empty = outdated.isEmpty && hits.isEmpty
            case .health: return .nothingToSelect // answered above
            }
        }
        if empty { return .nothingToSelect }
        guard let selected else { return .nothingSelected }
        let desc = descriptions[selected]
        /// The one hit lookup every segment falls back to — a package offered
        /// under the section is never anything but an install, since `hits`
        /// has already had what is on this Mac filtered out of it.
        func hit(_ h: SearchHit) -> InspectorState {
            .package(InspectorSubject(id: h.id, name: h.name, isCask: h.isCask,
                                      version: "", desc: desc, updates: .notApplicable,
                                      action: .install))
        }
        switch segment {
        case .installed:
            if let p = installed.first(where: { $0.id == selected }) {
                return .package(InspectorSubject(
                    id: p.id, name: p.name, isCask: p.isCask, version: p.version, desc: desc,
                    updates: PackageStanding.updates(for: p.id, outdated: outdated,
                                                     loadedOutdated: loadedOutdated),
                    action: .uninstall))
            }
            guard let h = hits.first(where: { $0.id == selected }) else { return .nothingSelected }
            return hit(h)
        case .updates:
            if let p = outdated.first(where: { $0.id == selected }) {
                return .package(InspectorSubject(
                    id: p.id, name: p.name, isCask: p.isCask,
                    version: "\(p.installed) → \(p.latest)", desc: desc, updates: .notApplicable,
                    // A pinned formula is listed and not offered: `brew upgrade`
                    // answers it with "…is pinned", so the button could only
                    // ever fail.
                    action: p.pinned ? .pinned : .upgrade))
            }
            guard let h = hits.first(where: { $0.id == selected }) else { return .nothingSelected }
            return hit(h)
        case .health:
            return .nothingToSelect // answered above
        }
    }
}

/// What `brew doctor` answered — **and which of the three things it answered**.
///
/// The enum exists because two of the three are the same empty array, and the
/// port's own doc comment (`DoctorParser.parse`) says so: nil is "the tool said
/// nothing", `[]` is "it ran and found nothing". A caller that must tell them
/// apart gets an enum naming each reason rather than a convention for reading
/// one optional two ways — and here the caller that must tell them apart is a
/// sentence a person decides whether to trust their Mac on.
enum DoctorReading: Equatable {
    /// Nobody has asked yet. The ordinary state of every launch: `loadIfNeeded`
    /// does not run `brew doctor`, which is the slowest query in the module, so
    /// this is what the segment shows until somebody opens it.
    case notAsked
    /// `brew doctor` ran and this is what it found — possibly nothing, which is
    /// the one reading that may be drawn as a healthy machine.
    case examined([DoctorIssue])
    /// The question could not be put: brew is gone, the run timed out, the
    /// tool printed nothing at all where it always prints something, or it
    /// exited non-zero with nothing in its answer this build could read
    /// (`HomebrewEngine.doctor` — the reasons all arrive as the same empty
    /// reply, and this case is all of them). Not a
    /// clean machine — an unexamined one.
    case refused

    var issues: [DoctorIssue] {
        if case let .examined(issues) = self { return issues }
        return []
    }
}

/// What `brew doctor`'s reading comes to for the health tab — **four answers,
/// and the middle two are the whole point.**
///
/// `AvailableSection.of` is the shape this follows, for the reason that file
/// gives: which sentence stands over which state is the whole of the decision,
/// and a `body` is nowhere a test can reach.
///
/// `.clean` and `.unexaminable` are both an empty list of findings and they are
/// not the same sentence. One is `brew doctor` having looked and found nothing, which
/// is the only reading that may be drawn as a healthy machine; the other is the
/// question never having been put — brew gone, the run cut off at the deadline,
/// a tool that printed nothing where it always prints something, or one that
/// exited non-zero with nothing in its answer this build could read. Collapsed
/// into one they read as «Nothing to fix» over a Mac nobody examined, which is
/// this app telling somebody their machine is fine on the strength of an answer
/// it never got.
enum HealthListState: Equatable {
    /// Nobody has asked yet, and something is on its way.
    case busy
    /// Examined, and nothing was found.
    case clean
    /// The question could not be put. Not a clean machine — an unread one.
    case unexaminable
    case rows([DoctorIssue])

    static func of(_ reading: DoctorReading) -> HealthListState {
        switch reading {
        case .notAsked: return .busy
        case .refused: return .unexaminable
        case let .examined(issues): return issues.isEmpty ? .clean : .rows(issues)
        }
    }
}

/// One group of `brew config`'s lines, under one of the three headings this
/// app invented for them.
///
/// **The grouping is presentation and lives here rather than in the engine.**
/// `brew config` prints one flat list; `ConfigLine.section` is the engine's
/// answer for *which* heading a line belongs under, and this is the list the
/// configuration card draws a block for. A group with no lines in it is not a group:
/// an empty heading over nothing is a promise the document did not make.
struct ConfigGroup: Equatable, Identifiable {
    let section: ConfigSection
    let lines: [ConfigLine]
    /// Prefixed, so a group's id can never be read as a package's `BrewKey`
    /// (`f:`/`c:`) nor as a `DoctorIssue`'s, which is built from the finding's
    /// own text around NUL separators.
    var id: String { "cfg:" + section.rawValue }

    /// The groups in `ConfigSection.allCases` order — which is the order the
    /// approved drawing puts them in — each keeping brew's own order inside it.
    ///
    /// Not a `Dictionary(grouping:)`: that answers in whatever order the hash
    /// happens to give, so the three headings would change places between
    /// launches, and the lines inside a group would too.
    static func grouping(_ lines: [ConfigLine]) -> [ConfigGroup] {
        ConfigSection.allCases.compactMap { section in
            let own = lines.filter { $0.section == section }
            return own.isEmpty ? nil : ConfigGroup(section: section, lines: own)
        }
    }
}

/// **What `brew doctor` says about this Mac, in the one line the tab opens with
/// — the verdict.**
///
/// `HealthListState`'s four answers as a value the header is drawn from, and
/// it is read off the *unfiltered* reading and never off what the search field
/// leaves: a word typed over the page must not be able to say the Mac is clean
/// (`HealthScreen.of`).
///
/// `.clean` and `.unexaminable` stay two, for the reason `HealthListState`
/// spells out: «Nothing to fix» is earned only by a `brew doctor` that ran and
/// named nothing, and a refusal says what is *not known*. The count rides on
/// `.findings` so a verdict of zero findings cannot be spelled.
enum HealthVerdict: Equatable {
    /// Nobody has asked yet, or the ask is out.
    case checking
    /// Examined, and nothing was found.
    case clean
    /// The question could not be put.
    case unexaminable
    /// Examined, and this many findings — never zero.
    case findings(Int)
}

/// **What the whole health tab puts on screen: a verdict, the findings the
/// search field leaves, and the configuration the search field leaves.**
///
/// The tab used to be a striped list with an inspector beside it and the
/// sentence for each reading a row in that list. It is one page now — the
/// verdict first, then a card of findings that each open in place, then the
/// configuration in a card of its own (`HomebrewHealthPage`) — so what the
/// three parts hold is decided here, where a test can reach it and a `body`
/// cannot.
///
/// **The fourth reading, `noMatches`, is about the findings and not about the
/// Mac.** `brew doctor` really finding nothing and a query hiding what it did
/// find are two different facts, and collapsing them would let a stray
/// character in the search field tell somebody their Mac has nothing wrong
/// with it. So the verdict is always the unfiltered one, and a filter that
/// empties a non-empty list is `noMatches` under it, in the place of the card.
struct HealthScreen: Equatable {
    let verdict: HealthVerdict
    /// The findings a needle keeps, in brew's order. Empty for every verdict
    /// but `.findings`, and also for one whose findings the needle hides.
    let findings: [DoctorIssue]
    /// The needle hides every finding there is.
    let noMatches: Bool
    /// The groups a needle keeps — all of them without one. Empty when `brew
    /// config` has answered nothing, and then the card is not drawn at all: a
    /// card with nothing in it is a promise the document did not make.
    let configuration: [ConfigGroup]

    /// The findings a needle keeps — its title and its body. `of(_:config:needle:)`
    /// is its one caller; it is a function of its own so that what an unmatched
    /// finding is stays one sentence, apart from the screen that is built
    /// around it.
    static func matchingIssues(_ needle: String?, _ issues: [DoctorIssue]) -> [DoctorIssue] {
        guard let needle else { return issues }
        return issues.filter { ListFilter.matches(needle, [$0.title, $0.body]) }
    }

    /// The groups a needle keeps — a group's own heading, or any line's key
    /// or value. Whole groups rather than lines: there is no reading in which
    /// the page shows a group with some of its own lines missing.
    static func matchingConfigGroups(_ needle: String?, _ groups: [ConfigGroup]) -> [ConfigGroup] {
        guard let needle else { return groups }
        return groups.filter { group in
            ListFilter.matches(needle, [HbStr.configSectionName(group.section)])
                || group.lines.contains { ListFilter.matches(needle, [$0.key, $0.value]) }
        }
    }

    /// **The only finding is open, and stays open.** A card of one row that
    /// hides its one paragraph asks a click for nothing, so it is drawn open
    /// and given no control to close it (`canToggle`). `total` is the reading's
    /// own count of findings and not what a needle leaves, so a word that
    /// narrows three findings to one does not make that one uncloseable.
    static func isOpen(_ issue: DoctorIssue, of total: Int, opened: Set<String>) -> Bool {
        total == 1 || opened.contains(issue.id)
    }

    /// Whether a finding's title is a control at all — see `isOpen`.
    static func canToggle(total: Int) -> Bool { total > 1 }

    /// `needle` is nil for the ordinary, unfiltered reading.
    static func of(_ reading: DoctorReading, config: [ConfigGroup],
                   needle: String? = nil) -> HealthScreen {
        let configuration = matchingConfigGroups(needle, config)
        switch HealthListState.of(reading) {
        case .busy:
            return HealthScreen(verdict: .checking, findings: [], noMatches: false,
                                configuration: configuration)
        case .clean:
            return HealthScreen(verdict: .clean, findings: [], noMatches: false,
                                configuration: configuration)
        case .unexaminable:
            return HealthScreen(verdict: .unexaminable, findings: [], noMatches: false,
                                configuration: configuration)
        case let .rows(issues):
            let shown = matchingIssues(needle, issues)
            return HealthScreen(verdict: .findings(issues.count), findings: shown,
                                noMatches: shown.isEmpty, configuration: configuration)
        }
    }
}

struct InspectorSubject: Equatable {
    enum Action: Equatable { case uninstall, upgrade, install, pinned }

    /// Four named reasons rather than one optional read three ways:
    /// `loadIfNeeded` never asks `brew outdated`, so `.notAsked` is the
    /// ordinary state on first open and must not be drawn as `.upToDate`.
    /// `pinned` rides on `.available` rather than standing beside it because it
    /// is a fact about *that* update and nothing else: a pinned formula still
    /// has a newer version, so the row's marker and the sentence are unchanged,
    /// and only the action beside them is. `brew upgrade` answers a pinned
    /// formula with "…is pinned", so a button offered here could only ever
    /// fail — the same reason `Action.pinned` exists one segment over, said
    /// once so the two cannot disagree about one package.
    enum Updates: Equatable {
        case notApplicable, notAsked, upToDate
        case available(String, pinned: Bool = false)
    }

    /// The `BrewKey` id — the only thing an action may look a package up by.
    /// A name alone collides: `docker` is both a formula and a cask.
    let id: String
    let name: String
    let isCask: Bool
    /// One version installed, "a → b" outdated, the installed version for a
    /// hit already on this Mac, "" for a hit that is not.
    let version: String
    /// nil until the `brew desc` batch answers — never an empty string, which
    /// the view would draw as a blank line that later fills and re-flows.
    let desc: String?
    let updates: Updates
    let action: Action
}

/// One tile of the package view's second tier: a label, and a value that was
/// actually read.
///
/// A value type rather than a view, for the reason `InspectorState` above gives:
/// which tiles an answer earns is the whole of the decision, and a `body` is not
/// somewhere a test can reach.
struct PackageFact: Equatable {
    let label: String
    let value: String
}

/// What is known about the disk a package occupies: nothing, a walk that is out
/// right now, or a figure.
///
/// **Three states rather than an optional, because the middle one is not an
/// absence.** `brew info --json=v2` carries no size in either direction, so the
/// figure is a walk of the package's own Cellar directory — the one reading in
/// the inspector that takes long enough to be worth saying something about. An
/// `Int?` folded «nobody has asked», «a walk is out» and «the walk answered
/// nothing» into one nil, and a view given that nil can only ever draw the same
/// thing for all three: it cannot say a measurement is under way without
/// claiming one where none was started, which is the whole of what
/// `PackageFacts` refuses.
///
/// A fourth state for «the walk was refused» would be a distinction with nothing
/// to say: the tile is absent either way, and a person who never saw one cannot
/// tell «no walk» from «a walk that failed» because neither is a fact about the
/// package. So a refusal lands back on `.notMeasured`, deliberately.
///
/// Never `.measured(0)` from the engine: a missing keg, a directory that would
/// not open and a cask are all nil there (`HomebrewEngine.size`), because a zero
/// in a tile is not a gap on the page — it is a measurement, and it says the
/// package occupies nothing.
enum SizeReading: Equatable, Sendable {
    /// Nothing has been walked and nothing is being walked: no tile.
    case notMeasured
    /// A walk is in flight **for the package on screen now**: the tile is there
    /// and says so.
    case measuring
    /// The walk answered, in bytes.
    case measured(Int)
}

/// Which tiles `brew info`'s answer earns — and no others.
///
/// **An absent fact is an absent tile.** Installed and not installed are two
/// different sets rather than one set with holes in it: "Version" over the
/// catalogue's number is a different sentence from "Installed version" over what
/// is on disk, and a package that is not installed has no install date and
/// nobody asked for it. Inside each set every tile is still dropped when its own
/// fact is nil, because the fields are optional for reasons that happen
/// constantly rather than rarely — a cask's document records neither a licence
/// nor who asked for it, so a cask simply has fewer tiles than a formula.
///
/// A placeholder would be worse than the gap in both directions: a dash reads as
/// "Homebrew answered and had nothing", and a zero reads as a measurement.
///
/// **The size is the one fact here that did not come with the answer.** `brew
/// info` carries no size in either direction, so it is a walk of the package's
/// own Cellar directory that lands later than everything else — a separate
/// parameter rather than a field of `PackageInfo`.
///
/// **It is also the one tile that may stand for a state rather than a figure,
/// and only for the one state that is really happening.** `.measuring` means a
/// walk is out *now, for this package*, so the tile says the figure is being
/// counted and then swaps it in place; `.notMeasured` covers everything else —
/// nothing selected, not installed, the walk refused — and earns no tile at all,
/// by exactly the rule the four above obey. There is deliberately still no «you
/// will know once it is installed» for a package that is not here: nothing is
/// walking, nothing ever will, and that sentence promises a number that never
/// comes. The distinction is carried by `SizeReading` rather than by a word this
/// enum would have to recognise, because a string a caller can spell is a state
/// a caller can invent.
enum PackageFacts {
    static func of(_ info: PackageInfo, size: SizeReading) -> [PackageFact] {
        var facts: [PackageFact] = []
        if let installed = info.installedVersion {
            facts.append(PackageFact(label: HbStr.tileInstalledVersion, value: installed))
            if let at = info.installedAt {
                // The shared helper, keyed by the app's language: a
                // `DateFormatter` built with no locale answers in the
                // *system's*, which on a Mac outside Helm's eight means an
                // English page with somebody else's dates spliced into it.
                facts.append(PackageFact(label: HbStr.tileInstalledOn,
                                         value: HelmDates.day(at)))
            }
            if let onRequest = info.installedOnRequest {
                facts.append(PackageFact(label: HbStr.tileHowItGotHere,
                                         value: onRequest ? HbStr.installedOnRequest
                                                          : HbStr.installedAsDependency))
            }
        } else {
            if let version = info.latestVersion {
                facts.append(PackageFact(label: HbStr.tileVersion, value: version))
            }
            if let licence = info.license {
                facts.append(PackageFact(label: HbStr.tileLicence, value: licence))
            }
        }
        // Last, and in both sets: it is the tile that arrives last, and a grid
        // whose earlier tiles moved when it landed would re-flow the page under
        // somebody's eyes. Holding the place while the walk is out is the other
        // half of that — the figure then swaps into a tile that is already
        // there rather than pushing one in beside the others.
        //
        // `Bytes` and not a formatter of its own — a Foundation one built with
        // no locale answers in the *system's* language, which on a Mac outside
        // Helm's eight is an English page with somebody else's units spliced
        // into it.
        switch size {
        case .notMeasured: break
        case .measuring:
            facts.append(PackageFact(label: HbStr.tileOnDisk, value: HbStr.countingTheSize))
        case let .measured(bytes):
            facts.append(PackageFact(label: HbStr.tileOnDisk, value: Bytes(bytes)))
        }
        return facts
    }
}

/// Whether the second tier's two always-present blocks have anything to draw.
///
/// **A stack that resolves to zero height is not the same as no stack.** A
/// `VStack`'s spacing is not paid around an absent child, which is why
/// `factTiles` collapses to nothing when it earns no tile — but `origin` and
/// `notes` were unconditional stacks, so for the commonest package of all (an
/// installed formula somebody asked for, no other version lines, not deprecated)
/// the tier paid its 24 pt step around each of two empty blocks where the
/// design's rhythm is 12.
///
/// Here rather than as computed properties of the view, for the reason
/// `PackageFacts` is here: a `body` is nowhere a test can reach, and the question
/// is about the answer rather than about the layout.
///
/// Presence is all these ask, because presence is all there is to ask:
/// `BrewInfoParser` maps a blank value to nil at the one place the document is
/// read, so a field that is there has something in it.
enum PackageBlocks {
    /// Either half of the origin line is enough to draw it — a package with a
    /// homepage and no tap is an ordinary answer, and so is the reverse.
    static func hasOrigin(_ info: PackageInfo) -> Bool {
        info.homepage != nil || info.tap != nil
    }

    /// The deprecation banner, "it came in as a dependency", and the other
    /// version lines. `installedOnRequest` is read as a *value* rather than for
    /// presence: nil is a cask, which records nobody, `true` is somebody asked
    /// for it, and only `false` is something to say.
    static func hasNotes(_ info: PackageInfo) -> Bool {
        info.deprecationReason != nil || info.installedOnRequest == false
            || !info.siblings.isEmpty
    }
}

/// The two questions the rows and the inspector both ask, answered once —
/// published sets "built once from the same expressions the behaviour consults" (CLAUDE.md).
enum PackageStanding {
    /// Whether an installed package has an update waiting, without asking
    /// `brew outdated` again: it reads the list the page already holds, and
    /// says "not asked" rather than "up to date" when that list has never
    /// come back.
    static func updates(for id: String, outdated: [OutdatedPackage],
                        loadedOutdated: Bool) -> InspectorSubject.Updates {
        if let op = outdated.first(where: { $0.id == id }) {
            return .available(op.latest, pinned: op.pinned)
        }
        return loadedOutdated ? .upToDate : .notAsked
    }

    /// The search hits that are **not** already on this Mac, filtered by
    /// `BrewKey` id and never by name — `docker` is both a formula and a
    /// cask, so an installed formula must not hide an offered cask of the
    /// same name, and the reverse.
    static func notInstalled(_ hits: [SearchHit], installed: [BrewPackage]) -> [SearchHit] {
        let ids = Set(installed.map(\.id))
        return hits.filter { !ids.contains($0.id) }
    }

    /// `installed`, kept where `needle` matches the name or — once it has
    /// loaded — the description. nil `needle` keeps everything.
    static func matching(_ needle: String?, _ installed: [BrewPackage],
                         descriptions: [String: String]) -> [BrewPackage] {
        guard let needle else { return installed }
        return installed.filter { ListFilter.matches(needle, [$0.name, descriptions[$0.id]]) }
    }

    /// `outdated`'s twin.
    static func matching(_ needle: String?, _ outdated: [OutdatedPackage],
                         descriptions: [String: String]) -> [OutdatedPackage] {
        guard let needle else { return outdated }
        return outdated.filter { ListFilter.matches(needle, [$0.name, descriptions[$0.id]]) }
    }
}
