import XCTest
@testable import Module_Screenshots_Engine

/// **A shortcut's two names are written once and cannot collide.** The slot is
/// where the host files the binding and where the page asks whether macOS
/// refused it; the prefix is where the combination lives in the module's store.
/// Two shortcuts sharing either would be one shortcut drawn twice, and a prefix
/// that moved would forget somebody's combination without a word.
final class TheShortcutsHaveOneNameEachTests: XCTestCase {

    func testEveryNameIsUniqueAndBelongsToThisModule() {
        let slots = ScreenshotsHotkey.allCases.map(\.slot)
        let prefixes = ScreenshotsHotkey.allCases.map(\.storePrefix)
        XCTAssertEqual(Set(slots).count, ScreenshotsHotkey.allCases.count, "two shortcuts share a slot: \(slots)")
        XCTAssertEqual(Set(prefixes).count, ScreenshotsHotkey.allCases.count, "two shortcuts share a store prefix: \(prefixes)")
        for slot in slots {
            XCTAssertTrue(slot.hasPrefix(ScreenshotsEngine.moduleID + "."), "\(slot) is not under the module's id")
        }
    }

    /// Deployed stored data: the prefixes are pinned as strings, because a
    /// rename is invisible to every other test and loses a person's combination.
    func testThePrefixesAreTheOnesAlreadyOnDisk() {
        XCTAssertEqual(ScreenshotsHotkey.area.storePrefix, "areaHotkey")
        XCTAssertEqual(ScreenshotsHotkey.fullScreen.storePrefix, "fullScreenHotkey")
    }

    /// What ships must be something Carbon can register — inside the bounds the
    /// host enforces — and its label must say what the numbers mean.
    func testTheShippedCombinationsAreRegistrableAndLabelledTruly() {
        for hotkey in ScreenshotsHotkey.allCases {
            let shipped = hotkey.fallback
            XCTAssertTrue((0...0xFF).contains(shipped.keyCode), "\(hotkey): key code \(shipped.keyCode)")
            XCTAssertTrue((1...0xFFFF).contains(shipped.modifiers), "\(hotkey): modifiers \(shipped.modifiers)")
            XCTAssertEqual(shipped.modifiers, CarbonModifier.cmd | CarbonModifier.shift, "\(hotkey)")
        }
        XCTAssertEqual(ScreenshotsHotkey.fullScreen.fallback.label, "⇧⌘1")
        XCTAssertEqual(ScreenshotsHotkey.area.fallback.label, "⇧⌘2")
        XCTAssertEqual(ScreenshotsHotkey.fullScreen.fallback.keyCode, 18, "kVK_ANSI_1")
        XCTAssertEqual(ScreenshotsHotkey.area.fallback.keyCode, 19, "kVK_ANSI_2")
    }

    /// The panel's shortcut is not here until the panel is: a recorder for an
    /// action that is not built is a row drawing a shortcut that does nothing.
    func testThereAreExactlyTheTwoShortcutsThatDoSomething() {
        XCTAssertEqual(Set(ScreenshotsHotkey.allCases.map(\.rawValue)), ["area", "fullScreen"])
    }
}
