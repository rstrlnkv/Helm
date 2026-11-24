import XCTest
import HelmRuntime
@testable import HelmApp
@testable import HelmUI

/// The flat `moduleOrder` list from before sections existed: it orders the
/// modules inside the seeded sections, and stops mattering once a layout is
/// stored.
@MainActor
final class SidebarLayoutStoreTests: XCTestCase {

    /// Somebody who already arranged the flat list keeps that order — inside
    /// the seeded sections. Losing it would be the upgrade rearranging their
    /// sidebar for them.
    func testTheFlatOrderMigrates() {
        let s = NamespacedStore.scratch()
        s.set(["duplicates", "disk"], for: "moduleOrder")
        let read = SidebarLayoutStore.read(from: s,
                                           registry: [("disk", .files), ("duplicates", .files)])
        XCTAssertEqual(read.sections.first?.modules, ["duplicates", "disk"])
    }

    /// The migration runs once. After a layout exists, the flat key is history
    /// and must not reorder what the person has since arranged.
    func testTheFlatOrderStopsMatteringOnceALayoutExists() {
        let s = NamespacedStore.scratch()
        s.set(["duplicates", "disk"], for: "moduleOrder")
        let reg: [(String, ModuleCategory)] = [("disk", .files), ("duplicates", .files)]
        SidebarLayoutStore.write(SidebarLayout(sections: [
            .init(id: "a", seed: "files", name: nil, modules: ["disk", "duplicates"]),
        ]), to: s)
        XCTAssertEqual(SidebarLayoutStore.read(from: s, registry: reg).sections.first?.modules,
                       ["disk", "duplicates"])
    }
}
