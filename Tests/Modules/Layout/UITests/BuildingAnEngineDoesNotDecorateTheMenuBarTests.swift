import HelmRuntime
import XCTest
@testable import Module_Layout_UI
import Module_Layout_Engine

/// **Building an engine must not put anything in the menu bar.**
///
/// `makeEngine` used to build the module's `LanguageIndicator` and call
/// `refresh()` on it, and `refresh` builds a real `NSStatusItem` the moment it
/// reads `indicator` = true. So every caller of `makeEngine` that happened to
/// hold a store with that setting on decorated the Mac it was running on — the
/// offscreen render harness among them, which is how this was found: seeding
/// Layout's store for a measurement put a second flag in the menu bar of the
/// test run and two `DistributedNotificationCenter` observers behind it, held by
/// a descriptor that lives as long as the process. Writing the key straight into
/// the backing store dodges `.helmStoreChanged` and does not dodge this: no
/// notification is involved.
///
/// The seam is `attachMenuBarPresence()` / `detachMenuBarPresence()` on the
/// descriptor, which the host calls around a module's lifetime. A measurement
/// builds the engine and never attaches, so it may read this Mac without
/// decorating it.
///
/// **No test here switches the indicator on**, and that is deliberate rather
/// than a gap: a test that let `refresh` build the item would be the very defect
/// this file exists about. The setting is off, so `attach` builds the indicator
/// object and the indicator builds no status item — which is enough to see the
/// three states apart.
@MainActor
final class BuildingAnEngineDoesNotDecorateTheMenuBarTests: XCTestCase {

    private func store(indicator: Bool) -> NamespacedStore {
        let store = NamespacedStore(namespace: LayoutDescriptor.id.rawValue,
                                    backing: InMemoryKeyValueStore())
        store.set(indicator, for: LayoutKey.indicator)
        return store
    }

    func testMakingTheEngineLeavesTheMenuBarAloneWithTheIndicatorSwitchedOn() {
        let descriptor = LayoutDescriptor()
        _ = descriptor.makeEngine(store: store(indicator: true))
        XCTAssertNil(descriptor.indicator, """
            `makeEngine` built the module's menu-bar indicator, and with the setting on that \
            is a real `NSStatusItem` in the menu bar of whatever process asked for an engine — \
            a measurement, a seeded render, a test. Building an engine is not the moment a \
            module appears in the menu bar; `attachMenuBarPresence()` is.
            """)
    }

    func testAttachingThePresenceIsWhatBuildsTheIndicator() {
        let descriptor = LayoutDescriptor()
        _ = descriptor.makeEngine(store: store(indicator: false))
        descriptor.attachMenuBarPresence()
        XCTAssertNotNil(descriptor.indicator, """
            nothing was built by `attachMenuBarPresence()`, so the seam the render harness \
            relies on has taken the indicator away from the app as well: with the setting on, \
            nobody would draw it.
            """)
    }

    func testDetachingDropsIt() {
        let descriptor = LayoutDescriptor()
        _ = descriptor.makeEngine(store: store(indicator: false))
        descriptor.attachMenuBarPresence()
        XCTAssertNotNil(descriptor.indicator,
                        "nothing was attached, so this test would prove nothing about detaching")
        descriptor.detachMenuBarPresence()
        XCTAssertNil(descriptor.indicator, """
            the indicator outlived `detachMenuBarPresence()`. Switching the module off left its \
            flag in the menu bar, retained by its own observers, for the life of the process.
            """)
    }
}
