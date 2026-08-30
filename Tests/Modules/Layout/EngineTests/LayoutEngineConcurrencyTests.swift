import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

private final class ConcurrentTyping: TypingPort, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [SwitchPlan] = []
    var performed: [SwitchPlan] { lock.lock(); defer { lock.unlock() }; return plans }
    func perform(_ plan: SwitchPlan) -> Bool {
        lock.lock(); plans.append(plan); lock.unlock(); return true
    }
}

private struct ConcurrentContext: SecureContextPort {
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { "com.apple.Notes" }
}

private struct ConcurrentTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        word.isEmpty ? nil : String(repeating: "п", count: word.count)
    }
}

private struct ConcurrentSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class ConcurrentTap: KeyTapPort, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        lock.lock(); starts += 1; lock.unlock()
        handler = onEvent
        modifiers = onModifier
        return true
    }
    func stop() { handler = nil; modifiers = nil }
}

private struct ConcurrentSources: LayoutSourcePort {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

/// The tap delivers on a run-loop source and the transport on a concurrency
/// pool, and both touch the same fields behind one `NSLock`.
final class LayoutEngineConcurrencyTests: XCTestCase {

    private func engine(_ settings: NamespacedStore,
                        tap: ConcurrentTap,
                        typing: ConcurrentTyping) -> LayoutEngine {
        LayoutEngine(tap: tap, typing: typing, sources: ConcurrentSources(),
                     translation: ConcurrentTranslation(), spell: ConcurrentSpell(),
                     secure: ConcurrentContext(), settings: settings)
    }

    /// Two starts would build two taps and leave the first one enabled on the
    /// run loop, doubling every keystroke. The claim in the source is that the
    /// start is claimed inside the lock rather than merely checked.
    func testStartingTwiceBuildsOneTap() {
        let tap = ConcurrentTap()
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        let engine = engine(store, tap: tap, typing: ConcurrentTyping())
        engine.activate()
        engine.activate()
        engine.activate()
        XCTAssertEqual(tap.startCount, 1)
    }

    /// …and after it has been switched off, starting it again builds exactly
    /// one more. An engine that could not be restarted would be a tap that
    /// stays dead until relaunch.
    func testItStartsAgainAfterBeingSwitchedOff() {
        let tap = ConcurrentTap()
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        let engine = engine(store, tap: tap, typing: ConcurrentTyping())
        engine.activate()
        engine.deactivate()
        engine.activate()
        XCTAssertEqual(tap.startCount, 2)
    }

    /// The storm, then a question with one right answer.
    ///
    /// Reloads arrive on the transport's pool while keys arrive on the tap's
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
        let tap = ConcurrentTap()
        let typing = ConcurrentTyping()
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        let engine = engine(store, tap: tap, typing: typing)
        let codes: [Int64] = TapKey.allCases.compactMap(\.keyCode)

        for key in [TapKey.globe, .leftControl, .off, .rightCommand] {
            store.set(key.rawValue, for: LayoutKey.tapKey)
            engine.activate()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        _ = try? await engine.transport.send(
                            EngineCommand(name: "settingsChanged"))
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
        XCTAssertEqual(tap.startCount, 1, "the storm built a second tap")
        // The storm contains real taps of the bound key, so conversions are
        // expected. What is not expected is a *shape* of plan the logic cannot
        // produce: a plan that deletes nothing types the replacement on top of
        // what is already there.
        for plan in typing.performed {
            XCTAssertGreaterThan(plan.backspaces, 0, "a plan that deletes nothing")
            XCTAssertFalse(plan.insert.isEmpty, "a plan that types nothing")
        }
    }

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
        let tap = ConcurrentTap()
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        let engine = engine(store, tap: tap, typing: ConcurrentTyping())
        engine.activate()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5_000 {
                group.addTask {
                    _ = try? await engine.transport.send(EngineCommand(name: "settingsChanged"))
                }
                group.addTask {
                    tap.modifiers?(.down(TapKey.globe.keyCode!, at: 0, othersHeld: false))
                    tap.modifiers?(.up(TapKey.globe.keyCode!, at: 0.05))
                }
            }
        }
        XCTAssertEqual(tap.startCount, 1)
    }
}
