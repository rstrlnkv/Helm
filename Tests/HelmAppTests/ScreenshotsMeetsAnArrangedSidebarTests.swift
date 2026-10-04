import XCTest
import HelmRuntime
import Module_Screenshots_UI
import Module_Homebrew_UI
@testable import HelmApp
@testable import HelmUI

/// Screenshots arriving in a sidebar somebody already rearranged.
///
/// `SidebarLayoutStoreTests` proves the untouched case: a seeded sidebar meets
/// the eleventh module inside Utilities. A person who has used the composer has
/// a sidebar the seed no longer describes — Utilities renamed, moved, emptied or
/// deleted, its modules carried elsewhere — and each of those is a different
/// answer to "where does the new module go". These pin the answers, so a change
/// to `SidebarLayout.reconciled(with:)` that moves the module somewhere else has
/// to say so.
@MainActor
final class ScreenshotsMeetsAnArrangedSidebarTests: XCTestCase {

    private let shot = ScreenshotsDescriptor.id.rawValue
    private let utilities = "seed.utilities"

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
    }

    /// The registry of the build before Screenshots existed.
    private var before: [(String, ModuleCategory)] {
        SidebarLayoutStore.registry().filter { $0.0 != shot }
    }

    /// What the stored sidebar reads as on the first launch of the new build.
    private func arrive(_ arranged: SidebarLayout) -> SidebarLayout {
        let s = store()
        SidebarLayoutStore.write(arranged, to: s)
        XCTAssertFalse(SidebarLayoutStore.read(from: s, registry: before)
            .sections.flatMap(\.modules).contains(shot), "the fixture must predate the module")
        let read = SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry())
        let placed = read.sections.flatMap(\.modules)
        XCTAssertEqual(placed.filter { $0 == shot }.count, 1, "placed exactly once")
        XCTAssertEqual(Set(read.sections.map(\.id)).count, read.sections.count,
                       "section ids must stay unique: a drag targets a section by id")
        return read
    }

    private func section(holding id: String, in layout: SidebarLayout) throws -> SidebarLayout.Section {
        try XCTUnwrap(layout.sections.first { $0.modules.contains(id) })
    }

    /// The other Utilities modules of the shipped registry, read rather than
    /// listed, so a module moving category does not leave this fixture stale.
    private var siblings: [String] {
        before.filter { $0.1 == .utilities }.map(\.0)
    }

    func testTheFixtureHasSiblings() {
        XCTAssertGreaterThan(siblings.count, 1, "the cases below need Utilities to hold more than one module")
    }

    /// Renamed: the seed survives a rename, so the module goes into the section
    /// the person renamed, and the name they typed stays.
    func testARenamedUtilitiesStillReceivesIt() throws {
        let arranged = SidebarLayout.seeded(from: before).renaming(utilities, to: "Tools")
        let read = arrive(arranged)
        let home = try section(holding: shot, in: read)
        XCTAssertEqual(home.id, utilities)
        XCTAssertEqual(home.name, "Tools")
        XCTAssertEqual(home.modules, siblings + [shot], "beside what lives there, last")
        XCTAssertEqual(read.sections.count, arranged.sections.count, "no new section")
    }

    /// Moved to the top: the section is found by seed wherever it sits, and its
    /// position is not disturbed.
    func testAUtilitiesMovedToTheTopReceivesItWhereItIs() throws {
        let seeded = SidebarLayout.seeded(from: before)
        let arranged = seeded.movingSection(utilities, before: seeded.sections.first?.id)
        XCTAssertEqual(arranged.sections.first?.id, utilities)
        let read = arrive(arranged)
        XCTAssertEqual(read.sections.map(\.id), arranged.sections.map(\.id), "order unchanged")
        XCTAssertEqual(read.sections.first?.modules, siblings + [shot])
    }

    /// Some Utilities modules carried into another section: the module joins the
    /// ones still in Utilities, and the ones carried away stay where they were put.
    func testModulesCarriedOutOfUtilitiesStayPut() throws {
        let seeded = SidebarLayout.seeded(from: before)
        let elsewhere = try XCTUnwrap(seeded.sections.first { $0.id != utilities }).id
        let carried = siblings[0]
        let arranged = seeded.moving(carried, toSection: elsewhere, before: nil)
        let read = arrive(arranged)
        XCTAssertEqual(try section(holding: shot, in: read).id, utilities)
        XCTAssertEqual(try section(holding: carried, in: read).id, elsewhere)
        XCTAssertEqual(try section(holding: shot, in: read).modules,
                       Array(siblings.dropFirst()) + [shot])
    }

    /// Every sibling carried out and the empty section kept: the module lands in
    /// the empty Utilities, alone. Its neighbours are wherever the person put them.
    func testAnEmptiedUtilitiesReceivesItAlone() throws {
        var arranged = SidebarLayout.seeded(from: before)
        let elsewhere = try XCTUnwrap(arranged.sections.first { $0.id != utilities }).id
        for id in siblings { arranged = arranged.moving(id, toSection: elsewhere, before: nil) }
        let read = arrive(arranged)
        XCTAssertEqual(try section(holding: shot, in: read).modules, [shot])
        XCTAssertEqual(read.sections.count, arranged.sections.count)
    }

    /// Deleted: the composer rehomes the siblings into the section above, and
    /// the seeded Utilities is gone. The module joins the section that now holds
    /// the Utilities modules, at its end, so it sits beside its siblings and no
    /// section the person removed comes back.
    func testADeletedUtilitiesLetsTheNewModuleJoinTheSectionHoldingItsSiblings() throws {
        let arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        XCTAssertFalse(arranged.sections.contains { $0.seed == "utilities" })
        let siblingHome = try section(holding: siblings[0], in: arranged)
        let read = arrive(arranged)
        let home = try section(holding: shot, in: read)
        XCTAssertEqual(home.id, siblingHome.id, "beside its siblings")
        XCTAssertEqual(home.modules, siblingHome.modules + [shot], "last in that section")
        XCTAssertEqual(read.sections.count, arranged.sections.count, "the removed section stays removed")
        XCTAssertFalse(read.sections.contains { $0.id == utilities })
    }

    /// Deleted and replaced by a hand-made section the person called
    /// "Utilities" and filled with the siblings: the category comes from the
    /// registry and not from the name or the seed, so the hand-made section is
    /// the one holding the most Utilities modules and receives the newcomer. No
    /// second seeded Utilities appears.
    func testAHandMadeSectionHoldingTheSiblingsReceivesIt() throws {
        var arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        arranged = arranged.addingSection(named: "Utilities")
        let handMade = try XCTUnwrap(arranged.sections.last).id
        for id in siblings { arranged = arranged.moving(id, toSection: handMade, before: nil) }
        let read = arrive(arranged)
        let home = try section(holding: shot, in: read)
        XCTAssertEqual(home.id, handMade)
        XCTAssertEqual(home.modules, siblings + [shot])
        XCTAssertEqual(read.sections.count, arranged.sections.count)
    }

    /// A hand-made section merely *named* "Utilities" and holding none of the
    /// category is not a home: the name decides nothing, and with no module of
    /// the category anywhere a seeded section is created at the foot.
    func testAHandMadeSectionHoldingNoneIsNotAHome() throws {
        var arranged = SidebarLayout.seeded(from: before.filter { $0.1 != .utilities })
        arranged = arranged.addingSection(named: "Utilities")
        let handMade = try XCTUnwrap(arranged.sections.last).id
        let read = SidebarLayout(sections: arranged.sections)
            .reconciled(with: SidebarLayoutStore.registry().filter { $0.1 != .utilities || $0.0 == shot })
        let home = try section(holding: shot, in: read)
        XCTAssertNotEqual(home.id, handMade)
        XCTAssertEqual(home.id, utilities)
        XCTAssertEqual(home.modules, [shot])
        XCTAssertEqual(read.sections.last?.id, utilities, "at the foot")
    }

    // MARK: - The rule on a small registry

    private let other: ModuleCategory = ModuleCategory.allCases.first { $0 != .utilities }!

    private func section(_ id: String, _ modules: [String], seed: String? = nil) -> SidebarLayout.Section {
        SidebarLayout.Section(id: id, seed: seed, name: id, modules: modules)
    }

    /// Two sections hold the same number of the category and no section is
    /// seeded for it: the first in layout order takes the newcomer.
    func testATieGoesToTheFirstSectionInOrder() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a"]), section("two", ["b"])])
        let read = layout.reconciled(with: registry)
        XCTAssertEqual(read.sections.map(\.modules), [["a", "new"], ["b"]])
        let swapped = SidebarLayout(sections: [section("two", ["b"]), section("one", ["a"])])
        XCTAssertEqual(swapped.reconciled(with: registry).sections.map(\.modules), [["b", "new"], ["a"]])
    }

    /// The larger holder wins over an earlier smaller one.
    func testTheSectionHoldingMostWinsOverAnEarlierOne() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities),
                                                    ("c", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a"]), section("two", ["b", "c"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["a"], ["b", "c", "new"]])
    }

    /// Modules of other categories do not count, whatever the section is called.
    func testOtherCategoriesDoNotCount() {
        let registry: [(String, ModuleCategory)] = [("x", other), ("y", other), ("a", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["x", "y"]), section("two", ["a"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["x", "y"], ["a", "new"]])
    }

    /// No module of the category exists anywhere else: a fresh seeded section
    /// at the foot holds the newcomer alone.
    func testNoModuleOfTheCategoryAnywhereMakesAFootSection() throws {
        let registry: [(String, ModuleCategory)] = [("x", other), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["x"])])
        let read = layout.reconciled(with: registry)
        XCTAssertEqual(read.sections.count, 2)
        XCTAssertEqual(read.sections.last?.id, utilities)
        XCTAssertEqual(read.sections.last?.seed, "utilities")
        XCTAssertEqual(read.sections.last?.modules, ["new"])
    }

    /// A seeded section is present but empty while another section holds the
    /// category's modules: the seeded section still wins. That is right because
    /// the seed is the person's own mark of where the category lives and they
    /// kept the empty section; guessing a better home from a head count would
    /// move a module out of the section they named for it.
    func testAnEmptySeededSectionStillBeatsAFullerOne() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a", "b"]),
                                              section(utilities, [], seed: "utilities")])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["a", "b"], ["new"]])
    }

    /// The same answer on every read of the same bytes, and after a write.
    func testAHeadCountArrivalIsStableAcrossReadsAndAWrite() throws {
        let arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        let s = store()
        SidebarLayoutStore.write(arranged, to: s)
        let first = SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry())
        XCTAssertEqual(try section(holding: shot, in: first).id,
                       try section(holding: siblings[0], in: first).id)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry()), first)
        SidebarLayoutStore.write(first, to: s)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry()), first)
    }

    // MARK: - Several arrivals in one read

    /// Two newcomers of one category arriving together both join the section
    /// holding their siblings, in registry order — the first one's placement
    /// adds to the winner's count and cannot hand the second a different home.
    func testTwoNewcomersOfOneCategoryJoinTheSiblingsTogether() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities), ("c", .utilities),
                                                    ("n1", .utilities), ("n2", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a"]), section("two", ["b", "c"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules),
                       [["a"], ["b", "c", "n1", "n2"]])
    }

    /// Two newcomers of one category with no sibling anywhere: the first
    /// recreates the seeded section and the second joins it, rather than a
    /// second section with the same id.
    func testTwoHomelessNewcomersShareOneFootSection() {
        let registry: [(String, ModuleCategory)] = [("x", other), ("n1", .utilities), ("n2", .utilities)]
        let read = SidebarLayout(sections: [section("one", ["x"])]).reconciled(with: registry)
        XCTAssertEqual(read.sections.map(\.id), ["one", utilities])
        XCTAssertEqual(read.sections.map(\.modules), [["x"], ["n1", "n2"]])
    }

    /// Two newcomers of different categories in one read each find their own
    /// siblings; neither is counted toward the other's category.
    func testNewcomersOfTwoCategoriesEachJoinTheirOwnSiblings() {
        let registry: [(String, ModuleCategory)] = [("x", other), ("a", .utilities),
                                                    ("nu", .utilities), ("no", other)]
        let layout = SidebarLayout(sections: [section("one", ["x"]), section("two", ["a"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules),
                       [["x", "no"], ["a", "nu"]])
    }

    // MARK: - What a corrupt store must not count

    /// A module held twice counts once, at its first placement: the duplicate
    /// is collapsed before the head count, so a second copy cannot outvote the
    /// section the module actually sits in.
    func testAModuleHeldTwiceCountsOnceInTheHeadCount() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["b"]), section("two", ["a", "b"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["b", "new"], ["a"]])
    }

    /// Ids this build does not ship count for nothing, however many a section holds.
    func testUnknownIdsDoNotCount() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a"]),
                                              section("two", ["ghost1", "ghost2", "b"])])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["a", "new"], ["b"]])
    }

    /// A seeded section holding fewer of the category than another still wins.
    func testASeededSectionBeatsAFullerOneWhenNotEmptyEither() {
        let registry: [(String, ModuleCategory)] = [("a", .utilities), ("b", .utilities),
                                                    ("c", .utilities), ("new", .utilities)]
        let layout = SidebarLayout(sections: [section("one", ["a", "b"]),
                                              section(utilities, ["c"], seed: "utilities")])
        XCTAssertEqual(layout.reconciled(with: registry).sections.map(\.modules), [["a", "b"], ["c", "new"]])
    }

    /// The first read's answer is not persisted by the read, so it has to be the
    /// same answer every launch; and once written, reading it back changes nothing.
    func testAFreshSidebarPlacesScreenshotsDirectlyBeforeHomebrew() throws {
        // A machine with no stored arrangement: the seed is spelled by the registry's order, and the
        // owner decided Screenshots stands directly before Homebrew. The relation is asserted, not the list.
        let brew = HomebrewDescriptor.id.rawValue
        let read = SidebarLayoutStore.read(from: store(), registry: SidebarLayoutStore.registry())
        let home = try section(holding: shot, in: read)
        let shotAt = try XCTUnwrap(home.modules.firstIndex(of: shot))
        let brewAt = try XCTUnwrap(home.modules.firstIndex(of: brew), "Homebrew shares the section")
        XCTAssertEqual(shotAt + 1, brewAt, "Screenshots directly before Homebrew: \(home.modules)")
    }

    func testTheArrivalIsStableAcrossReadsAndAWrite() {
        let arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        let s = store()
        SidebarLayoutStore.write(arranged, to: s)
        let first = SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry())
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry()), first)
        SidebarLayoutStore.write(first, to: s)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: SidebarLayoutStore.registry()), first)
    }
}
