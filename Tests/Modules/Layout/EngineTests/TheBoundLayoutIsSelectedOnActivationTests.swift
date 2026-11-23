import XCTest
import HelmRuntime
@testable import Module_Layout_Engine

/// The fixture both classes below build on, so the split into two classes
/// does not copy it. Holds no test.
@MainActor
class LayoutBindingRig: XCTestCase {
    fileprivate var sources = FakeSources()

    /// `FakeSources.installed()` answers `["en", "ru"]` and starts on `en`, so
    /// the bindings below name those.
    fileprivate func engine(bindings: [String: String], appRules: [String: Bool] = [:]) -> LayoutEngine {
        sources = FakeSources()
        let store = layoutStore()
        store.set(bindings, for: LayoutKey.appLayouts)
        if !appRules.isEmpty { store.set(appRules, for: LayoutKey.appRules) }
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: sources,
            translation: FakeTranslation(table: [:]),
            spell: FakeSpell(valid: []), secure: FakeSecure(), activation: AppActivation(),
            settings: store)
        engine.activate()
        return engine
    }

    override func tearDown() {
        FrontmostApp.shared.setForTesting("")
        super.tearDown()
    }
}

/// **The binding, acted on.** `FakeSources` records what it was asked to
/// select, so these assertions are about what the engine decided and not about
/// TIS.
@MainActor
final class TheBoundLayoutIsSelectedOnActivationTests: LayoutBindingRig {
    /// A deactivated engine has stopped watching. Without this the watcher
    /// outlives the module being switched off, and every activation selects a
    /// layout for a module that is not running.
    func testADeactivatedEngineStopsWatching() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "ru"])
        engine.deactivate()
        FrontmostApp.shared.setForTesting("ru.keepcoder.Telegram")
        XCTAssertTrue(sources.selected.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// Two `activate()`s in a row, with no `deactivate()` between: the second
    /// must drop the first registration rather than orphan it in
    /// `FrontmostApp.shared`'s watcher dictionary. Proved through
    /// `deactivate()`: a fixed engine holds one token, and that one call
    /// stops it — an orphaned first token would still be registered and
    /// would go on selecting for a module the page shows as off.
    func testActivatingTwiceLeavesNoOrphanedWatcherBehind() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "ru"])
        engine.activate()
        engine.deactivate()
        FrontmostApp.shared.setForTesting("ru.keepcoder.Telegram")
        XCTAssertTrue(sources.selected.isEmpty)
        withExtendedLifetime(engine) {}
    }
}
