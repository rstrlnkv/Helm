import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// **Hostile bytes in the stored rule list are `unreadable`, never a trap.**
///
/// The scanner in `StoredRuleSet` walks the sealed record by hand, and the
/// record is a plist value any process can write. A scanner that recursed, or
/// indexed past the end, would take the whole app down at launch, before the
/// seal is even consulted.
final class TheStoredRuleScannerHoldsOnHostileBytesTests: XCTestCase {

    private let head = #"[{"id":"f","path":"/p","enabled":true,"rules":[],"depth":1"#

    private func assertUnreadable(_ data: Data, _ what: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(StoredRuleSet.read(data), .unreadable, what, file: file, line: line)
    }

    func testTruncatedInputIsUnreadable() {
        assertUnreadable(Data(head.utf8), "cut before the object and the array close")
        assertUnreadable(Data(#"[{"id":"f","pa"#.utf8), "cut inside a key")
    }

    func testAnUnterminatedStringIsUnreadable() {
        assertUnreadable(Data(#"[{"id":"f"#.utf8), "a string that never closes")
    }

    func testALoneBackslashIsUnreadable() {
        assertUnreadable(Data(#"[{"id":"f\"#.utf8), "a backslash at the end")
        assertUnreadable(Data(#"[{"id":"\q"}]"#.utf8), "a backslash before a letter that is no escape")
    }

    func testHundredThousandNestedBracketsAreUnreadable() {
        assertUnreadable(Data(repeating: 0x5B, count: 100_000), "100,000 open brackets")
        let nested = Data(repeating: 0x5B, count: 100_000) + Data(repeating: 0x5D, count: 100_000)
        assertUnreadable(nested, "100,000 balanced brackets")
    }

    func testNulBytesAreUnreadable() {
        assertUnreadable(Data([0, 0, 0, 0]), "only NUL")
        assertUnreadable(Data(head.utf8) + Data([0]) + Data("}]".utf8), "NUL inside the record")
    }

    func testInvalidUTF8IsUnreadable() {
        assertUnreadable(Data(#"[{"id":""#.utf8) + Data([0xFF, 0xFE]) + Data(#"","path":"/p","enabled":true,"rules":[],"depth":1}]"#.utf8),
                         "bytes that are not UTF-8 inside a string")
    }

    // A removed-folder stub is not decoded, so only the scanner judges what sits
    // in its unknown members: each case below reaches a guard nothing else does.
    private func stub(member: Data) -> Data {
        Data(#"[{"id":"f","path":"/p","rules":[],"helmRemovedFolder":true,"x":"#.utf8) + member + Data("}]".utf8)
    }

    func testInvalidUTF8InAMemberNobodyDecodesIsUnreadable() {
        assertUnreadable(stub(member: Data("\"".utf8) + Data([0xFF, 0xFE]) + Data("\"".utf8)),
                         "bytes that are not UTF-8 in a member the scanner only skips")
    }

    func testAControlCharacterInsideAStringIsUnreadable() {
        assertUnreadable(stub(member: Data("\"a".utf8) + Data([0x0A]) + Data("b\"".utf8)),
                         "a raw line feed inside a string")
        XCTAssertNotEqual(StoredRuleSet.read(stub(member: Data(#""a\nb""#.utf8))), .unreadable,
                          "the escaped form is fine")
    }

    func testNestingPastTheBoundIsUnreadableAndBelowItIsRead() {
        func nested(_ n: Int) -> Data { Data(repeating: 0x5B, count: n) + Data(repeating: 0x5D, count: n) }
        XCTAssertNotEqual(StoredRuleSet.read(stub(member: nested(40))), .unreadable, "40 deep is the deployed shape and more")
        assertUnreadable(stub(member: nested(100)), "100 deep, balanced")
        assertUnreadable(stub(member: nested(100_000)), "100,000 deep, balanced")
    }
}
