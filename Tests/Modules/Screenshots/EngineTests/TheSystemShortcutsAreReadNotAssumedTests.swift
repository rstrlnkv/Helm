import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Read, never assumed.** macOS shows an entry for a box only once somebody
/// has touched it, so an *absent* entry is a box macOS still holds — on by
/// default — and an *unreadable* reading is unknown. Reading absent as off tells
/// a person ⌘⇧4 is free while it is taken; reading unreadable as free does the
/// same from the other side.
final class TheSystemShortcutsAreReadNotAssumedTests: XCTestCase {

    private func entry(enabled: Any, parameters: [Int]? = nil) -> [String: Any] {
        var out: [String: Any] = ["enabled": enabled]
        if let parameters { out["value"] = ["parameters": parameters, "type": "standard"] }
        return out
    }

    private func reading(_ boxes: [SystemBoxReading], _ box: SystemBox) -> SystemBoxReading {
        boxes.first { $0.box == box }!
    }

    func testAnAbsentEntryIsAnUntouchedBoxAndIsOn() {
        let boxes = SystemShortcuts.boxes(from: .read(["28": entry(enabled: false)]))
        XCTAssertEqual(reading(boxes, .saveArea).state, .on, "an entry nobody touched was read as off")
        XCTAssertEqual(reading(boxes, .saveScreen).state, .off)
    }

    func testADomainWithNoKeyIsEveryBoxOnByDefault() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        XCTAssertEqual(boxes.map(\.state), Array(repeating: .on, count: SystemBox.allCases.count))
        XCTAssertEqual(reading(boxes, .saveScreen).keyCode, 20)
        XCTAssertEqual(reading(boxes, .saveScreen).modifiers, CarbonModifier.cmd | CarbonModifier.shift)
    }

    func testAnUnreadableReadingIsUnknownAndNeverFree() {
        let boxes = SystemShortcuts.boxes(from: .unreadable)
        XCTAssertEqual(Set(boxes.map(\.state)), [.unknown])
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 20, modifiers: CarbonModifier.cmd | CarbonModifier.shift, in: boxes), [],
                       "an unknown box was named as a conflict")
    }

    /// `boxes(from:)` never gives an unknown box a combination, so the reading
    /// above cannot tell whether `holding` asks the state at all. This one can: an
    /// unknown box that *does* carry a combination is still not a conflict, and an
    /// off one is not either.
    func testOnlyABoxKnownToBeOnIsNamedAsHoldingACombination() {
        let key = 20, mask = CarbonModifier.cmd | CarbonModifier.shift
        let readings = [SystemBoxReading(box: .saveScreen, state: .unknown, keyCode: key, modifiers: mask),
                        SystemBoxReading(box: .copyScreen, state: .off, keyCode: key, modifiers: mask),
                        SystemBoxReading(box: .saveArea, state: .on, keyCode: key, modifiers: mask)]
        XCTAssertEqual(SystemShortcuts.holding(keyCode: key, modifiers: mask, in: readings), [.saveArea])
    }

    func testAnEnabledFlagMayBeABooleanOrAnIntegerAndNothingElse() {
        let table: [String: Any] = ["28": entry(enabled: 0), "29": entry(enabled: 1),
                                    "30": entry(enabled: "yes"), "31": entry(enabled: true)]
        let boxes = SystemShortcuts.boxes(from: .read(table))
        XCTAssertEqual(reading(boxes, .saveScreen).state, .off)
        XCTAssertEqual(reading(boxes, .copyScreen).state, .on)
        XCTAssertEqual(reading(boxes, .saveArea).state, .unknown, "a string was taken for an answer")
        XCTAssertEqual(reading(boxes, .copyArea).state, .on)
    }

    func testAnEntryThatIsNotADictionaryIsUnknown() {
        let boxes = SystemShortcuts.boxes(from: .read(["28": 5, "30": ["value": "x"]]))
        XCTAssertEqual(reading(boxes, .saveScreen).state, .unknown)
        XCTAssertEqual(reading(boxes, .saveArea).state, .unknown, "an entry with no `enabled` was read as on")
    }

    /// Moved in System Settings: the combination the box holds is the one in its
    /// parameters, and judging the person against the default calls a taken
    /// combination free.
    func testAMovedShortcutIsJudgedWhereItNowStands() {
        // ⌥⌘9: key 25, Cocoa flags option 0x80000 + command 0x100000.
        let boxes = SystemShortcuts.boxes(from: .read(["30": entry(enabled: true, parameters: [65535, 25, 0x180000])]))
        let moved = reading(boxes, .saveArea)
        XCTAssertEqual(moved.keyCode, 25)
        XCTAssertEqual(moved.modifiers, CarbonModifier.cmd | CarbonModifier.option)
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 25, modifiers: CarbonModifier.cmd | CarbonModifier.option, in: boxes), [.saveArea])
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 21, modifiers: CarbonModifier.cmd | CarbonModifier.shift, in: boxes), [],
                       "the old combination is still reported as held after the box moved")
    }

    func testAnEnabledBoxHoldsItsDefaultCombinationAndADisabledOneHoldsNothing() {
        let table: [String: Any] = ["28": entry(enabled: false)]
        let boxes = SystemShortcuts.boxes(from: .read(table))
        let cmdShift = CarbonModifier.cmd | CarbonModifier.shift
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 20, modifiers: cmdShift, in: boxes), [],
                       "an unticked box was named as a conflict")
        XCTAssertEqual(SystemShortcuts.holding(keyCode: 21, modifiers: cmdShift, in: boxes), [.saveArea])
    }

    func testNonsenseParametersFallBackToTheDefaultAndNeverTrap() {
        let bad: [[Any]] = [[0, Int.max, 0], [0, -1, 0], [0, 20, -5], [0, "x", 0], [0], [0, 1e300, 0]]
        for parameters in bad {
            let table: [String: Any] = ["28": ["enabled": true, "value": ["parameters": parameters]]]
            let boxes = SystemShortcuts.boxes(from: .read(table))
            XCTAssertEqual(reading(boxes, .saveScreen).keyCode, 20, "\(parameters)")
        }
    }

    func testCocoaFlagsBecomeCarbonFlags() {
        XCTAssertEqual(CarbonModifier.fromCocoa(1_179_648), CarbonModifier.cmd | CarbonModifier.shift)
        XCTAssertEqual(CarbonModifier.fromCocoa(1_441_792), CarbonModifier.cmd | CarbonModifier.shift | CarbonModifier.control)
        XCTAssertEqual(CarbonModifier.fromCocoa(0), 0)
    }
}
