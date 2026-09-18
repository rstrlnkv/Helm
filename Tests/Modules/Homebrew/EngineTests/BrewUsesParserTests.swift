import XCTest
@testable import Module_Homebrew_Engine

/// `brew uses --installed` prints one name per line, and that is the whole
/// contract this parser is allowed to assume.
///
/// Measured against Homebrew 6.x on 2026-09-13: a leaf answers **exit 0 with
/// empty stdout**, and every warning it has to make — a deprecated tap, a name
/// it cannot resolve — goes to stderr, which `HelmProcess.run` sends to the null
/// device. So an empty answer is "nothing depends on it" and never "the tool
/// complained", and no line needs filtering beyond the blank ones a trailing
/// newline leaves behind.
final class BrewUsesParserTests: XCTestCase {

    func testOneNamePerLine() {
        XCTAssertEqual(BrewUsesParser.parse("aria2\nnode\npython@3.14\n"),
                       ["aria2", "node", "python@3.14"])
    }

    func testALeafHasNoDependents() {
        XCTAssertEqual(BrewUsesParser.parse(""), [])
        XCTAssertEqual(BrewUsesParser.parse("\n"), [])
    }

    /// Whitespace a shell would have eaten is not part of a package name.
    func testSurroundingWhitespaceIsNotPartOfAName() {
        XCTAssertEqual(BrewUsesParser.parse("  aria2  \n\n node \n"), ["aria2", "node"])
    }
}
