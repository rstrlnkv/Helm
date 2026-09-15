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

    static func of(segment: HomebrewViewModel.Segment,
                   selected: String?,
                   installed: [BrewPackage],
                   outdated: [OutdatedPackage],
                   loadedOutdated: Bool,
                   hits: [SearchHit],
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
/// Size is deliberately not here — it is a directory walk belonging to a later
/// phase, and a tile that says it is working something out for a phase that has
/// not landed is a promise this code cannot keep.
enum PackageFacts {
    static func of(_ info: PackageInfo) -> [PackageFact] {
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
        return facts
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
