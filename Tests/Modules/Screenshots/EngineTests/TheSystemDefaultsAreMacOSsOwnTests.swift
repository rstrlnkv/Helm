import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **A default written down is checked against the file it was copied from.**
/// `SystemBox.defaultKey` holds the combinations macOS ships for five of its
/// screenshot boxes; the Keyboard settings extension carries them in
/// `DefaultShortcutsTable.xml`, and this reads that file on the Mac running the
/// suite. A number remembered from one macOS and never compared is how a
/// "conflict" gets reported for a combination the system moved.
final class TheSystemDefaultsAreMacOSsOwnTests: XCTestCase {

    private let table = "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources/en.lproj/DefaultShortcutsTable.xml"

    func testEveryBoxDefaultMatchesTheSystemsOwnTable() throws {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: table), """
            the system's own default shortcuts table is not at \(table) — a macOS that moved it \
            needs this path read again, and a check that skips is a check that passes
            """)
        let sections = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])
        let elements = sections.flatMap { $0["elements"] as? [[String: Any]] ?? [] }
        var compared = 0
        for box in SystemBox.allCases {
            let entry = try XCTUnwrap(elements.first { ($0["sybmolichotkey"] as? Int) == box.rawValue },
                                      "macOS's table has no entry for box \(box.rawValue)")
            XCTAssertEqual(entry["key"] as? Int, box.defaultKey.keyCode, "key code of box \(box.rawValue)")
            XCTAssertEqual(entry["modifier"] as? Int, box.defaultKey.cocoaModifiers, "modifiers of box \(box.rawValue)")
            compared += 1
        }
        XCTAssertEqual(compared, SystemBox.allCases.count, "not every box was compared")
    }

    func testTheReplacedBoxesAreTheTwoSaveBoxes() {
        XCTAssertEqual(SystemBox.replaced, [.saveScreen, .saveArea])
    }
}
