import Foundation

/// What the sidebar looks like, as a value the person owns.
///
/// `ModuleCategory` seeds the first arrangement and then stops deciding
/// anything. Somebody who moves Disk into a section they called «Каждый день»
/// has said something the enum cannot represent, and the enum is not the place
/// to argue with them.
///
/// **Every registry module appears exactly once**, enforced by `reconciled(with:)`
/// on every read rather than on write. The bytes were written by a build that is
/// not necessarily this one: modules arrive and leave between versions, and a
/// layout that loses one makes it unreachable — the sidebar and Settings are the
/// only two places that can switch a module back on, and both draw from here.
///
/// **A default name is not a name.** A seeded section is called «Питание»,
/// «Power» or «電源» depending on the language, translated from its seed through
/// eight `Localizable.strings` tables. Storing the displayed string would freeze
/// whichever language was current the day it was stored — and renaming one
/// section would quietly stop the others following the app. So a section keeps
/// its seed *and* an optional hand-set name, and clearing the name translates
/// again.
public struct SidebarLayout: Equatable, Codable, Sendable {

    public struct Section: Equatable, Codable, Sendable, Identifiable {
        /// Stable across renames, because a drag targets a section by id and a
        /// rename must not move anything.
        public let id: String
        /// The category this was seeded from, or nil for a section somebody
        /// added. Kept after a rename so clearing the name can translate again.
        public var seed: String?
        /// Set only when a person typed one. Nil means "translate the seed".
        public var name: String?
        public var modules: [String]

        public init(id: String, seed: String?, name: String?, modules: [String]) {
            self.id = id
            self.seed = seed
            self.name = name
            self.modules = modules
        }
    }

    public var sections: [Section]

    public init(sections: [Section]) { self.sections = sections }

    // MARK: - Seeding

    /// The arrangement before anybody touches it: one section per category that
    /// has modules, in the order the enum declares them.
    public static func seeded(from modules: [(String, ModuleCategory)]) -> SidebarLayout {
        SidebarLayout(sections: ModuleCategory.allCases.compactMap { category in
            let ids = modules.filter { $0.1 == category }.map(\.0)
            guard !ids.isEmpty else { return nil }
            return Section(id: seedID(category), seed: category.rawValue, name: nil, modules: ids)
        })
    }

    private static func seedID(_ category: ModuleCategory) -> String { "seed.\(category.rawValue)" }

    // MARK: - Names

    public func renaming(_ sectionID: String, to name: String?) -> SidebarLayout {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return self }
        var copy = self
        // Whitespace is somebody clearing the field, not naming a section " ".
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sections[index].name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return copy
    }

    public func addingSection(named name: String) -> SidebarLayout {
        var copy = self
        copy.sections.append(Section(id: "user.\(UUID().uuidString)",
                                     seed: nil, name: name, modules: []))
        return copy
    }

    // MARK: - The invariant

    /// The layout as it must be before anything draws it: every registry module
    /// present exactly once, nothing else present at all.
    public func reconciled(with registry: [(String, ModuleCategory)]) -> SidebarLayout {
        let known = Set(registry.map(\.0))
        var seen = Set<String>()
        var sections = self.sections.map { section -> Section in
            var copy = section
            // `seen.insert(_:).inserted` is what collapses a module held twice —
            // a corrupt store, reachable from a half-written save — to its first
            // placement rather than drawing the row in two places.
            copy.modules = section.modules.filter { known.contains($0) && seen.insert($0).inserted }
            return copy
        }

        for (id, category) in registry where !seen.contains(id) {
            let seed = category.rawValue
            if let index = sections.firstIndex(where: { $0.seed == seed }) {
                sections[index].modules.append(id)
            } else {
                // The person removed the section this belongs to, and a module
                // with nowhere to go is a module they cannot switch on. Put the
                // section back rather than inventing a home for it.
                sections.append(Section(id: "seed.\(seed)", seed: seed, name: nil, modules: [id]))
            }
            seen.insert(id)
        }
        return SidebarLayout(sections: sections)
    }

    // MARK: - What the sidebar lists

    /// The modules of a section that are switched on, in the section's order.
    public func live(in section: Section, enabled: Set<String>) -> [String] {
        section.modules.filter(enabled.contains)
    }

    /// Every module that is switched off, in layout order across the sections.
    ///
    /// **Because the sidebar used to answer this by dropping them.** A module
    /// switched off then had no page anywhere: all four routes to `.module(id)`
    /// refuse it, so the empty state written for exactly that case — symbol,
    /// name, summary and a «Turn on» button — could not be reached in the
    /// shipping app, and the only trace of a module somebody switched off was a
    /// tooltip in the composer. One list at the foot of the sidebar is the door;
    /// this is the list.
    public func off(enabled: Set<String>) -> [String] {
        sections.flatMap(\.modules).filter { !enabled.contains($0) }
    }

    // MARK: - Moving

    /// Moves a module into `section`, before `before`, or to its end.
    ///
    /// Removed from wherever it was first, so a move inside one section is the
    /// same call as a move between two and neither can leave a copy behind.
    public func moving(_ module: String, toSection section: String,
                       before: String?) -> SidebarLayout {
        guard sections.contains(where: { $0.id == section }) else { return self }
        var copy = self
        for index in copy.sections.indices {
            copy.sections[index].modules.removeAll { $0 == module }
        }
        guard let target = copy.sections.firstIndex(where: { $0.id == section }) else { return self }
        if let before, let at = copy.sections[target].modules.firstIndex(of: before) {
            copy.sections[target].modules.insert(module, at: at)
        } else {
            copy.sections[target].modules.append(module)
        }
        return copy
    }

    public func movingSection(_ sectionID: String, before: String?) -> SidebarLayout {
        guard let from = sections.firstIndex(where: { $0.id == sectionID }) else { return self }
        var copy = self
        let section = copy.sections.remove(at: from)
        if let before, let at = copy.sections.firstIndex(where: { $0.id == before }) {
            copy.sections.insert(section, at: at)
        } else {
            copy.sections.append(section)
        }
        return copy
    }

    // MARK: - Removing

    /// Removes a section and rehomes its modules — to the one before it, or to
    /// the one after when it was first. The last section is never removed: its
    /// modules would have nowhere to be, and a sidebar with no sections has no
    /// rows.
    public func removingSection(_ sectionID: String) -> SidebarLayout {
        guard sections.count > 1,
              let index = sections.firstIndex(where: { $0.id == sectionID }) else { return self }
        var copy = self
        let leaving = copy.sections.remove(at: index)
        if index > 0 {
            // The modules were below their new home, so they go after what is
            // already there and the reading order is unchanged.
            copy.sections[index - 1].modules.append(contentsOf: leaving.modules)
        } else {
            // Rehoming forward: they were *above* the section receiving them, so
            // appending would turn the sidebar upside down for the person who
            // arranged it. They go in front.
            copy.sections[0].modules.insert(contentsOf: leaving.modules, at: 0)
        }
        return copy
    }
}
