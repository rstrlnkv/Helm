import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Layout_Engine

/// The engine registers nothing process-wide itself: both «something came to the
/// front» observations live behind `AppActivationPort`, and deactivation is the
/// one call that takes them away.
///
/// Defect class kept (ARCHITECTURE.md § State and lifetime): an observer started in
/// `activate()` that `deactivate()` does not stop. A module switched off would
/// go on rebuilding a key tap whenever Helm came to the front, and selecting a
/// layout for an app it was told to leave alone. The fake carries the port's
/// states only (`observing`, `starts`), so every assertion is about what the
/// engine asked of the port.
@MainActor
final class TheEngineLetsGoOfItsObserversTests: XCTestCase {

    private var tap = FakeTap()
    private var sources = FakeSources()
    private var activation = FakeActivation()

    private func engine(bindings: [String: String] = [:]) -> LayoutEngine {
        tap = FakeTap(); sources = FakeSources(); activation = FakeActivation()
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(bindings, for: LayoutKey.appLayouts)
        return LayoutEngine(tap: tap, typing: FakeTyping(), sources: sources,
                            translation: FakeTranslation(table: [:]),
                            spell: FakeSpell(valid: []), secure: FakeSecure(),
                            activation: activation, settings: store)
    }

    func testActivationWatchesAndDeactivationStopsWatching() {
        let engine = engine()
        XCTAssertFalse(activation.observing, "precondition: a built engine watches nothing yet")
        engine.activate()
        XCTAssertTrue(activation.observing, "activate() did not start the observations")
        XCTAssertEqual(activation.starts, 1)
        engine.deactivate()
        XCTAssertFalse(activation.observing, "deactivate() left an observation running")
    }

    func testAnotherAppComingForwardSelectsItsBoundLayout() {
        let engine = engine(bindings: ["ru.keepcoder.Telegram": "ru"])
        engine.activate()
        activation.comesToTheFront("ru.keepcoder.Telegram")
        XCTAssertEqual(sources.selected, ["ru"],
                       "the app bound to «ru» came to the front and its layout was not selected")
        engine.deactivate()
        activation.comesToTheFront("ru.keepcoder.Telegram")
        XCTAssertEqual(sources.selected, ["ru"], "a deactivated engine selected a layout")
    }
}
