import Foundation
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
