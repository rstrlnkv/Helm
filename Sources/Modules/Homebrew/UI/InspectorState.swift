import Foundation
import HelmUI
import Module_Homebrew_Engine

/// What the inspector draws, decided without a view.
///
/// **Health has no inspector** (Architecture/Homebrew.md § The Health tab):
/// `.health` answers `.nothingToSelect`, which the page never mounts.
///
/// Like `AvailableSection.of`, a value a test reads without a view, and a
/// function of what the page already has: no query of its own.
enum InspectorState: Equatable {
    /// **There are rows, and none of them is picked:** the invitation.
    case nothingSelected
    /// **There is nothing to pick.** The list beside this is empty — waiting,
    /// answered nothing, or refused — and «Select a package» would invite a
    /// choice nobody can make. One case for all three: the list's sentences
    /// are `ListScreen`'s, and the inspector does not repeat them.
    case nothingToSelect
    case package(InspectorSubject)
    /// `hits` is what the "Available to install" section draws
    /// (`HomebrewViewModel.shownHits`), already without what is on this Mac.
    ///
    /// `shownEmpty` is the page's filtered emptiness once a query is in the
    /// field, nil without a filter. `installed`/`outdated` stay the *full*
    /// lists: a lookup by id is correct off them, since a row the filter hides
    /// loses its selection first (`reconcileVisible`). Only emptiness needs
    /// the filtered count.
    static func of(segment: HomebrewViewModel.Segment,
                   selected: String?,
                   installed: [BrewPackage],
                   outdated: [OutdatedPackage],
                   loadedOutdated: Bool,
                   hits: [SearchHit],
                   descriptions: [String: String],
                   shownEmpty: Bool? = nil) -> InspectorState {
        // **Emptiness is asked before the selection,** of the lists the
        // master draws: a stale `selected` from a list since emptied offers
        // nothing. Health first, whatever it holds.
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
        switch segment {
        case .installed:
            if let p = installed.first(where: { $0.id == selected }) {
                return .package(InspectorSubject(
                    id: p.id, name: p.name, isCask: p.isCask, version: p.version, desc: desc,
                    updates: PackageStanding.updates(for: p.id, outdated: outdated,
                                                     loadedOutdated: loadedOutdated),
                    action: .uninstall))
            }
        case .updates:
            if let p = outdated.first(where: { $0.id == selected }) {
                return .package(InspectorSubject(
                    id: p.id, name: p.name, isCask: p.isCask,
                    version: p.versionStep, desc: desc, updates: .notApplicable,
                    // `brew upgrade` refuses a pinned formula.
                    action: p.pinned ? .pinned : .upgrade))
            }
        case .health:
            return .nothingToSelect // answered above
        }
        // A hit is only ever an install: `hits` holds nothing on this Mac.
        guard let h = hits.first(where: { $0.id == selected }) else { return .nothingSelected }
        return .package(InspectorSubject(id: h.id, name: h.name, isCask: h.isCask,
                                         version: "", desc: desc, updates: .notApplicable,
                                         action: .install))
    }
}

/// What `brew doctor` answered — **and which of the three things it answered**.
///
/// An enum because "found nothing" and "could not be asked" must be told
/// apart (`DoctorParser.parse`), and the page's verdict is that sentence.
enum DoctorReading: Equatable {
    /// Nobody has asked yet: `loadIfNeeded` does not run `brew doctor`, the
    /// slowest query, so this holds until somebody opens the tab.
    case notAsked
    /// `brew doctor` ran and this is what it found — possibly nothing, which is
    /// the one reading that may be drawn as a healthy machine.
    case examined([DoctorIssue])
    /// The question could not be put: brew is gone, the run timed out, the
    /// tool printed nothing at all where it always prints something, or it
    /// exited non-zero with nothing in its answer this build could read
    /// (`HomebrewEngine.doctor` folds them into one empty reply). Not a clean
    /// machine — an unexamined one.
    case refused
}

