import XCTest
@testable import HelmUI

/// The sidebar's arrangement, as a value the person owns.
///
/// Two rules everything else follows from, and both are here rather than in a
/// comment: every registry module appears exactly once, and a default name is
/// not a name.
final class SidebarLayoutTests: XCTestCase {

    private func layout(_ sections: [(String, [String])]) -> SidebarLayout {
        SidebarLayout(sections: sections.map {
            SidebarLayout.Section(id: $0.0, seed: nil, name: $0.0, modules: $0.1)
        })
    }

    // MARK: - Seeding

    /// The default is one section per category that has modules, in the order
    /// `ModuleCategory.allCases` declares — the arrangement somebody sees before
    /// they touch anything.
    func testTheDefaultSeedsFromCategories() {
        let made = SidebarLayout.seeded(from: [
            ("keep-awake", .power), ("vpn", .network),
            ("disk", .files), ("duplicates", .files),
        ])
        XCTAssertEqual(made.sections.map(\.seed), ["power", "network", "files"])
        XCTAssertEqual(made.sections.last?.modules, ["disk", "duplicates"])
    }

    /// A category with no modules produces no section. An empty heading is a
    /// promise of something that is not there.
    func testCategoriesWithoutModulesProduceNoSection() {
        XCTAssertEqual(SidebarLayout.seeded(from: [("vpn", .network)]).sections.count, 1)
    }

    /// A seeded section has no name of its own — the title is translated from
    /// the seed, so switching the app's language moves the heading with it.
    func testASeededSectionCarriesNoLiteralName() {
        let made = SidebarLayout.seeded(from: [("vpn", .network)])
        XCTAssertNil(made.sections.first?.name)
        XCTAssertEqual(made.sections.first?.seed, "network")
    }

    /// Two sections may not share an id — a drag targets one by id, and a
    /// collision would move a module into whichever came first.
    func testSectionIdsAreUnique() {
        let made = SidebarLayout.seeded(from: [
            ("keep-awake", .power), ("vpn", .network), ("disk", .files),
        ])
        XCTAssertEqual(Set(made.sections.map(\.id)).count, made.sections.count)
    }

    // MARK: - Names

    /// Renaming sets the literal. Clearing it goes back to the translated seed
    /// rather than to the string that happened to be on screen.
    func testRenamingSetsALiteralAndClearingRestoresTheSeed() {
        var made = SidebarLayout.seeded(from: [("vpn", .network)])
        let id = made.sections[0].id
        made = made.renaming(id, to: "Работа")
        XCTAssertEqual(made.sections[0].name, "Работа")
        made = made.renaming(id, to: nil)
        XCTAssertNil(made.sections[0].name)
        XCTAssertEqual(made.sections[0].seed, "network")
    }

    /// Whitespace is somebody clearing the field, not naming a section " ".
    func testABlankNameClearsRatherThanNames() {
        var made = SidebarLayout.seeded(from: [("vpn", .network)])
        made = made.renaming(made.sections[0].id, to: "   ")
        XCTAssertNil(made.sections[0].name)
    }

    /// A section the person made has a name and no seed: there is nothing to
    /// translate it back to.
    func testAnAddedSectionHasNoSeed() {
        var made = SidebarLayout.seeded(from: [("vpn", .network)])
        made = made.addingSection(named: "Моё")
        XCTAssertNil(made.sections.last?.seed)
        XCTAssertEqual(made.sections.last?.name, "Моё")
        XCTAssertTrue(made.sections.last?.modules.isEmpty ?? false)
    }

    // MARK: - The invariant

    /// A module this build no longer ships leaves the layout rather than
    /// drawing a row that opens nothing.
    func testUnknownModulesAreDropped() {
        let fixed = layout([("a", ["disk", "ghost"])]).reconciled(with: [("disk", .files)])
        XCTAssertEqual(fixed.sections.flatMap(\.modules), ["disk"])
    }

    /// A module the registry has and the layout does not — the case every
    /// future version creates — lands in the section seeded from its category,
    /// and that section is recreated if the person removed it.
    func testNewModulesLandInTheirSeedSection() {
        let stored = SidebarLayout(sections: [
            .init(id: "user.1", seed: nil, name: "Моё", modules: ["disk"]),
        ])
        let fixed = stored.reconciled(with: [("disk", .files), ("vpn", .network)])
        XCTAssertEqual(fixed.sections.count, 2)
        XCTAssertEqual(fixed.sections.last?.seed, "network")
        XCTAssertEqual(fixed.sections.last?.modules, ["vpn"])
        XCTAssertEqual(fixed.sections.first?.modules, ["disk"],
                       "a module the person placed stays where they put it")
    }

