import XCTest
import HelmRuntime
@testable import HelmApp
@testable import HelmUI

/// The store never hands out a layout that breaks the invariant, because the
/// bytes it reads were written by a build that is not necessarily this one.
@MainActor
final class SidebarLayoutStoreTests: XCTestCase {

    /// In memory, not `UserDefaults.standard`: a test that writes a sidebar
    /// arrangement into the real domain rearranges the sidebar of whoever runs
    /// it.
    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
    }

    private let registry: [(String, ModuleCategory)] = [("disk", .files), ("vpn", .network)]

    func testRoundTrips() {
        let s = store()
        let made = SidebarLayout.seeded(from: registry).addingSection(named: "Моё")
        SidebarLayoutStore.write(made, to: s)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: registry), made)
    }

    /// Nothing stored is a fresh install: the seeded arrangement, not an empty
    /// sidebar.
    func testAnEmptyStoreSeeds() {
        let read = SidebarLayoutStore.read(from: store(), registry: registry)
        XCTAssertEqual(read.sections.map(\.seed), ["network", "files"])
    }

    /// Bytes that are not a layout are a corrupt store, and the answer is the
    /// default rather than a crash or an empty sidebar.
    func testGarbageFallsBackToTheDefault() {
        let s = store()
        s.set(Data([0x00, 0x01, 0x02]), for: SidebarLayoutStore.key)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: registry),
                       SidebarLayout.seeded(from: registry))
    }

    /// Somebody who already arranged the flat list keeps that order — inside
    /// the seeded sections. Losing it would be the upgrade rearranging their
    /// sidebar for them.
    func testTheFlatOrderMigrates() {
        let s = store()
        s.set(["duplicates", "disk"], for: "moduleOrder")
        let read = SidebarLayoutStore.read(from: s,
                                           registry: [("disk", .files), ("duplicates", .files)])
        XCTAssertEqual(read.sections.first?.modules, ["duplicates", "disk"])
    }

    /// The migration runs once. After a layout exists, the flat key is history
    /// and must not reorder what the person has since arranged.
    func testTheFlatOrderStopsMatteringOnceALayoutExists() {
        let s = store()
        s.set(["duplicates", "disk"], for: "moduleOrder")
        let reg: [(String, ModuleCategory)] = [("disk", .files), ("duplicates", .files)]
        SidebarLayoutStore.write(SidebarLayout(sections: [
            .init(id: "a", seed: "files", name: nil, modules: ["disk", "duplicates"]),
        ]), to: s)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: reg).sections.first?.modules,
                       ["disk", "duplicates"])
    }

    /// Read reconciles, so a module added since the layout was written is
    /// present the first time it is read rather than after a write.
    func testReadReconciles() {
        let s = store()
        SidebarLayoutStore.write(SidebarLayout.seeded(from: [("vpn", .network)]), to: s)
        let read = SidebarLayoutStore.read(from: s, registry: registry)
        XCTAssertEqual(read.sections.flatMap(\.modules).sorted(), ["disk", "vpn"])
    }

    /// The registry the app actually ships, read through the same helper the
    /// window uses — nine modules, each in exactly one section.
    func testTheRealRegistryPlacesEveryModuleOnce() {
        let read = SidebarLayoutStore.read(from: store(), registry: SidebarLayoutStore.registry())
        let placed = read.sections.flatMap(\.modules)
        XCTAssertEqual(placed.sorted(), ModuleRegistry.all.map(\.idRaw).sorted())
        XCTAssertEqual(Set(placed).count, placed.count)
    }
}
