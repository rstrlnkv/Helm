import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

private final class LaunchTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class LaunchContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

private struct LaunchTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        guard !word.isEmpty else { return nil }
        return String(repeating: "п", count: word.count)
    }
}

private struct LaunchSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class LaunchTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        modifiers = onModifier
        return true
    }
    func stop() { handler = nil; modifiers = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private final class LaunchSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
}

private final class LaunchSound: SoundPort, @unchecked Sendable {
    var played = 0
    func playSwitch() { played += 1 }
}

/// Every field the engine caches has to be right on the launch that follows a
/// setting being changed — not only in the session where it was changed.
///
/// `reloadSettings()` used to run on the transport's `settingsChanged` and
/// nowhere else, so a launch kept whatever the initialiser held. Most fields
/// have a sensible initialiser value and the gap never showed; `tapKey` has no
/// initialiser parameter at all, so the gesture was bound to nothing on every
/// start, silently, because a key bound to nothing refuses before there is
/// anything to log.
///
/// One test per cached field, and each one is arranged so that the value in the
/// **store** and the value in the **initialiser** disagree. That is the whole
/// method: a test that passes because the initialiser happened to hold the
/// right thing is a test that would have passed while the bug shipped. No
/// `settingsChanged` is sent anywhere in this file — a launch does not send one.
final class LayoutEngineLaunchTests: XCTestCase {
    private var typing = LaunchTyping()
    private var context = LaunchContext()
    private var tap = LaunchTap()
    private var sources = LaunchSources()
    private var sound = LaunchSound()

    private func store(_ write: (NamespacedStore) -> Void = { _ in }) -> NamespacedStore {
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        write(store)
        return store
    }

