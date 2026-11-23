import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

private func concurrentEngine(_ settings: NamespacedStore,
                             tap: FakeTap,
                             typing: FakeTyping) -> LayoutEngine {
    LayoutEngine(tap: tap, typing: typing, sources: FakeSources(follows: false),
                 translation: FakeTranslation(sameLength: true), spell: FakeSpell(cyrillic: true),
                 secure: FakeSecure(), activation: FakeActivation(), settings: settings)
}

/// The tap delivers on a run-loop source and the settings re-read runs on the
/// engine's serial queue, and both touch the same fields behind one `NSLock`.
final class LayoutEngineConcurrencyTests: XCTestCase {
    /// Two starts would build two taps and leave the first one enabled on the
    /// run loop, doubling every keystroke. The claim in the source is that the
    /// start is claimed inside the lock rather than merely checked.
    func testStartingTwiceBuildsOneTap() {
        let tap = FakeTap()
        let store = layoutStore()
        let engine = concurrentEngine(store, tap: tap, typing: FakeTyping())
        engine.activate()
        engine.activate()
        engine.activate()
        XCTAssertEqual(tap.starts, 1)
    }

    /// …and after it has been switched off, starting it again builds exactly
    /// one more. An engine that could not be restarted would be a tap that
    /// stays dead until relaunch.
    func testItStartsAgainAfterBeingSwitchedOff() {
        let tap = FakeTap()
        let store = layoutStore()
        let engine = concurrentEngine(store, tap: tap, typing: FakeTyping())
        engine.activate()
        engine.deactivate()
        engine.activate()
        XCTAssertEqual(tap.starts, 2)
    }

    /// The storm, then a question with one right answer.
    ///
    /// Reloads arrive on the engine's serial queue while keys arrive on the tap's
    /// thread. Nothing here asserts on what happened *during* the storm — a
    /// race can satisfy any such claim by luck. What is asserted is the state
    /// afterwards: every task has finished, and the engine must be reporting
    /// the key that is in the store. A field left torn, a lock left held or a
    /// reload that lost to a concurrent read shows up here as a wrong answer or
    /// as a test that never returns.
    ///
    /// The store is written only while no task is running: `InMemoryKeyValueStore`
    /// is a bare dictionary, and racing the fixture would drown the signal it
    /// is here to carry.
    func testTheEngineSettlesOnTheStoredKeyAfterConcurrentTraffic() async throws {
        let tap = FakeTap()
        let typing = FakeTyping()
        let store = layoutStore()
        let engine = concurrentEngine(store, tap: tap, typing: typing)
        let codes: [Int64] = TapKey.allCases.compactMap(\.keyCode)

        for key in [TapKey.globe, .leftControl, .off, .rightCommand] {
            store.set(key.rawValue, for: LayoutKey.tapKey)
            engine.activate()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        await rereadSettings(engine)
                    }
                    group.addTask {
                        // The tap's own stream: presses and releases of every
                        // key that might be bound, plus ordinary typing.
                        for code in codes {
                            tap.modifiers?(.down(code, at: 0, othersHeld: false))
                            tap.modifiers?(.up(code, at: 0.05))
                        }
                        tap.handler?(.character("g"))
                        tap.handler?(.navigation)
                    }
                }
            }
            XCTAssertEqual(engine.boundTapKey, key,
                           "the engine did not settle on the key the store holds")
        }
        XCTAssertEqual(tap.starts, 1, "the storm built a second tap")
        // The storm contains real taps of the bound key, so conversions are
        // expected. What is not expected is a *shape* of plan the logic cannot
        // produce: a plan that deletes nothing types the replacement on top of
        // what is already there.
        for plan in typing.performed {
            XCTAssertGreaterThan(plan.backspaces, 0, "a plan that deletes nothing")
            XCTAssertFalse(plan.insert.isEmpty, "a plan that types nothing")
        }
    }
}

/// The thread-sanitiser run of the storm in `LayoutEngineConcurrencyTests`,
/// which only reports.
final class LayoutEngineUnderTheSanitiserTests: XCTestCase {
    /// The same storm, longer, for a thread sanitiser to look at.
    ///
    /// `handleModifier` reads `tapKey` without taking the lock — the log line
    /// for a refused gesture compares the event's key code against
    /// `tapKey.key.keyCode` outside the guarded section — while
    /// `reloadSettings` assigns the whole struct under it. `ModifierTap` is
    /// several words wide, so this is an unsynchronised read of a value being
    /// written. Nothing deterministic can catch it, which is why this reports
    /// rather than gates:
    ///
    ///     HELM_BENCH=1 swift test --sanitize=thread \
    ///         --filter testConcurrentSettingsAndTapsUnderTheSanitiser
    func testConcurrentSettingsAndTapsUnderTheSanitiser() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let tap = FakeTap()
        let store = layoutStore()
        let engine = concurrentEngine(store, tap: tap, typing: FakeTyping())
        engine.activate()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5_000 {
                group.addTask {
                    await rereadSettings(engine)
                }
                group.addTask {
                    tap.modifiers?(.down(TapKey.globe.keyCode!, at: 0, othersHeld: false))
                    tap.modifiers?(.up(TapKey.globe.keyCode!, at: 0.05))
                }
            }
        }
        XCTAssertEqual(tap.starts, 1)
    }
}