/// One group of `brew config`'s lines, under one of the three headings this
/// app invented for them.
///
/// **The grouping is presentation and lives here rather than in the engine,**
/// which only says which heading a line belongs under (`ConfigLine.section`).
/// A group with no lines is not drawn.
struct ConfigGroup: Equatable, Identifiable {
    let section: ConfigSection
    let lines: [ConfigLine]
    /// Prefixed, so a group's id can never be read as a package's `BrewKey`
    /// (`f:`/`c:`) nor as a `DoctorIssue`'s, which is built from the finding's
    /// own text around NUL separators.
    var id: String { "cfg:" + section.rawValue }

    /// The groups in `ConfigSection.allCases` order, each keeping brew's own
    /// order inside it. Not a `Dictionary(grouping:)`, whose order changes
    /// between launches.
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
/// Read off the *unfiltered* reading, never off what the search field leaves:
/// a typed word must not make the Mac look clean (`HealthScreen.of`).
///
/// `.clean` and `.unexaminable` are both an empty list of findings and they are
/// not the same sentence: only `.clean` may be drawn as a healthy machine
/// (`DoctorReading.refused` names the reasons). The count rides on `.findings`
/// so a verdict of zero findings cannot be spelled.
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
/// Decided here, once, and not in `HomebrewHealthPage`'s `body`.
///
/// **`noMatches` is about the findings and not about the Mac:** a filter that
/// empties a non-empty list says so under the unfiltered verdict.
struct HealthScreen: Equatable {
    let verdict: HealthVerdict
    /// The findings a needle keeps, in brew's order. Empty for every verdict
    /// but `.findings`, and also for one whose findings the needle hides.
    let findings: [DoctorIssue]
    /// The needle hides every finding there is.
    let noMatches: Bool
    /// The groups a needle keeps — all of them without one. Empty when `brew
    /// config` has answered nothing, and then the card is not drawn.
    let configuration: [ConfigGroup]

    /// The findings a needle keeps, matched on title and body.
    static func matchingIssues(_ needle: String?, _ issues: [DoctorIssue]) -> [DoctorIssue] {
        guard let needle else { return issues }
        return issues.filter { ListFilter.matches(needle, [$0.title, $0.body]) }
    }

    /// The groups a needle keeps — a group's own heading, or any line's key
    /// or value. Whole groups, never a group with some lines missing.
    static func matchingConfigGroups(_ needle: String?, _ groups: [ConfigGroup]) -> [ConfigGroup] {
        guard let needle else { return groups }
        return groups.filter { group in
            ListFilter.matches(needle, [HbStr.configSectionName(group.section)])
                || group.lines.contains { ListFilter.matches(needle, [$0.key, $0.value]) }
        }
    }

    /// `needle` is nil for the ordinary, unfiltered reading.
    static func of(_ reading: DoctorReading, config: [ConfigGroup],
                   needle: String? = nil) -> HealthScreen {
        let configuration = matchingConfigGroups(needle, config)
        let verdict: HealthVerdict
        switch reading {
        case .notAsked: verdict = .checking
        case .refused: verdict = .unexaminable
        case let .examined(issues):
            if !issues.isEmpty {
                let shown = matchingIssues(needle, issues)
                return HealthScreen(verdict: .findings(issues.count), findings: shown,
                                    noMatches: shown.isEmpty, configuration: configuration)
            }
            verdict = .clean
        }
        return HealthScreen(verdict: verdict, findings: [], noMatches: false,
                            configuration: configuration)
    }
}

struct InspectorSubject: Equatable {
    enum Action: Equatable { case uninstall, upgrade, install, pinned }

    /// `loadIfNeeded` never asks `brew outdated`, so `.notAsked` is the
    /// ordinary state on first open and must not be drawn as `.upToDate`.
    /// `pinned` rides on `.available`: a pinned formula still has a newer
    /// version, and only the action changes (`brew upgrade` refuses it).
    enum Updates: Equatable {
        case notApplicable, notAsked, upToDate
        case available(String, pinned: Bool = false)
    }

