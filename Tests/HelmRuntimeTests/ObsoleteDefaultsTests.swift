import XCTest
@testable import HelmRuntime

/// Settings outlive the features that wrote them. A key left behind by a
/// removed feature is invisible clutter that later reads as a real setting.
final class ObsoleteDefaultsTests: XCTestCase {
    func testRemovesRetiredKeys() {
        let store = InMemoryKeyValueStore()
        store.set("list", forKey: "module.app.panelLayout")
        store.set(["disk"], forKey: "module.app.moduleOrder")

        ObsoleteDefaults.purge(from: store)

        XCTAssertNil(store.object(forKey: "module.app.panelLayout"))
        XCTAssertNotNil(store.object(forKey: "module.app.moduleOrder"),
                        "a live setting must survive the purge")
    }

    func testPurgingTwiceIsHarmless() {
        let store = InMemoryKeyValueStore()
        ObsoleteDefaults.purge(from: store)
        ObsoleteDefaults.purge(from: store)
        XCTAssertNil(store.object(forKey: "module.app.panelLayout"))
    }

    /// Every retired key is namespaced, so the purge can never reach into
    /// another app's or another module's settings.
    func testEveryRetiredKeyIsNamespaced() {
        for key in ObsoleteDefaults.retired {
            XCTAssertTrue(key.hasPrefix("module."), "\(key) is not namespaced")
        }
    }

    /// The Island module was rolled back, and its settings stayed behind.
    func testIslandKeysAreRetired() {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "module.island.enabled")
        store.set(["a"], forKey: "module.island.shelfBookmarks")
        ObsoleteDefaults.purge(from: store)
        XCTAssertNil(store.object(forKey: "module.island.enabled"))
        XCTAssertNil(store.object(forKey: "module.island.shelfBookmarks"))
    }
}
