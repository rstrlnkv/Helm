import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

/// Every field the engine caches has to be right on the launch that follows a
/// setting being changed — not only in the session where it was changed.
///
/// `reloadSettings()` runs in `activate()`, not only on `settingsChanged`, or a
/// launch keeps whatever the initialiser holds. Most fields have a sensible
/// initialiser value and the gap would not show; `tapKey` has no initialiser
/// parameter at all, so the gesture would be bound to nothing on every start,
/// silently, because a key bound to nothing refuses before there is anything to log.
///
/// One test per cached field, and each one is arranged so that the value in the
/// **store** and the value in the **initialiser** disagree. That is the whole
/// method: a test that passes because the initialiser happened to hold the
/// right thing is a test that would have passed while the bug shipped. No
/// `settingsChanged` is sent anywhere in this file — a launch does not send one.
final class LayoutEngineLaunchTests: XCTestCase {
    private var typing = FakeTyping()
    private var context = FakeSecure()
    private var tap = FakeTap()
    private var sources = StuckSources()
    private var sound = FakeSound()

    private func store(_ write: (NamespacedStore) -> Void = { _ in }) -> NamespacedStore {
        let store = layoutStore()
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
                        audible: Bool = false) -> LayoutEngine {
        typing = FakeTyping(); context = FakeSecure()
        tap = FakeTap(); sources = StuckSources(); sound = FakeSound()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: SameLengthTranslation(), spell: CyrillicSpell(latin: ["Hello"]),
                                  secure: context, activation: FakeActivation(), sound: sound,
 fixCapitals: fixCapitals,
                                  rules: rules, exceptions: exceptions,
                                  automatic: automatic,
                                  audible: audible, settings: settings)
        engine.activate()
        return engine
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

    // MARK: - The defaults a fresh install runs on

    /// The documented default beats the initialiser.
    ///
    /// `ConversionTriggers` says Return is off and says why at length:
    /// in a chat Return sends the message and empties the field, so the
    /// backspaces delete nothing, the correction is typed into an empty box and
    /// the newline sends it — the other person gets the mistyped word and then
    /// a second message correcting it.
    ///
    /// Nothing is in the store: this is a fresh install reading its own
    /// defaults on its first launch, which is the one moment a
    /// `settingsChanged` never arrives.
    ///
    /// This used to hand the initialiser Return *on*, so that a pass could not
    /// come from the initialiser happening to agree. There is no initialiser to
    /// hand it to now — `ConversionTriggers` is an enum with no state, because
    /// `reloadSettings` overwrote whatever it was given anyway. The test is the
    /// same claim with the instrument gone.
    func testAFreshInstallRunsOnTheDocumentedDefaults() {
        let engine = engine(settings: store())
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
    /// `settingsChanged` — the launch read is an addition to that path, not a
    /// replacement for it.
    func testAChangeStillArrivesThroughSettingsChanged() async throws {
        let settings = store()
        let engine = engine(settings: settings)
        // Over «Fix as I type» rather than over a trigger switch: the three of
        // those are gone, and the engine reads no key for them any more.
        settings.set(false, for: LayoutKey.automatic)
        await rereadSettings(engine)
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
