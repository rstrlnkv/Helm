import XCTest
import HelmRuntime
@testable import Module_Layout_Engine

/// **The binding, acted on.** `FakeSources` records what it was asked to
/// select, so these assertions are about what the engine decided and not about
/// TIS.
@MainActor
final class TheBoundLayoutIsSelectedOnActivationTests: XCTestCase {

    private var sources = FakeSources()

    /// `FakeSources.installed()` answers `["en", "ru"]` and starts on `en`, so
    /// the bindings below name those.
    private func engine(bindings: [String: String]) -> LayoutEngine {
        sources = FakeSources()
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(bindings, for: LayoutKey.appLayouts)
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: sources,
            translation: FakeTranslation(table: [:]),
            spell: FakeSpell(valid: []), secure: FakeSecure(),
            settings: store)
        engine.activate()
        return engine
    }

    override func tearDown() {
        FrontmostApp.shared.setForTesting("")
        super.tearDown()
    }

    func testComingForwardSelectsTheBoundLayout() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "ru"])
        FrontmostApp.shared.setForTesting("ru.keepcoder.Telegram")
        XCTAssertEqual(sources.selected, ["ru"])
        withExtendedLifetime(engine) {}
    }

    func testAnUnboundApplicationChangesNothing() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "ru"])
        FrontmostApp.shared.setForTesting("com.apple.Safari")
        XCTAssertTrue(sources.selected.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// **The one that matters most.** `FakeSources` starts on `en`, so a
    /// binding to `en` is already satisfied — and a `TISSelectInputSource` for
    /// the layout you are already on is a system event for nothing.
    func testTheLayoutYouAreAlreadyOnIsNotSelectedAgain() {
        let engine = engine(bindings: ["com.apple.Terminal": "en"])
        FrontmostApp.shared.setForTesting("com.apple.Terminal")
        XCTAssertTrue(sources.selected.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// A layout the person bound and then removed in System Settings.
    func testALayoutThatIsGoneChangesNothing() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "uk"])
        FrontmostApp.shared.setForTesting("ru.keepcoder.Telegram")
        XCTAssertTrue(sources.selected.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// **`AppScope` does not gate this**, and the two are different questions:
    /// «do not rewrite my text here» and «I write English here». The second is
    /// more likely to be wanted in a terminal, not less.
    func testAnAppOnTheLeaveAloneListStillGetsItsLayout() {
        sources = FakeSources()
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(["com.apple.Terminal": "ru"], for: LayoutKey.appLayouts)
        store.set(["com.apple.Terminal": false], for: LayoutKey.appRules)
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: sources,
            translation: FakeTranslation(table: [:]),
            spell: FakeSpell(valid: []), secure: FakeSecure(),
            settings: store)
        engine.activate()
        FrontmostApp.shared.setForTesting("com.apple.Terminal")
        XCTAssertEqual(sources.selected, ["ru"])
        withExtendedLifetime(engine) {}
    }

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
}
