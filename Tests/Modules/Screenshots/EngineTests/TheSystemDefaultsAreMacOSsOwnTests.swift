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

    /// The page draws all three boxes Helm may take, always; the button asks about the two that give ⇧⌘3 and ⇧⌘4.
    func testTheReplacedBoxesAreTheTwoSaveBoxesAndThePanelsAndOnlyTheTwoGateTheButton() {
        XCTAssertEqual(SystemBox.replaced, [.saveScreen, .saveArea, .panel])
        XCTAssertEqual(SystemBox.capture, [.saveScreen, .saveArea])
    }

    /// Box 184 is read from macOS's table like the others — ⇧⌘5, key code 23 —
    /// and compared above through `allCases`; this names it so a table that
    /// stops carrying it fails here by name and not as an unexplained count.
    func testTheCommandShiftFiveBoxIsInMacOSsTableAsTheSystemSaysItIs() throws {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: table))
        let sections = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])
        let entry = try XCTUnwrap(sections.flatMap { $0["elements"] as? [[String: Any]] ?? [] }
            .first { ($0["sybmolichotkey"] as? Int) == 184 })
        XCTAssertEqual(SystemBox.panel.rawValue, 184)
        XCTAssertEqual(entry["key"] as? Int, 23)
        XCTAssertEqual(entry["modifier"] as? Int, 1_179_648)
        XCTAssertEqual(SystemBox.panel.defaultKey.keyCode, 23)
        XCTAssertEqual(SystemBox.panel.defaultKey.cocoaModifiers, 1_179_648)
        XCTAssertTrue(SystemBox.allCases.contains(.panel), "the box is not read")
    }
}
