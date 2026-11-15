import XCTest
@testable import Module_Layout_Engine
import HelmContract
import HelmRuntime
import HelmTestSupport

private final class DefaultsTyping: TypingPort, @unchecked Sendable {
    var performed = 0
    func perform(_ plan: SwitchPlan) -> Bool { performed += 1; return true }
}
private struct DefaultsTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? { "привет" }
}
private final class DefaultsTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool { handler = onEvent; return true }
    func stop() { handler = nil }
}
private final class DefaultsSound: SoundPort, @unchecked Sendable {
    var played = 0
    func playSwitch() { played += 1 }
}

private final class DefaultsSelection: SelectionPort, @unchecked Sendable {
    func selectedTextWithoutClipboard() -> String? { "ghbdtn" }
    func replaceSelection(with text: String) -> Bool { true }
}

/// Before anyone has chosen, each setting reads as it did when the defaults were
/// spelled inline in the engine and the pages. Moving them into one table must
/// not move a value: a changed default silently changes what every new install
/// does, and for the period, where the page opens.
final class AFreshStoreHoldsTheDeployedDefaultsTests: XCTestCase {

    private func store() -> NamespacedStore {
        layoutStore()
    }

    func testTheSettingsDefaultAsTheyAlwaysDid() {
        XCTAssertTrue(LayoutDefault.automatic)
        XCTAssertFalse(LayoutDefault.audible)
        XCTAssertTrue(LayoutDefault.fixCapitals)
        XCTAssertEqual(LayoutDefault.tapKey, .rightCommand)
    }

    /// The engine and every page read through these four, so this is the pin
    /// for each caller: an empty store gives the deployed value, a stored
    /// choice the opposite one.
    func testTheReadsEveryCallerSharesAnswerFromTheStoreOrTheDefault() {
        let empty = store()
        XCTAssertTrue(empty.layoutAutomatic)
        XCTAssertFalse(empty.layoutAudible)
        XCTAssertTrue(empty.layoutFixCapitals)
        XCTAssertEqual(empty.layoutTapKey, .rightCommand)

        let chosen = store()
        chosen.set(false, for: LayoutKey.automatic)
        chosen.set(true, for: LayoutKey.audible)
        chosen.set(false, for: LayoutKey.fixCapitals)
        chosen.set(TapKey.leftControl.rawValue, for: LayoutKey.tapKey)
        XCTAssertFalse(chosen.layoutAutomatic)
        XCTAssertTrue(chosen.layoutAudible)
        XCTAssertFalse(chosen.layoutFixCapitals)
        XCTAssertEqual(chosen.layoutTapKey, .leftControl)
    }

    /// The engine's own read, at launch, for the two the launch tests do not
    /// reach on an empty store: silent conversion and the right Command tap.
    func testTheEngineLaunchesSilentOnTheRightCommandKey() {
        for (audible, expected) in [(nil, 0), (true, 1)] as [(Bool?, Int)] {
            let store = store()
            if let audible { store.set(audible, for: LayoutKey.audible) }
            let tap = DefaultsTap(), sound = DefaultsSound()
            let engine = LayoutEngine(tap: tap, typing: DefaultsTyping(), sources: StuckSources(),
                                      translation: DefaultsTranslation(), spell: CyrillicSpell(),
                                      secure: FakeSecure(), activation: FakeActivation(),
                                      sound: sound, settings: store)
            engine.activate()
            XCTAssertEqual(engine.boundTapKey, .rightCommand)
            for c in "ghbdtn" { tap.handler?(.character(c)) }
            tap.handler?(.space)
            XCTAssertEqual(sound.played, expected, "audible \(String(describing: audible))")
            withExtendedLifetime(engine) {}
        }
    }

    /// «Fix two capitals» is on for a store nobody has written to. The default
    /// lives in `LayoutDefault`; this pins the engine's own read of it, which
    /// a test of the table alone cannot: every other test of the capital fix
    /// writes `true` into the store first.
    func testAFreshStoreCorrectsASlippedCapital() {
        let tap = DefaultsTap(), typing = DefaultsTyping()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: StuckSources(),
                                  translation: DefaultsTranslation(), spell: CyrillicSpell(),
                                  secure: FakeSecure(), activation: FakeActivation(),
                                  sound: DefaultsSound(), settings: store())
        engine.activate()
        for c in "ПРивет" { tap.handler?(.character(c)) }
        tap.handler?(.space)
        XCTAssertEqual(typing.performed, 1, "the capital was left alone on a fresh store")
        withExtendedLifetime(engine) {}
    }

    /// The two doors that are not the typed space — a corrected capital and a
    /// converted selection — announce through the same setting, read under the
    /// lock: each sounds when it is on and stays silent when it is not.
    func testTheCapitalFixAndTheSelectionDoorsHonourTheSoundSetting() {
        for (audible, expected) in [(false, 0), (true, 1)] {
            let store = store()
            store.set(audible, for: LayoutKey.audible)
            let tap = DefaultsTap(), sound = DefaultsSound()
            let engine = LayoutEngine(tap: tap, typing: DefaultsTyping(), sources: StuckSources(),
                                      translation: DefaultsTranslation(), spell: CyrillicSpell(),
                                      secure: FakeSecure(), activation: FakeActivation(),
                                      sound: sound, selection: DefaultsSelection(), settings: store)
            engine.activate()
            for c in "ПРивет" { tap.handler?(.character(c)) }
            tap.handler?(.space)
            XCTAssertEqual(sound.played, expected, "capital fix, audible \(audible)")
            engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")
            XCTAssertEqual(sound.played, expected * 2, "selection, audible \(audible)")
            withExtendedLifetime(engine) {}
        }
    }

    func testAnEmptyStoreReadsTheHeroOnToday() {
        XCTAssertEqual(ConversionPeriod.stored(in: store()), .today)
    }

    func testAnUnknownStoredPeriodReadsAsToday() {
        let store = store()
        store.set("fortnight", for: LayoutKey.heroPeriod)
        XCTAssertEqual(ConversionPeriod.stored(in: store), .today)
    }

    func testAStoredPeriodIsReadBack() {
        let store = store()
        store.set(ConversionPeriod.week.rawValue, for: LayoutKey.heroPeriod)
        XCTAssertEqual(ConversionPeriod.stored(in: store), .week)
    }
}
