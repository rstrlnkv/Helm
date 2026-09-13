import XCTest
@testable import Module_Homebrew_Engine

/// Three traps, all silent, all measured against the real documents on
/// 2026-09-13.
///
/// The cask document's top-level key is `"formulae"` — not `"casks"` — so a
/// decoder that reads the obvious key returns an empty dictionary and throws
/// nothing. The count is a string with thousands separators, so `Int(_:)` on it
/// answers nil for exactly the packages that matter most. And a document this
/// parser does not recognise has to answer nil rather than an empty map, or a
/// broken endpoint reads as "nobody installs anything" and quietly re-sorts
/// every search result by nothing at all.
final class InstallCountsParserTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testAFormulaDocumentIsRead() {
        let json = #"{"category":"formula_install_on_request","formulae":"#
                 + #"{"wget":[{"formula":"wget","count":"4,321"}],"#
                 + #""jq":[{"formula":"jq","count":"87"}]}}"#
        XCTAssertEqual(InstallCounts.parse(data(json))?.counts, ["wget": 4321, "jq": 87])
    }

    /// The cask file keys its packages under `formulae` too. This is the test
    /// that fails when somebody "fixes" the key to match the file's subject.
    func testACaskDocumentUsesTheSameTopLevelKey() {
        let json = #"{"category":"cask_install","formulae":"#
                 + #"{"firefox":[{"cask":"firefox","count":"12,345"}]}}"#
        XCTAssertEqual(InstallCounts.parse(data(json))?.counts, ["firefox": 12345])
    }

    func testAThousandsSeparatorIsNotPartOfTheNumber() {
        let json = #"{"formulae":{"node":[{"formula":"node","count":"1,162"}]}}"#
        XCTAssertEqual(InstallCounts.parse(data(json))?.counts["node"], 1162)
    }

    /// A count that is not a number at all costs its own package a rank and
    /// nothing else — the rest of the document is still an answer.
    func testAnUnreadableCountDropsOnlyItsOwnPackage() {
        let json = #"{"formulae":{"a":[{"count":"nope"}],"b":[{"count":"5"}]}}"#
        XCTAssertEqual(InstallCounts.parse(data(json))?.counts, ["b": 5])
    }

    func testADocumentThisParserDoesNotKnowIsNotAnAnswer() {
        XCTAssertNil(InstallCounts.parse(data("not json at all")))
        XCTAssertNil(InstallCounts.parse(data(#"{"category":"formula_install_on_request"}"#)),
                     "a document with no packages key is not «nobody installs anything»")
        XCTAssertNil(InstallCounts.parse(Data()))
    }

    /// An empty map *is* an answer, and a different one.
    func testAnEmptyPackageListIsAnAnswer() {
        XCTAssertEqual(InstallCounts.parse(data(#"{"formulae":{}}"#))?.counts, [:])
    }
}
