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

    func testPreviousSidebarJSONSurvivesReadAndExplicitWrite() throws {
        let key = "module.app.sidebarLayout"
        let other: [String: Any] = ["module.app.moduleOrder": ["disk", "duplicates"],
                                    "module.app.appearance": "dark"]
        var original = other
        original[key] = Data("""
        {"sections":[
          {"id":"user.favorites","name":"Favorites","modules":["keepawake"]},
          {"id":"seed.files","seed":"files","name":"File Tools","modules":["duplicates","disk"]}
        ]}
        """.utf8)
        let backing = InMemoryKeyValueStore()
        backing.raw = original
        let store = NamespacedStore(namespace: "app", backing: backing)

        let layout = SidebarLayoutStore.read(from: store, registry: [
            ("uninstaller", .files), ("disk", .files), ("keepawake", .power), ("duplicates", .files),
        ])
        XCTAssertEqual(layout.sections, [
            .init(id: "user.favorites", seed: nil, name: "Favorites", modules: ["keepawake"]),
            .init(id: "seed.files", seed: "files", name: "File Tools", modules: ["duplicates", "disk", "uninstaller"]),
        ])
        XCTAssertEqual(backing.raw as NSDictionary, original as NSDictionary,
                       "reconciling on read must not rewrite the stored sidebar layout")

        SidebarLayoutStore.write(layout.renaming("user.favorites", to: "Pinned"), to: store)
        var remaining = backing.raw
        let written = try XCTUnwrap(remaining.removeValue(forKey: key) as? Data)
        let expected: NSDictionary = ["sections": [
            ["id": "user.favorites", "name": "Pinned", "modules": ["keepawake"]],
            ["id": "seed.files", "seed": "files", "name": "File Tools", "modules": ["duplicates", "disk", "uninstaller"]],
        ]]
        XCTAssertEqual(try JSONSerialization.jsonObject(with: written) as? NSDictionary, expected)
        XCTAssertEqual(remaining as NSDictionary, other as NSDictionary)
    }

    func testInvalidSidebarJSONFallsBackToLegacyOrderWithoutRepairingTheStore() {
        let original: [String: Any] = ["module.app.sidebarLayout": Data("{".utf8),
                                        "module.app.moduleOrder": ["duplicates", "disk"]]
        let backing = InMemoryKeyValueStore()
        backing.raw = original
        let store = NamespacedStore(namespace: "app", backing: backing)

        let layout = SidebarLayoutStore.read(from: store, registry: [
            ("uninstaller", .files), ("disk", .files), ("duplicates", .files),
        ])
        XCTAssertEqual(layout.sections, [
            .init(id: "seed.files", seed: "files", name: nil, modules: ["duplicates", "disk", "uninstaller"]),
        ])
        XCTAssertEqual(backing.raw as NSDictionary, original as NSDictionary)
    }
}
