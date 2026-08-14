import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// What a stamp is allowed to be worth.
///
/// The mark says "this rule has had its turn at this file", and a file carrying
/// one is skipped. It sits in an extended attribute on somebody's file, where
/// any process running as the user can write it, and the rule id it used to
/// hold is a UUID out of a plist the same process can read — so writing the
/// right value was a matter of copying it. A file that stamps itself is a file
/// no rule can ever catch.
///
/// So the value is a MAC under the seal key, over the rule *and* the file's
/// identity: unforgeable without the key, and worthless on any other file.
final class StampMarkTests: XCTestCase {

    private let key = Data(repeating: 0x11, count: 32)
    private let other = Data(repeating: 0x22, count: 32)

    func testTheSameRuleOnTheSameFileMarksTheSame() {
        XCTAssertEqual(StampMark.of(rule: "r", device: 1, inode: 2, key: key),
                       StampMark.of(rule: "r", device: 1, inode: 2, key: key))
    }

    /// Per rule, not per file: two rules each get their turn.
    func testAnotherRuleGetsAnotherMark() {
        XCTAssertNotEqual(StampMark.of(rule: "r", device: 1, inode: 2, key: key),
                          StampMark.of(rule: "s", device: 1, inode: 2, key: key))
    }

    /// The property that stops a stamp being *copied*. An attacker who cannot
    /// compute a mark can still read one off a file a rule has already acted on
    /// — `xattr -p` needs no permission of its own — and write it onto the file
    /// they want immunised.
    func testTheSameRuleOnAnotherFileGetsAnotherMark() {
        XCTAssertNotEqual(StampMark.of(rule: "r", device: 1, inode: 2, key: key),
                          StampMark.of(rule: "r", device: 1, inode: 3, key: key))
        XCTAssertNotEqual(StampMark.of(rule: "r", device: 1, inode: 2, key: key),
                          StampMark.of(rule: "r", device: 4, inode: 2, key: key))
    }

    /// And the property that stops one being *written*. Without the key the mark
    /// is not a value anybody can produce, which is the whole difference between
    /// this and the rule id it replaces.
    func testAMarkMadeWithAnotherKeyIsAnotherMark() {
        XCTAssertNotEqual(StampMark.of(rule: "r", device: 1, inode: 2, key: key),
                          StampMark.of(rule: "r", device: 1, inode: 2, key: other))
    }

    /// Three values go into one message, so the way they are joined has to be a
    /// spelling no other triple can produce. A rule id is a stored string that
    /// has been a UUID, an empty string and an emoji in this suite already, and
    /// nothing stops it holding the separator.
    ///
    /// Device and inode are decimal digits and cannot hold one, so the first two
    /// separators are at fixed places and the rest of the message is the rule's
    /// — but a joining that put the rule first, or used no separator at all,
    /// would let (1, 23, "x") and (1, 2, "3:x") share a mark, which is one file
    /// immunised by another's stamp.
    func testNoTwoTriplesShareAMark() {
        let marks = [StampMark.of(rule: "3:x", device: 1, inode: 2, key: key),
                     StampMark.of(rule: "x", device: 1, inode: 23, key: key),
                     StampMark.of(rule: "x", device: 12, inode: 3, key: key),
                     StampMark.of(rule: ":x", device: 12, inode: 3, key: key),
                     StampMark.of(rule: "", device: 1, inode: 2, key: key)]
        XCTAssertEqual(Set(marks).count, marks.count, "two different triples share a mark")
    }

    /// Hex, so it survives the JSON the attribute holds and reads as nothing at
    /// all to whoever prints it — the mark says which rules have run, and a rule
    /// id said which rules exist.
    func testAMarkIsHexAndSaysNothingAboutTheRule() {
        let mark = StampMark.of(rule: "Invoices", device: 1, inode: 2, key: key)
        XCTAssertEqual(mark.count, 64)
        XCTAssertTrue(mark.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertFalse(mark.contains("Invoices"))
    }
}
