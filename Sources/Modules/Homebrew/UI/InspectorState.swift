import Foundation
import HelmUI
import Module_Homebrew_Engine

/// What the inspector draws, decided without a view.
///
/// `SearchDisplay.state` is the shape this follows: the page asks a value type
/// what it is looking at, and the decision is held by a test rather than by a
/// screenshot. Everything here is a function of what the page already has — no
/// query of its own, and nothing that can be waited on.
///
/// Internal, not `public` — nothing outside `Module_Homebrew_UI` reads this
/// (`public` in this tree means "another target uses this").
enum InspectorState: Equatable {
    case nothingSelected
    case package(InspectorSubject)
    /// One `brew doctor` finding, whole. Unlike a package, nothing is composed
    /// for it from two containers and nothing about it is waited on — the
    /// severity, the title and the body all arrive together from the one query,
    /// and the fix beside them was put there by `HomebrewViewModel.refreshDoctor`
    /// before this was ever asked.
    case issue(DoctorIssue)
    /// One group of `brew config`'s lines, whole. The other half of what the
    /// health list holds: the segment's list has two kinds of thing in it, and
    /// the inspector describes whichever is selected.
    case configSection(ConfigGroup)

    static func of(segment: HomebrewViewModel.Segment,
                   selected: String?,
                   installed: [BrewPackage],
                   outdated: [OutdatedPackage],
                   loadedOutdated: Bool,
                   hits: [SearchHit],
                   issues: [DoctorIssue],
                   config: [ConfigGroup],
                   descriptions: [String: String]) -> InspectorState {
        guard let selected else { return .nothingSelected }
        let desc = descriptions[selected]
        switch segment {
        case .installed:
            guard let p = installed.first(where: { $0.id == selected }) else { return .nothingSelected }
            return .package(InspectorSubject(
                id: p.id, name: p.name, isCask: p.isCask, version: p.version, desc: desc,
                updates: PackageStanding.updates(for: p.id, outdated: outdated,
                                                 loadedOutdated: loadedOutdated),
                action: .uninstall))
        case .updates:
            guard let p = outdated.first(where: { $0.id == selected }) else { return .nothingSelected }
            return .package(InspectorSubject(
                id: p.id, name: p.name, isCask: p.isCask,
                version: "\(p.installed) → \(p.latest)", desc: desc, updates: .notApplicable,
                // A pinned formula is listed and not offered: `brew upgrade`
                // answers it with "…is pinned", so the button could only ever
                // fail.
                action: p.pinned ? .pinned : .upgrade))
        case .search:
            guard let h = hits.first(where: { $0.id == selected }) else { return .nothingSelected }
            // An installed cask or formula found again by search offers its
            // removal, not a second install — the row draws the same fact as
            // a badge (`design/Main.dc.html:400`).
            if let already = PackageStanding.installedVersion(of: h.id, installed: installed) {
                return .package(InspectorSubject(id: h.id, name: h.name, isCask: h.isCask,
                                                 version: already, desc: desc, updates: .notApplicable,
                                                 action: .uninstall))
            }
            return .package(InspectorSubject(id: h.id, name: h.name, isCask: h.isCask,
                                             version: "", desc: desc, updates: .notApplicable,
                                             action: .install))
        case .health:
            // **Two lists, not one.** This segment's list holds `brew doctor`'s
            // findings under one heading and `brew config`'s groups under
            // another, so the selection is looked for in both before it is
            // read as nothing. The ids cannot collide: a `DoctorIssue`'s is
            // built from its own text around NUL separators and a
            // `ConfigGroup`'s is `cfg:` and a case name.
            //
            // The same shape as the three above otherwise: a selection neither
            // list holds any more is nothing at all, not a stale finding kept
            // on screen because it was there a moment ago.
            if let issue = issues.first(where: { $0.id == selected }) { return .issue(issue) }
            guard let group = config.first(where: { $0.id == selected }) else {
                return .nothingSelected
            }
            return .configSection(group)
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
    /// The question could not be put: brew is gone, the run timed out, or the
    /// tool printed nothing at all where it always prints something. Not a
    /// clean machine — an unexamined one.
    case refused

    var issues: [DoctorIssue] {
        if case let .examined(issues) = self { return issues }
        return []
    }
}

/// What the health master list puts on screen — **four answers, and the middle
/// two are the whole point.**
///
/// `SearchDisplay.state` is the shape this follows, for the reason that file
/// gives: which sentence stands over which state is the whole of the decision,
/// and a `body` is nowhere a test can reach.
///
/// `.clean` and `.unexaminable` are both an empty screen and they are not the
/// same sentence. One is `brew doctor` having looked and found nothing, which
/// is the only reading that may be drawn as a healthy machine; the other is the
/// question never having been put — brew gone, the run cut off at the deadline,
/// or a tool that printed nothing where it always prints something. Collapsed
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
/// health segment draws a row for. A group with no lines in it is not a group:
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

/// The sentence the health list has instead of findings — named rather than
/// spelled, so the value the tests read carries no language in it.
///
/// Each of the three is `HealthListState`'s own reading of `brew doctor`, and
/// the three stay three for the reason that type spells out: «Nothing to fix»
/// and «Homebrew did not answer» are one empty list and must never be one
/// sentence.
enum HealthNote: String, Equatable { case busy, clean, unexaminable }

/// One row under the Checkup heading: a finding, or the one sentence that
/// stands in for the findings when there are none to draw.
enum HealthRow: Equatable, Identifiable {
    case note(HealthNote)
    case issue(DoctorIssue)
    /// A note is not selectable and the list says so; the id is still distinct,
    /// because a `ForEach` needs one and two rows sharing an id is a row that
    /// redraws as the other.
    var id: String {
        switch self {
        case let .note(note): return "note:" + note.rawValue
        case let .issue(issue): return issue.id
        }
    }
}

/// **What the whole health segment puts on screen — one list with two kinds of
/// thing in it, or one sentence and nothing else.**
///
/// The segment held only `brew doctor`'s findings, so an empty reading was an
/// empty screen and `HelmEmptyState` was the whole of it. It holds `brew
/// config` as well now, and that changes what an empty reading means: a Mac
/// whose findings could not be read still has a configuration to show, and
/// collapsing to the centred sentence would throw away rows that were read
/// successfully. Collapsing the other way would be worse — the sentence saying
/// **why** there are no findings is the one a person decides whether to trust
/// their Mac on, and it has to survive the configuration being there.
///
/// So: the sentence becomes a row under its own heading when there is anything
/// else on the list, and stays the centred empty state when there is not. Both
/// readings are kept in one place a test can reach, for the reason
/// `HealthListState` gives about a `body`.
enum HealthScreen: Equatable {
    /// The whole segment is one sentence: `brew doctor` has nothing to draw and
    /// `brew config` answered nothing either.
    case sentence(HealthNote)
    /// A list. `configuration` empty means that heading is not drawn at all.
    case groups(checkup: [HealthRow], configuration: [ConfigGroup])

    static func of(_ reading: DoctorReading, config: [ConfigGroup]) -> HealthScreen {
        func checkup(_ note: HealthNote) -> HealthScreen {
            config.isEmpty ? .sentence(note)
                           : .groups(checkup: [.note(note)], configuration: config)
        }
        switch HealthListState.of(reading) {
        case .busy: return checkup(.busy)
        case .clean: return checkup(.clean)
        case .unexaminable: return checkup(.unexaminable)
        // Findings are rows whether or not there is a configuration beside
        // them: a list is already the shape, so there is nothing to collapse.
        case let .rows(issues): return .groups(checkup: issues.map(HealthRow.issue),
                                               configuration: config)
        }
    }
}

struct InspectorSubject: Equatable {
    enum Action: Equatable { case uninstall, upgrade, install, pinned }

    /// Four named reasons rather than one optional read three ways:
    /// `loadIfNeeded` never asks `brew outdated`, so `.notAsked` is the
    /// ordinary state on first open and must not be drawn as `.upToDate`.
    enum Updates: Equatable { case notApplicable, notAsked, upToDate, available(String) }

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
/// "build them from the same expressions the behaviour consults" (CLAUDE.md).
enum PackageStanding {
    /// Whether an installed package has an update waiting, without asking
    /// `brew outdated` again: it reads the list the page already holds, and
    /// says "not asked" rather than "up to date" when that list has never
    /// come back.
    static func updates(for id: String, outdated: [OutdatedPackage],
                        loadedOutdated: Bool) -> InspectorSubject.Updates {
        if let op = outdated.first(where: { $0.id == id }) { return .available(op.latest) }
        return loadedOutdated ? .upToDate : .notAsked
    }

    /// The installed version of a search hit, or nil if it is not here.
    static func installedVersion(of id: String, installed: [BrewPackage]) -> String? {
        installed.first(where: { $0.id == id })?.version
    }
}
