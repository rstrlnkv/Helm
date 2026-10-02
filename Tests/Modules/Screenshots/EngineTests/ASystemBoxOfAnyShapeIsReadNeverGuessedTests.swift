import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Shapes of a box entry `TheSystemShortcutsAreReadNotAssumedTests` does not
/// feed.** Its nonsense is numeric — numbers out of range inside a well-formed
/// `parameters` list. A preferences file anything can write also holds entries
/// whose `value` is not a dictionary, whose `parameters` is not a list, whose
/// list holds a boolean or a null, and entries with a combination and no
/// `enabled` at all. None of them may trap, none may be read as "off", and an
/// entry with no `enabled` is not known to be on either.
final class ASystemBoxOfAnyShapeIsReadNeverGuessedTests: XCTestCase {

    private func box(_ entry: Any) -> SystemBoxReading {
        SystemShortcuts.boxes(from: .read(["30": entry])).first { $0.box == .saveArea }!
    }

    func testAMalformedCombinationKeepsTheDefaultAndTheTick() {
        let shapes: [(String, Any)] = [
            ("value is a string", "standard"),
            ("parameters is a string", ["parameters": "65535, 21, 1179648"]),
            ("parameters is a dictionary", ["parameters": ["1": 21]]),
            ("a boolean for the key code", ["parameters": [65535, true, 1_179_648]]),
            ("a null for the modifiers", ["parameters": [65535, 21, NSNull()]]),
            ("a string for the modifiers", ["parameters": [65535, 21, "1179648"]]),
        ]
        for (what, value) in shapes {
            let reading = box(["enabled": true, "value": value])
            XCTAssertEqual(reading.state, .on, "\(what): a ticked box was not read as ticked")
            XCTAssertEqual(reading.keyCode, 21, "\(what): the combination was not macOS's default")
            XCTAssertEqual(reading.modifiers, CarbonModifier.cmd | CarbonModifier.shift, "\(what)")
        }
    }

    /// A combination on file with no tick on file: nobody knows whether macOS
    /// holds it, and the page must not offer the combination as free.
    func testAnEntryWithNoEnabledIsUnknown() {
        let reading = box(["value": ["parameters": [65535, 21, 1_179_648], "type": "standard"]])
        XCTAssertEqual(reading.state, .unknown, "an entry with no tick was read as \(reading.state)")
    }
}
