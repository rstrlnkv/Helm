import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **`noDictionary` is a snapshot in a state struct whose neighbour is live.**
///
/// `LayoutState.suspended` is recomputed inside every `emitState()`, and the
/// commit that made it so is called «the suspension is a fact, not a snapshot»:
/// a stored reading of something the system owns went stale and the page said
/// the wrong thing until something else happened to emit. `noDictionary` is the
/// same field one line down and still the old shape — `refreshDictionarySupport()`
/// runs exactly once, inside `activate()`, and nothing re-asks:
///
/// ```
/// grep -n refreshDictionarySupport Sources/Modules/Layout/Engine/LayoutEngine.swift
/// 140:        refreshDictionarySupport()
/// 800:    private func refreshDictionarySupport() {
/// ```
///
/// What a person does: Helm is running, they open System Settings ▸ Keyboard and
/// add Georgian — one of the eight scripts `NSSpellChecker` on this Mac has no
/// dictionary for — then come back to Helm and carry on typing. What they get:
/// «Fix as I type» is now dead for every pair that includes Georgian, the switch
/// is on, the badge is green, and the sentence the page owes them is the one
/// `DictionarySupport` exists to say. What they should get: that sentence, which
/// they get today only by quitting Helm and starting it again.
///
/// The installed set is *not* stale for conversion — `target(for:from:)` asks
/// `sources.installed()` on every word — so the module already converts between
/// layouts it has never judged. Two readings of one fact, one live and one from
/// launch.
///
/// **What this pins and what it does not.** It exercises the two ordinary
/// triggers: coming back to Helm (`didBecomeActive`, which the engine already
/// observes for the grant, and which is the same journey — the settings note
/// sends people to System Settings and they come back) and the next conversion,
/// which emits. A repair that re-asks on either satisfies it. A repair that
/// listens only for `kTISNotifyEnabledKeyboardInputSourcesChanged` would not,
/// and that is a conversation rather than a hidden failure.
@MainActor
final class ALayoutAddedAfterLaunchIsJudgedTests: XCTestCase {

    private let en = "com.apple.keylayout.US"
    private let ru = "com.apple.keylayout.Russian"
    private let ka = "com.apple.keylayout.Georgian"

    // MARK: - Ports

    /// **The installed set moves, because on a real Mac it does.** The shared
    /// `FakeSources` answers `["en", "ru"]` from a hard-coded literal, so «the
    /// person added a layout while Helm was running» is a state no test could
    /// write down — the fake is simpler than the port in exactly the way that
    /// makes a whole class of defect unrepresentable.
    private final class MovingSources: LayoutSourcePort, @unchecked Sendable {
        private let lock = NSLock()
        private var all: [String]
        private var live: String
        var selected: [String] = []
        init(current: String, installed: [String]) { live = current; all = installed }
        func installed() -> [String] { lock.lock(); defer { lock.unlock() }; return all }
        func current() -> String? { lock.lock(); defer { lock.unlock() }; return live }
        func select(_ sourceID: String) {
            lock.lock(); selected.append(sourceID); live = sourceID; lock.unlock()
        }
        /// System Settings ▸ Keyboard ▸ Input Sources ▸ +
        func personAdds(_ sourceID: String) {
            lock.lock(); all.append(sourceID); lock.unlock()
        }
    }

    /// Nil is «macOS has no dictionary for this language», which the port's
    /// contract says must never be read as «not a word».
    private struct Spell: SpellPort {
        let valid: Set<String>
        let withoutADictionary: Set<String>
        func isWord(_ word: String, sourceID: String) -> Bool? {
            withoutADictionary.contains(sourceID) ? nil : valid.contains(word)
        }
    }

    private struct Translation: TranslationPort {
        let table: [String: String]
        func translate(_ word: String, from: String, to: String) -> String? { table[word] }
    }

    private func published(by engine: LayoutEngine) async -> LayoutState? {
        for await event in engine.transport.events
        where event.name == LayoutEvent.layoutState.rawValue {
            return try? JSONDecoder().decode(LayoutState.self, from: event.payload)
        }
        return nil
    }

    /// Hands the main queue over, so a `didBecomeActive` observer registered on
    /// `OperationQueue.main` has run before anything is asserted. Twice, because
    /// one reading of a queue is not a measurement of it.
    private func letTheMainQueueRun() async {
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func testTheLayoutAddedWhileHelmWasRunningIsNamedToo() async {
        let sources = MovingSources(current: en, installed: [en, ru])
        let tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: FakeTyping(), sources: sources,
            translation: Translation(table: ["ghbdtn": "привет"]),
            spell: Spell(valid: ["привет"], withoutADictionary: [ka]),
            secure: FakeSecure(),
            ledger: LedgerStore(),
            settings: NamespacedStore(namespace: LayoutEngine.moduleID,
                                      backing: InMemoryKeyValueStore()))
        engine.activate()

        let atLaunch = await published(by: engine)
        XCTAssertEqual(atLaunch?.noDictionary, [], """
            precondition: both layouts installed at launch have a dictionary, so \
            an empty list below would mean nothing — an absence proves nothing \
            when the subject never happened.
            """)

        // System Settings ▸ Keyboard, then back to Helm, then carry on typing.
        sources.personAdds(ka)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification,
                                        object: nil)
        await letTheMainQueueRun()
        tap.type("ghbdtn"); tap.space()

        let now = await published(by: engine)
        XCTAssertEqual(now?.noDictionary, [ka], """
            the page still describes the Mac as it was at launch. A layout macOS \
            has no spelling for was added while Helm was running, «Fix as I type» \
            is now dead for every pair that includes it, and the one sentence the \
            page owes for exactly this is withheld until the app is restarted — \
            while `target(for:from:)` has been reading the new installed set on \
            every keystroke all along.
            """)
        engine.deactivate()
    }
}
