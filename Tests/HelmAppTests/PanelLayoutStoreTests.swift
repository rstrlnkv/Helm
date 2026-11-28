import XCTest
import HelmRuntime
@testable import HelmApp
@testable import HelmUI

@MainActor
final class PanelLayoutStoreTests: XCTestCase {

    /// **The key is not `panelLayout`.** That one is in
    /// `ObsoleteDefaults.retired`, so a layout stored under it would be deleted
    /// at the next launch and the panel would forget its arrangement every
    /// morning, which looks like no bug while you are looking at it.
    func testTheKeyIsNotOneThatGetsPurgedAtLaunch() {
        let namespaced = "module.app." + PanelLayoutStore.key
        XCTAssertFalse(ObsoleteDefaults.retired.contains(namespaced),
                       "\(namespaced) is purged at every launch")
    }

    func testPreviousPanelJSONSurvivesReadAndExplicitWrite() throws {
        let key = "module.app.panelWidgets"
        let other = ["module.app.appearance": "dark"]
        var original: [String: Any] = other
        original[key] = Data("""
        {"tabs":[{"id":"seed.main","seed":"main","name":"Tools","glyph":"star","widgets":[
          {"widget":"disk","size":"tall"},{"widget":"vpn","size":"compact"}]}],
         "dismissed":["layout"],"hidden":["launchpad"]}
        """.utf8)
        let backing = InMemoryKeyValueStore()
        backing.raw = original
        let store = NamespacedStore(namespace: "app", backing: backing)

        let layout = PanelLayoutStore.read(from: store, offered: ["homebrew", "vpn", "disk", "layout", "launchpad"],
                                           sizes: ["homebrew": .compact])
        XCTAssertEqual(layout, PanelLayout(tabs: [
            .init(id: "seed.main", seed: "main", name: "Tools", widgets: [
                .init(widget: "disk", size: .tall), .init(widget: "vpn", size: .compact),
                .init(widget: "homebrew", size: .wide),
            ], glyph: "star"),
        ], dismissed: ["layout"], hidden: ["launchpad"]))
        XCTAssertEqual(backing.raw as NSDictionary, original as NSDictionary,
                       "reconciling on read must not rewrite the stored panel layout")

        PanelLayoutStore.write(layout.resizing("vpn", to: .wide), to: store)
        var remaining = backing.raw
        let written = try XCTUnwrap(remaining.removeValue(forKey: key) as? Data)
        let expected: NSDictionary = [
            "tabs": [["id": "seed.main", "seed": "main", "name": "Tools", "glyph": "star", "widgets": [
                ["widget": "disk", "size": "tall"], ["widget": "vpn", "size": "wide"],
                ["widget": "homebrew", "size": "wide"],
            ]]],
            "dismissed": ["layout"], "hidden": ["launchpad"],
        ]
        XCTAssertEqual(try JSONSerialization.jsonObject(with: written) as? NSDictionary, expected)
        XCTAssertEqual(remaining as NSDictionary, other as NSDictionary)
    }

    func testInvalidPanelJSONUsesSeedOrderAndSizesWithoutRepairingTheStore() {
        let key = "module.app.panelWidgets"
        let invalid = Data("{".utf8)
        let backing = InMemoryKeyValueStore()
        backing.raw = [key: invalid]
        let store = NamespacedStore(namespace: "app", backing: backing)

        let layout = PanelLayoutStore.read(from: store, offered: ["vpn", "disk", "homebrew"],
                                           sizes: ["vpn": .compact, "disk": .tall])
        XCTAssertEqual(layout.tabs.map(\.id), ["seed.main"])
        XCTAssertEqual(layout.allSlots, [
            .init(widget: "vpn", size: .compact), .init(widget: "disk", size: .tall),
            .init(widget: "homebrew", size: .wide),
        ])
        XCTAssertEqual(backing.raw as NSDictionary, [key: invalid] as NSDictionary)
    }
}
