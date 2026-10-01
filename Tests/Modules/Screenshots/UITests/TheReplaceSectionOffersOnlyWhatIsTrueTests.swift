import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Use ⇧⌘3 and ⇧⌘4» is offered when both boxes are read as off, and only
/// then.** Registering a combination macOS still holds answers success and does
/// nothing; a box that is unknown is not known to be off. The button is the one
/// place this page could make a person believe a shortcut works.
@MainActor
final class TheReplaceSectionOffersOnlyWhatIsTrueTests: XCTestCase {

    private func readings(save: BoxState, area: BoxState) -> [SystemBoxReading] {
        SystemShortcuts.boxes(from: .absent).map { reading in
            switch reading.box {
            case .saveScreen: SystemBoxReading(box: reading.box, state: save, keyCode: 20, modifiers: 768)
            case .saveArea: SystemBoxReading(box: reading.box, state: area, keyCode: 21, modifiers: 768)
            default: reading
            }
        }
    }

    func testItIsOfferedWhenBothAreOff() {
        XCTAssertTrue(ScreenshotsSettingsPage.offersToUseSystemKeys(readings(save: .off, area: .off)))
    }

    func testItIsNeverOfferedWhileEitherIsOnOrUnknown() {
        for (save, area) in [(BoxState.on, BoxState.off), (.off, .on), (.on, .on),
                             (.unknown, .off), (.off, .unknown), (.unknown, .unknown)] {
            XCTAssertFalse(ScreenshotsSettingsPage.offersToUseSystemKeys(readings(save: save, area: area)),
                           "offered with save \(save) and area \(area)")
        }
    }

    func testItIsNeverOfferedBeforeAnyReading() {
        XCTAssertFalse(ScreenshotsSettingsPage.offersToUseSystemKeys([]), "offered before macOS was asked")
        XCTAssertFalse(ScreenshotsSettingsPage.offersToUseSystemKeys(ScreenshotsState.unread.boxes))
    }

    func testEachStateHasItsOwnWords() {
        XCTAssertEqual(Set([BoxState.on, .off, .unknown].map(ScreenshotsSettingsPage.say)).count, 3)
    }

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    /// Which combination a hotkey holds is asked of the store in three different
    /// ways: never recorded (the default it ships with), recorded, and cleared.
    /// The conflict note is judged on it, so a cleared shortcut must not be
    /// reported as holding the default.
    func testWhichCombinationAHotkeyHoldsNow() {
        let shipped = ScreenshotsSettingsPage.combination(of: .area, in: store())
        XCTAssertEqual(shipped?.keyCode, ScreenshotsHotkey.area.fallback.keyCode)
        XCTAssertEqual(shipped?.modifiers, ScreenshotsHotkey.area.fallback.modifiers)

        let recorded = ScreenshotsSettingsPage.combination(
            of: .area, in: store(["areaHotkeyKeyCode": 21, "areaHotkeyModifiers": 768]))
        XCTAssertEqual(recorded?.keyCode, 21)
        XCTAssertEqual(recorded?.modifiers, 768)

        let cleared = ScreenshotsSettingsPage.combination(
            of: .area, in: store(["areaHotkeyKeyCode": -1, "areaHotkeyModifiers": 0]))
        XCTAssertNil(cleared, "a shortcut the person cleared was judged as the default")
    }

    /// A recorded ⌘⇧4 conflicts with the box macOS still ticks; the shipped
    /// default does not.
    func testTheShippedDefaultsConflictWithNoBoxAndACommandShiftFourDoes() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        for hotkey in ScreenshotsHotkey.allCases {
            let shipped = hotkey.fallback
            XCTAssertEqual(SystemShortcuts.holding(keyCode: shipped.keyCode, modifiers: shipped.modifiers, in: boxes), [],
                           "\(hotkey) ships on a combination macOS holds")
        }
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 21, modifiers: CarbonModifier.cmd | CarbonModifier.shift, in: boxes),
                       [.saveArea])
    }

    /// A box that is on is warned about only when a combination Helm holds is
    /// the one it holds: on a fresh install (Helm on ⇧⌘1 and ⇧⌘2) both boxes
    /// read on and nothing collides, so nothing is in warning ink.
    func testABoxIsInWarningInkOnlyAgainstAShortcutItActuallyHolds() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        let mine = ScreenshotsHotkey.allCases.map { (keyCode: $0.fallback.keyCode, modifiers: $0.fallback.modifiers) }
        XCTAssertEqual(boxes.filter { $0.state == .on }.count, SystemBox.allCases.count,
                       "the control needs every box on, as on an untouched Mac")
        for reading in boxes {
            XCTAssertFalse(ScreenshotsSettingsPage.conflicts(reading, with: mine),
                           "\(reading.box) is on in macOS and collides with nothing Helm holds, yet is drawn as a warning")
        }
        let taken = [(keyCode: 21, modifiers: CarbonModifier.cmd | CarbonModifier.shift)]
        let hit = boxes.filter { ScreenshotsSettingsPage.conflicts($0, with: taken) }.map(\.box)
        XCTAssertEqual(hit, [.saveArea], "a recorded ⇧⌘4 is the conflict the ink is for")
        var off = boxes
        off = off.map { SystemBoxReading(box: $0.box, state: .off, keyCode: $0.keyCode, modifiers: $0.modifiers) }
        XCTAssertTrue(off.allSatisfy { !ScreenshotsSettingsPage.conflicts($0, with: taken) },
                      "a box that is off holds nothing")
    }

    /// One combination is written in one order on the page: the recorder's, which
    /// is macOS's (⇧ before ⌘). A heading that said ⌘⇧3 above a row that said ⇧⌘3
    /// was one shortcut in two spellings.
    func testTheHeadingAndTheButtonSpellTheCombinationsAsTheRecorderDoes() throws {
        let three = try XCTUnwrap(HotkeyCombination(keyCode: 20, modifiers: CarbonModifier.cmd | CarbonModifier.shift)).label
        let four = try XCTUnwrap(HotkeyCombination(keyCode: 21, modifiers: CarbonModifier.cmd | CarbonModifier.shift)).label
        XCTAssertEqual([three, four], ["⇧⌘3", "⇧⌘4"])
        AppLanguage.each { language in
            for text in [ScStr.replaceTitle, ScStr.useSystemKeys] {
                XCTAssertTrue(text.contains(three) && text.contains(four), "\(language): «\(text)»")
                XCTAssertFalse(text.contains("⌘⇧"), "\(language): «\(text)» spells the combination the other way round")
            }
        }
    }

    /// The page's two writes are spelled by `HotkeyCombination.label`, not by
    /// hand, and the defaults Helm ships are spelled the same way: one spelling
    /// for one pair, from one place.
    func testTheSystemKeysAndTheShippedDefaultsAreSpelledByTheRowsOwnSpelling() throws {
        let page = [ScreenshotsSettingsPage.systemScreenKey, ScreenshotsSettingsPage.systemAreaKey]
        XCTAssertEqual(page.map(\.label), ["⇧⌘3", "⇧⌘4"])
        for pair in page {
            XCTAssertEqual(pair.label, HotkeyCombination(keyCode: pair.keyCode, modifiers: pair.modifiers)?.label)
        }
        for hotkey in ScreenshotsHotkey.allCases {
            let shipped = hotkey.fallback
            XCTAssertEqual(shipped.label, HotkeyCombination(keyCode: shipped.keyCode, modifiers: shipped.modifiers)?.label,
                           "\(hotkey): the default's label is not the one its row would draw")
        }
    }
}
