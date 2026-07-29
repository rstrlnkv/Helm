import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The question `RenamePattern` has to answer before it renames anything: is
/// this file already called something this pattern produces?
///
/// A shape is the pattern with `{date}` and `{counter}` already resolved for
/// one file and `{name}` left as a hole. Matching is therefore not a prefix
/// test, not a `contains`, and not a list of the tokens somebody thought of:
/// the literals of the pattern, in order, with at least one character standing
/// in for the name.
final class RenameShapeTests: XCTestCase {

    // MARK: - One hole

    func testAShapeMatchesTheNameItsOwnPatternProduced() {
        let shape = RenameShape(resolved: "2026-07-15-{name}")

        XCTAssertTrue(shape.matches("2026-07-15-report"))
        XCTAssertFalse(shape.matches("report"), "a name the pattern has not been applied to")
    }

    /// The literal may sit at either end, and it is matched where it belongs
    /// rather than anywhere in the name.
    func testATrailingLiteralIsASuffixAndNotJustSomethingContained() {
        let shape = RenameShape(resolved: "{name}-copy")

        XCTAssertTrue(shape.matches("my-report-copy"))
        XCTAssertFalse(shape.matches("copy-my-report"))
    }

    /// The hole is the file's name, and a file has one. Without this, `scan-`
    /// on its own would read as a name that has already been renamed.
    func testTheHoleTakesAtLeastOneCharacter() {
        let shape = RenameShape(resolved: "scan-{name}")

        XCTAssertTrue(shape.matches("scan-r"))
        XCTAssertFalse(shape.matches("scan-"))
    }

    // MARK: - More than one hole, and none

    /// Two holes need two characters between them, so the shape of a pattern
    /// that names the file twice is still an honest question about the name.
    func testTwoHolesEachTakeTheirOwnCharacter() {
        let shape = RenameShape(resolved: "{name}{name}")

        XCTAssertTrue(shape.matches("reportreport"))
        XCTAssertTrue(shape.matches("ab"))
        XCTAssertFalse(shape.matches("a"))
        XCTAssertFalse(shape.matches(""))
    }

    /// A middle literal is searched for rather than expected at a fixed offset:
    /// the holes on either side are whatever is left.
    func testAMiddleLiteralIsFoundWhereverTheHolesAllow() {
        let shape = RenameShape(resolved: "{name} 2026-07-15 {name}")

        XCTAssertTrue(shape.matches("a 2026-07-15 b"))
        XCTAssertTrue(shape.matches("a b 2026-07-15 c d"))
        XCTAssertFalse(shape.matches("a 2026-07-15"), "nothing stands in for the second name")
    }

    /// A pattern that never names the file describes exactly one name, and
    /// describes it exactly: `report` and `REPORT` are two different requests,
    /// which is the whole point of a rule that normalises capitalisation.
    func testAShapeWithoutAHoleIsTheOneNameItSpells() {
        let shape = RenameShape(resolved: "REPORT")

        XCTAssertTrue(shape.matches("REPORT"))
        XCTAssertFalse(shape.matches("report"))
        XCTAssertFalse(shape.matches("REPORT 2"))
    }

    // MARK: - What the produced name went through

    /// `RenamePattern` trims what it produces, so a pattern padded with spaces
    /// produces an unpadded name — and the shape has to be the shape of the
    /// name that lands, not of the pattern as typed.
    func testPaddingAroundThePatternIsNotPartOfTheShape() {
        XCTAssertTrue(RenameShape(resolved: "  {name}  ").matches("report"))
        XCTAssertTrue(RenameShape(resolved: " scan-{name} ").matches("scan-report"))
    }

    /// Inside, whitespace is a literal like any other.
    func testWhitespaceInsideThePatternIsMatchedLiterally() {
        let shape = RenameShape(resolved: "{name}\t2026-07-15")

        XCTAssertTrue(shape.matches("report\t2026-07-15"))
        XCTAssertFalse(shape.matches("report 2026-07-15"))
    }
}
