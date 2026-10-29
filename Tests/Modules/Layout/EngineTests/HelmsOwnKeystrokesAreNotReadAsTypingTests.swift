import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Layout_Engine

/// Keystrokes the engine itself sends while converting are not typing.
///
/// The marker on every synthesised event, dropped in `CGKeyTap.deliver`, is the
/// only defence on every shipping path: each `perform` runs on main (the
/// automatic path in the tap callback, the gesture and the hotkey after
/// `fix()`'s hop back to main), only posts and returns, so the echo reaches the
/// tap after `performing` is reset. It needs a real `CGEvent` through a started
/// tap and has no test. `performing`, set around `typing.perform`, covers only
/// an echo that lands while `perform` is still running; `LoopbackTyping` feeds
/// the echo inside `perform`, a timing the real port does not have, and this
/// file keeps that guard. A tap that missed the marker would hand the engine
/// its own output as a word; the engine would then convert the conversion
/// (layouts swapped again) and type over the person's text a second time.
///
/// Defect class kept: the engine reading its own output. `LoopbackTyping` is a
/// `TypingPort` whose `perform` feeds `plan.insert` back through `FakeTap`
/// exactly once (a second feed-back would loop a broken engine for ever instead
/// of failing it). The spelling fake is layout-aware: «привет» and `ghbdtn` are
/// words only in `ru`, so `привет` read while the keyboard is still on `en`
/// translates to `ghbdtn`, which the fake accepts, and an engine that listens to
/// its own output converts again and `performed` shows two plans.
final class HelmsOwnKeystrokesAreNotReadAsTypingTests: XCTestCase {

    private final class LoopbackTyping: TypingPort, @unchecked Sendable {
        private let lock = NSLock()
        private var plans: [SwitchPlan] = []
        private var fed = false
        var tap: FakeTap?
        var performed: [SwitchPlan] { lock.withLock { plans } }
        func perform(_ plan: SwitchPlan) -> Bool {
            let first = lock.withLock { plans.append(plan); defer { fed = true }; return !fed }
            if first, let tap {
                for character in plan.insert {
                    if character == " " { tap.space() } else { tap.type(String(character)) }
                }
            }
            return true
        }
    }

    private struct LayoutAwareSpell: SpellPort {
        func isWord(_ word: String, sourceID: String) -> Bool? {
            sourceID == "ru" && (word == "привет" || word == "ghbdtn")
        }
    }

    func testAConversionIsNotConvertedAgainByItsOwnKeystrokes() async {
        let tap = FakeTap()
        let typing = LoopbackTyping()
        typing.tap = tap
        let sources = FakeSources()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет", "привет": "ghbdtn"]),
            spell: LayoutAwareSpell(), secure: FakeSecure(), activation: FakeActivation(),
            ledger: LedgerStore(), settings: NamespacedStore(namespace: LayoutEngine.moduleID,
                                                             backing: InMemoryKeyValueStore()))
        engine.activate()

        tap.type("ghbdtn"); tap.space()

        XCTAssertEqual(typing.performed.count, 1,
                       "the engine converted its own output: \(typing.performed)")
        XCTAssertEqual(typing.performed.first?.insert, "привет ",
                       "control: the person's word was converted")
        XCTAssertEqual(sources.selected, ["ru"], "the keyboard was switched more than once")
        var recorded = -1
        for await state in engine.stream() { recorded = state.totals.allTime.words; break }
        XCTAssertEqual(recorded, 1, "the ledger did not count exactly one conversion")
        engine.deactivate()
    }
}
