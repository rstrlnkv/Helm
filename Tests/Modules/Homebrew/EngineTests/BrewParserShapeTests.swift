import XCTest
@testable import Module_Homebrew_Engine

/// The four brew parsers all read text a tool prints for humans, and the tool
/// changes its mind about that text between versions. These pin the shapes that
/// matter — and one that current Homebrew no longer emits.
final class BrewParserShapeTests: XCTestCase {

    // MARK: - Nothing in, nothing out

    /// Cheapest whole family: brew fails, prints a warning to stderr and nothing
    /// to stdout, or prints only whitespace. No parser may invent a row from it,
    /// because a row is a button that runs `brew uninstall`.
    func testNoParserInventsRowsFromEmptyOrBlankOutput() {
        for output in ["", "\n", "   ", "\n\n\n", "\t\n \n"] {
            XCTAssertEqual(BrewSearchParser.parse(output, isCask: false).count, 0, output.debugDescription)
            XCTAssertEqual(BrewDescParser.parse(output).count, 0, output.debugDescription)
        }
        // Stronger than a count of zero for this one: nothing readable in is
        // "the module could not answer", which the engine keeps apart from a
        // machine with nothing outstanding (`ARefusedQueryIsNotACleanMachineTests`).
        XCTAssertNil(BrewOutdatedParser.parse(Data()))
        XCTAssertNil(BrewOutdatedParser.parse(Data("not json".utf8)))
        XCTAssertNil(BrewOutdatedParser.parse(Data("{}".utf8)))
    }

    /// Split out because this one is the odd parser: the other three trim each
    /// line before deciding, `BrewListParser` splits only on the literal space.
    /// A line holding nothing but a tab therefore becomes a package named "\t",
    /// and every package row carries an Uninstall button that passes its name
    /// straight to `brew uninstall`. Lowest-harm of the findings in this pass —
    /// `brew list --versions` does not print such a line today — but it is the
    /// same missing trim that would turn any prose brew sends to stdout into a
    /// row, and the fix is one call.
    func testAWhitespaceOnlyLineIsNotAPackage() {
        for output in ["\t\n", " \n", "\t\n \n", "\u{00A0}\n"] {
            XCTAssertEqual(BrewListParser.parse(output, isCask: false).map(\.name), [],
                           output.debugDescription)
        }
    }

    // MARK: - Name collisions across kinds

    /// Trap of the family that bit Login Items: two rows that render the same
    /// identity. `docker` is both a formula (the CLI) and a cask (the app), and
    /// the Install/Uninstall buttons pass `isCask` straight to the brew command.
    /// If the two ever collapse into one row, the button uninstalls the wrong
    /// one. The rows carry it correctly today — pinning so they keep to it.
    func testAPackageThatIsBothFormulaAndCaskStaysTwoDistinguishableRows() throws {
        let json = """
        {"formulae":[{"name":"docker","installed_versions":["27.0.1"],"current_version":"28.0.0"}],
         "casks":[{"name":"docker","installed_versions":["4.30.0"],"current_version":"4.40.0"}]}
        """
        let outdated = try XCTUnwrap(BrewOutdatedParser.parse(Data(json.utf8)))
        XCTAssertEqual(outdated.count, 2)
        XCTAssertEqual(Set(outdated.map { "\($0.isCask ? "c" : "f"):\($0.name)" }).count, 2)
        // The kind must travel with the version pair, not be reassigned by order.
        XCTAssertEqual(outdated.first { !$0.isCask }?.installed, "27.0.1")
        XCTAssertEqual(outdated.first { $0.isCask }?.installed, "4.30.0")
    }

    /// The same identity rule for the two `brew list --versions` calls, which
    /// the engine makes separately per kind and concatenates.
    func testTheTwoListCallsProduceDistinguishableRowsForTheSameName() {
        let formulae = BrewListParser.parse("docker 27.0.1\n", isCask: false)
        let casks = BrewListParser.parse("docker 4.30.0\n", isCask: true)
        XCTAssertEqual(Set((formulae + casks).map { "\($0.isCask ? "c" : "f"):\($0.name)" }).count, 2)
    }
}
