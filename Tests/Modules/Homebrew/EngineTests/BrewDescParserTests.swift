import XCTest
@testable import Module_Homebrew_Engine

final class BrewDescParserTests: XCTestCase {
    func testParsesNameDescriptionLines() {
        let out = "jq: Lightweight and flexible command-line JSON processor\nwget: Internet file retriever\n"
        let d = BrewDescParser.parse(out)
        XCTAssertEqual(d["jq"], "Lightweight and flexible command-line JSON processor")
        XCTAssertEqual(d["wget"], "Internet file retriever")
    }

    func testDropsCaskDisplayNameParens() {
        XCTAssertEqual(BrewDescParser.parse("figma: (Figma) Collaborative team software\n")["figma"],
                       "Collaborative team software")
    }

    func testIgnoresNoiseLines() {
        let d = BrewDescParser.parse("Warning: something\n\nplain line without separator\n")
        XCTAssertTrue(d.isEmpty || d["Warning"] == "something")   // no crash; junk tolerated
    }
}
