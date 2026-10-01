import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The page is drawn, in every language and both appearances, and what it says
/// about a missing grant and a held shortcut changes what it draws.** A measure
/// of height is all a render can say without reading glyphs, so each claim is a
/// *difference*: the same page with the state on and with it off, where the
/// first is taller by a note's worth or the claim is not on the screen at all.
@MainActor
final class TheScreenshotsPageDrawsInEveryLanguageTests: XCTestCase {

    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    func testThePageHasSubstanceInEveryLanguageAndAppearance() {
        for language in AppLanguage.allCases {
            for appearance in appearances {
                let mount = ScreenshotsPageRender.mount(language: language, appearance: appearance)
                let height = ScreenshotsPageRender.height(of: mount)
                XCTAssertGreaterThan(height, 400, "\(language) \(appearance.rawValue): the page came out \(height) pt tall")
                XCTAssertLessThan(height, 3000, "\(language) \(appearance.rawValue): \(height)")
                XCTAssertGreaterThan(mount.ink() ?? 0, 0, "\(language) \(appearance.rawValue): nothing was drawn")
            }
        }
    }

    func testADeniedGrantPutsTheNoteOnThePage() {
        for language in AppLanguage.allCases {
            let granted = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(
                language: language, appearance: .aqua, screenRecording: .granted))
            let denied = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(
                language: language, appearance: .aqua, screenRecording: .denied))
            XCTAssertGreaterThan(denied, granted + 30,
                                 "\(language): a withheld grant drew no note — \(denied) against \(granted)")
        }
    }

    func testAShortcutMacOSHoldsGetsANoteAndOneItDoesNotHoldDoesNot() {
        // ⌘⇧4 recorded, with macOS's box for it still on, against the same with the box off.
        let recorded: [String: Any] = ["areaHotkeyKeyCode": 21, "areaHotkeyModifiers": 768,
                                       "areaHotkeyLabel": "⇧⌘4"]
        var boxesOff = ScreenshotsPageRender.untouched
        boxesOff.boxes = SystemShortcuts.boxes(from: .read(["30": ["enabled": false], "28": ["enabled": false]]))
        for language in AppLanguage.allCases {
            let held = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(
                language: language, appearance: .aqua, values: recorded))
            let free = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(
                language: language, appearance: .aqua, state: boxesOff, values: recorded))
            XCTAssertGreaterThan(held, free + 12, "\(language): a held combination was not said — \(held) against \(free)")
        }
    }

    /// The shipped defaults hold no box, so a fresh install's page is not
    /// accusing the person of anything.
    func testTheShippedShortcutsDrawNoConflictNote() {
        var boxesOff = ScreenshotsPageRender.untouched
        boxesOff.boxes = SystemShortcuts.boxes(from: .read(["30": ["enabled": false], "28": ["enabled": false]]))
        let untouched = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(language: .en, appearance: .aqua))
        let off = ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(language: .en, appearance: .aqua, state: boxesOff))
        // With the boxes off the page also offers «Use ⇧⌘3 and ⇧⌘4», which is a button in
        // an existing row and adds no height; a conflict note would.
        XCTAssertEqual(untouched, off, accuracy: 6, "a shipped default drew a note")
    }
}