    /// The initialiser arguments here are deliberately the *opposite* of what
    /// each test writes to the store.
    private func engine(settings: NamespacedStore,
                        fixCapitals: Bool = false,
                        rules: [String: Bool] = [:],
                        exceptions: [String] = [],
                        automatic: Bool = true,
                        triggers: ConversionTriggers = .default,
                        audible: Bool = false) -> LayoutEngine {
        typing = LaunchTyping(); context = LaunchContext()
        tap = LaunchTap(); sources = LaunchSources(); sound = LaunchSound()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: LaunchTranslation(), spell: LaunchSpell(),
                                  secure: context, sound: sound,
 fixCapitals: fixCapitals,
                                  rules: rules, exceptions: exceptions,
                                  automatic: automatic, triggers: triggers,
                                  audible: audible, settings: settings)
        engine.activate()
        return engine
    }

    // MARK: - The key the gesture is bound to

    /// The field with no initialiser parameter, which is why it was the one
    /// that broke. A stored key must be in force at launch.
    func testTheStoredTapKeyIsBoundAtLaunch() {
        let engine = engine(settings: store { $0.set(TapKey.globe.rawValue, for: LayoutKey.tapKey) })
        XCTAssertEqual(engine.boundTapKey, .globe)
    }

    /// …and `off` means off, so the reload cannot be faked by a constant.
    func testAKeyTurnedOffStaysOffAtLaunch() {
        let engine = engine(settings: store { $0.set(TapKey.off.rawValue, for: LayoutKey.tapKey) })
        XCTAssertEqual(engine.boundTapKey, .off)
    }

    // MARK: - Every other cached field

    /// Automatic conversion switched off in a previous session stays off.
    func testAutomaticIsReadAtLaunch() {
        let engine = engine(settings: store { $0.set(false, for: LayoutKey.automatic) },
                            automatic: true)
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "the engine converted with automatic off")
        withExtendedLifetime(engine) {}
    }

    func testTheExceptionListIsReadAtLaunch() {
        let engine = engine(settings: store { $0.set(["ghbdtn"], for: LayoutKey.exceptions) },
                            exceptions: [])
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "a word on the exception list was converted")
        withExtendedLifetime(engine) {}
    }

    func testTheAppRulesAreReadAtLaunch() {
        let engine = engine(settings: store { $0.set(["com.apple.Notes": false],
                                                     for: LayoutKey.appRules) },
                            rules: [:])
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "an app the user switched off was converted in")
        withExtendedLifetime(engine) {}
    }

    /// The rules go the other way too: an app blocked by default that the user
    /// allowed has to be allowed on the next launch, or the setting looks like
    /// it did not stick.
    func testAnAllowedTerminalIsAllowedAtLaunch() {
        let engine = engine(settings: store { $0.set(["com.apple.Terminal": true],
                                                     for: LayoutKey.appRules) },
                            rules: [:])
        context.bundle = "com.apple.Terminal"
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "the user allowed this app and it was refused")
        withExtendedLifetime(engine) {}
    }

    func testTheSoundChoiceIsReadAtLaunch() {
        let engine = engine(settings: store { $0.set(true, for: LayoutKey.audible) },
                            audible: false)
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word converted")
        XCTAssertEqual(sound.played, 1, "the sound the user asked for was not played")
        withExtendedLifetime(engine) {}
    }

    func testTheCapitalCorrectionIsReadAtLaunch() {
        let engine = engine(settings: store { $0.set(true, for: LayoutKey.fixCapitals) },
                            fixCapitals: false)
        tap.type("HEllo")
        tap.send(.space)
        XCTAssertEqual(typing.performed.first?.insert, "Hello ",
                       "the held-capital correction was off on a launch that had it on")
        withExtendedLifetime(engine) {}
    }

    // MARK: - The defaults a fresh install runs on

    /// The documented default beats the initialiser.
    ///
    /// `ConversionTriggers.default` says Return is off and says why at length:
    /// in a chat Return sends the message and empties the field, so the
    /// backspaces delete nothing, the correction is typed into an empty box and
    /// the newline sends it — the other person gets the mistyped word and then
    /// a second message correcting it.
    ///
    /// The initialiser is handed Return *on* here so that a pass cannot come
    /// from the initialiser happening to agree. Nothing is in the store: this
    /// is a fresh install reading its own defaults on its first launch, which
    /// is the one moment a `settingsChanged` never arrives.
    func testAFreshInstallRunsOnTheDocumentedDefaults() {
        let engine = engine(settings: store(),
                            triggers: ConversionTriggers(onSpace: true, onReturn: true,
                                                         onPunctuation: true))
        tap.type("ghbdtn")
        tap.send(.newline)
        XCTAssertTrue(typing.performed.isEmpty,
                      "Return converted on a store nobody has written to")

        // …and the two documented as on are on, so the answer is not "switch
        // everything off". Counted as increments, so each stands on its own.
        var seen = typing.performed.count
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, seen + 1, "a space still confirms by default")
        seen = typing.performed.count
        tap.type("ghbdtn")
        tap.send(.punctuation("."))
        XCTAssertEqual(typing.performed.count, seen + 1, "punctuation still confirms by default")
        withExtendedLifetime(engine) {}
    }

    /// A setting written while the engine is running still takes effect through
    /// the transport — the launch read is an addition to that path, not a
    /// replacement for it.
    func testAChangeStillArrivesThroughTheTransport() async throws {
        let settings = store()
        let engine = engine(settings: settings)
        // Over «Fix as I type» rather than over a trigger switch: the three of
        // those are gone, and the engine reads no key for them any more.
        settings.set(false, for: LayoutKey.automatic)
        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "the change did not reach the engine")
    }

    /// Switched off and on again — the module's own toggle — re-reads the
    /// store. Anything changed while it was off has to be in force when it
    /// comes back, for the same reason it has to be in force at launch.
    func testTurningTheModuleOffAndOnAgainRereadsTheStore() {
        let settings = store()
        let engine = engine(settings: settings)
        engine.deactivate()
        settings.set(TapKey.leftControl.rawValue, for: LayoutKey.tapKey)
        settings.set(false, for: LayoutKey.automatic)
        engine.activate()
        XCTAssertEqual(engine.boundTapKey, .leftControl)
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "automatic was switched off while it was off")
    }
}