    /// The `BrewKey` id — the only thing an action may look a package up by.
    /// A name alone collides: `docker` is both a formula and a cask.
    let id: String
    let name: String
    let isCask: Bool
    /// One version installed, "a → b" outdated, "" for a hit (the hits are
    /// already filtered to what is not on this Mac).
    let version: String
    /// nil until the `brew desc` batch answers — never an empty string, which
    /// the view would draw as a blank line that later fills and re-flows.
    let desc: String?
    let updates: Updates
    let action: Action
}

/// One row of the package view's second tier: a label, and a value that was
/// actually read.
struct PackageFact: Equatable {
    let label: String
    let value: String
}

/// What is known about the disk a package occupies: nothing, a walk that is out
/// right now, or a figure.
///
/// **Three states rather than an optional, because the middle one is not an
/// absence.** The figure is a walk of the package's Cellar directory, long
/// enough to be worth saying something about; an `Int?` could not say a walk
/// is under way without claiming one where none was started.
///
/// A refused walk lands on `.notMeasured`: the row is absent either way.
///
/// Never `.measured(0)` from the engine: a missing keg, a directory that would
/// not open and a cask are all nil there (`HomebrewEngine.size`), because a
/// zero in a row says the package occupies nothing.
enum SizeReading: Equatable, Sendable {
    /// Nothing has been walked and nothing is being walked: no row.
    case notMeasured
    /// A walk is in flight **for the package on screen now**: the row is there
    /// and says so.
    case measuring
    /// The walk answered, in bytes.
    case measured(Int)
}

/// Which rows `brew info`'s answer earns — and no others.
///
/// **An absent fact is an absent row.** Installed and not installed are two
/// sets: "Version" over the catalogue's number is not "Installed version" over
/// what is on disk. Inside each set a row is dropped when its fact is nil; a
/// cask records neither a licence nor who asked for it. A placeholder would be
/// worse: a dash reads as "Homebrew had nothing", a zero as a measurement.
///
/// **The size** is a walk that lands later (`SizeReading`), so a separate
/// parameter. It is the one row that may stand for a state, and only while a
/// walk is out for this package; `.notMeasured` earns no row.
enum PackageFacts {
    static func of(_ info: PackageInfo, size: SizeReading) -> [PackageFact] {
        var facts: [PackageFact] = []
        if let installed = info.installedVersion {
            facts.append(PackageFact(label: HbStr.tileInstalledVersion, value: installed))
            if let at = info.installedAt {
                // The app's language, not the system's.
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
        // Last, in both sets: the row that arrives last moves no other row,
        // and the figure swaps into the row that held its place. `Bytes`, in
        // the app's language.
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

extension OutdatedPackage {
    /// "a → b", as the updates list's rows and the inspector both say it.
    var versionStep: String { "\(installed) → \(latest)" }
}

/// What `PackageStanding.matching` needs of a package: its `BrewKey` id and a name.
protocol NamedPackage: Identifiable where ID == String {
    var name: String { get }
}
extension BrewPackage: NamedPackage {}
extension OutdatedPackage: NamedPackage {}

/// The two questions the rows and the inspector both ask, answered once —
/// published sets built once from the same expressions the behaviour consults (Architecture/KeepAwake.md § Vetoes and the notice).
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

    /// `packages`, kept where `needle` matches the name or — once it has
    /// loaded — the description. nil `needle` keeps everything. One function
    /// for the installed list and the outdated one, which are both a list of
    /// named packages by `BrewKey` id.
    static func matching<P: NamedPackage>(_ needle: String?, _ packages: [P],
                                          descriptions: [String: String]) -> [P] {
        guard let needle else { return packages }
        return packages.filter { ListFilter.matches(needle, [$0.name, descriptions[$0.id]]) }
    }
}
