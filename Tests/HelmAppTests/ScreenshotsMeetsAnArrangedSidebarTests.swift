import XCTest
import HelmRuntime
import Module_Screenshots_UI
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
    /// the new module has no Utilities to join. `reconciled(with:)` puts a seeded
    /// Utilities back at the foot of the sidebar holding the new module alone —
    /// away from its siblings, in a section the person removed. Pinned so the
    /// choice is visible; the owner's "next to whatever already lives there"
    /// cannot hold here, since what lived there now lives somewhere else.
    func testADeletedUtilitiesComesBackAtTheFootHoldingOnlyTheNewModule() throws {
        let arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        XCTAssertFalse(arranged.sections.contains { $0.seed == "utilities" })
        let siblingHome = try section(holding: siblings[0], in: arranged).id
        let read = arrive(arranged)
        let home = try section(holding: shot, in: read)
        XCTAssertEqual(home.id, utilities)
        XCTAssertNil(home.name, "translated from its seed")
        XCTAssertEqual(home.modules, [shot])
        XCTAssertEqual(read.sections.last?.id, utilities, "appended at the foot")
        XCTAssertEqual(read.sections.count, arranged.sections.count + 1, "one section the person removed is back")
        XCTAssertNotEqual(home.id, siblingHome, "not beside its siblings")
    }

    /// Deleted and replaced by a hand-made section the person called
    /// "Utilities": the hand-made one has no seed, so it is not found, and the
    /// seeded Utilities comes back beside it — two sections that read alike.
    func testAHandMadeUtilitiesIsNotRecognised() throws {
        var arranged = SidebarLayout.seeded(from: before).removingSection(utilities)
        arranged = arranged.addingSection(named: "Utilities")
        let handMade = try XCTUnwrap(arranged.sections.last).id
        for id in siblings { arranged = arranged.moving(id, toSection: handMade, before: nil) }
        let read = arrive(arranged)
        let home = try section(holding: shot, in: read)
        XCTAssertNotEqual(home.id, handMade)
        XCTAssertEqual(home.id, utilities)
        XCTAssertEqual(home.modules, [shot])
    }

    /// The first read's answer is not persisted by the read, so it has to be the
    /// same answer every launch; and once written, reading it back changes nothing.
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