    /// One module in two sections is a corrupt store — reachable from a
    /// half-written save or a hand-edited file. The first placement wins, and
    /// the row does not appear twice.
    func testAModuleHeldTwiceKeepsItsFirstPlace() {
        let fixed = layout([("a", ["disk", "vpn"]), ("b", ["disk"])])
            .reconciled(with: [("disk", .files), ("vpn", .network)])
        XCTAssertEqual(fixed.sections.map(\.modules), [["disk", "vpn"], []])
    }

    /// Reconciling twice changes nothing the first pass did not. Without this a
    /// layout could drift on every launch.
    func testReconcilingIsIdempotent() {
        let registry: [(String, ModuleCategory)] = [("disk", .files), ("vpn", .network)]
        let once = SidebarLayout(sections: []).reconciled(with: registry)
        XCTAssertEqual(once.reconciled(with: registry), once)
    }

    /// The invariant itself, stated as a test rather than as a comment.
    func testEveryRegistryModuleAppearsExactlyOnce() {
        let registry: [(String, ModuleCategory)] = [
            ("keep-awake", .power), ("vpn", .network), ("disk", .files),
        ]
        let placed = layout([("a", ["disk", "disk"]), ("b", ["ghost"])])
            .reconciled(with: registry).sections.flatMap(\.modules)
        XCTAssertEqual(placed.sorted(), registry.map(\.0).sorted())
        XCTAssertEqual(Set(placed).count, placed.count)
    }

    // MARK: - Moving

    /// The move this whole plan exists for: out of one section and into
    /// another, which grouping by category could not express.
    func testAModuleMovesBetweenSections() {
        let moved = layout([("a", ["disk", "vpn"]), ("b", ["brew"])])
            .moving("vpn", toSection: "b", before: "brew")
        XCTAssertEqual(moved.sections.map(\.modules), [["disk"], ["vpn", "brew"]])
    }

    func testAModuleMovesToTheEndOfASection() {
        let moved = layout([("a", ["disk", "vpn"]), ("b", ["brew"])])
            .moving("disk", toSection: "b", before: nil)
        XCTAssertEqual(moved.sections.map(\.modules), [["vpn"], ["brew", "disk"]])
    }

    /// Reordering inside one section is the same call, and must not leave a
    /// copy of the module it moved past.
    func testMovingWithinASectionReorders() {
        let moved = layout([("a", ["disk", "vpn", "brew"])])
            .moving("brew", toSection: "a", before: "vpn")
        XCTAssertEqual(moved.sections[0].modules, ["disk", "brew", "vpn"])
    }

    /// A section that is not there is a drag that ended nowhere. The layout
    /// comes back whole rather than short one module.
    func testMovingToAMissingSectionChangesNothing() {
        let stored = layout([("a", ["disk"])])
        XCTAssertEqual(stored.moving("disk", toSection: "ghost", before: nil), stored)
    }

    func testSectionsReorder() {
        let stored = layout([("a", []), ("b", []), ("c", [])])
        XCTAssertEqual(stored.movingSection("c", before: "b").sections.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(stored.movingSection("a", before: nil).sections.map(\.id), ["b", "c", "a"])
    }

    // MARK: - Removing

    /// Removing a section must never remove modules. They go to the section
    /// before it, or to the one after when it was first.
    func testRemovingASectionRehomesItsModules() {
        let left = layout([("a", ["disk"]), ("b", ["vpn", "brew"])]).removingSection("b")
        XCTAssertEqual(left.sections.map(\.id), ["a"])
        XCTAssertEqual(left.sections[0].modules, ["disk", "vpn", "brew"])
    }

    func testRemovingTheFirstSectionRehomesForward() {
        let left = layout([("a", ["disk"]), ("b", ["vpn"])]).removingSection("a")
        XCTAssertEqual(left.sections.map(\.id), ["b"])
        XCTAssertEqual(left.sections[0].modules, ["disk", "vpn"])
    }

    /// The last section cannot go: the modules in it would have nowhere to be,
    /// and a sidebar with no sections has no rows.
    func testTheLastSectionIsKept() {
        let stored = layout([("a", ["disk"])])
        XCTAssertEqual(stored.removingSection("a"), stored)
    }

    /// An empty section stays until it is removed by hand. Vanishing on the
    /// last drag would take away the thing somebody just made.
    func testAnEmptySectionSurvives() {
        let stored = layout([("a", ["disk"]), ("b", [])])
        XCTAssertEqual(stored.moving("disk", toSection: "b", before: nil).sections.count, 2)
    }
}
