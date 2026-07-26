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
            XCTAssertEqual(BrewSearchParser.parse(output).count, 0, output.debugDescription)
            XCTAssertEqual(BrewDescParser.parse(output).count, 0, output.debugDescription)
        }
        XCTAssertEqual(BrewOutdatedParser.parse(Data()).count, 0)
        XCTAssertEqual(BrewOutdatedParser.parse(Data("not json".utf8)).count, 0)
        XCTAssertEqual(BrewOutdatedParser.parse(Data("{}".utf8)).count, 0)
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
    func testAPackageThatIsBothFormulaAndCaskStaysTwoDistinguishableRows() {
        let json = """
        {"formulae":[{"name":"docker","installed_versions":["27.0.1"],"current_version":"28.0.0"}],
         "casks":[{"name":"docker","installed_versions":["4.30.0"],"current_version":"4.40.0"}]}
        """
        let outdated = BrewOutdatedParser.parse(Data(json.utf8))
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

    // MARK: - brew desc

    /// Real output from `brew desc --cask docker` on Homebrew 6: the display
    /// name group holds three comma-separated aliases, so the parenthesis the
    /// parser looks for is not the first one it could have taken.
    func testRealCaskDescriptionDropsTheWholeDisplayNameGroup() {
        let out = "docker-desktop: (Docker Desktop, Docker Community Edition, Docker CE) "
            + "App to build and share containerised applications and microservices"
        XCTAssertEqual(BrewDescParser.parse(out)["docker-desktop"],
                       "App to build and share containerised applications and microservices")
    }

    /// A description with a colon-space in it must keep everything after the
    /// first separator — the split is on the name, not on punctuation.
    func testADescriptionContainingAColonKeepsAllOfIt() {
        XCTAssertEqual(BrewDescParser.parse("pandoc: Swiss-army knife: markup converter")["pandoc"],
                       "Swiss-army knife: markup converter")
    }

    // MARK: - brew search

    /// The documented sectioned shape. Kept as the control for the test below.
    func testSectionedSearchOutputAssignsTheKindPerSection() {
        let out = """
        ==> Formulae
        firefoxpwa
        ==> Casks
        firefox
        firefox@beta
        """
        let hits = BrewSearchParser.parse(out)
        XCTAssertEqual(hits.filter { !$0.isCask }.map(\.name), ["firefoxpwa"])
        XCTAssertEqual(hits.filter(\.isCask).map(\.name), ["firefox", "firefox@beta"])
    }

    /// This is the shape Homebrew 6.0.12 actually pipes: no `==>` headers at
    /// all, formulae first, a blank line, then casks. The parser's fallback
    /// ("a flat list is formulae") then labels every cask a formula, and
    /// `install(name:isCask:)` builds `brew install <name>` without `--cask`.
    /// For a name that exists in both taps — `docker` — that installs the CLI
    /// when the user pressed Install on the app.
    ///
    /// A unit test cannot assert the right kind here: the text carries no kind
    /// to read. What it can pin is that the parser does not silently *claim*
    /// one. Recorded as the characterisation of today's behaviour, with the
    /// live cross-check in `BrewSearchKindLiveScan` as the actual gate.
    func testHeaderlessSearchOutputIsWhatCurrentBrewEmits() {
        let out = "firefoxpwa\nfirefly\n\nfirefox\nfirefox@beta\n"
        let hits = BrewSearchParser.parse(out)
        XCTAssertEqual(hits.map(\.name), ["firefoxpwa", "firefly", "firefox", "firefox@beta"],
                       "the blank separator must not become a row")
        XCTAssertTrue(hits.allSatisfy { !$0.isCask },
                      "characterisation: with no headers everything is called a formula — "
                      + "see BrewSearchKindLiveScan for what that costs")
    }

    /// Brew's own prose must never become an installable row. "Error: No
    /// formulae or casks found for …" is what 6.0.12 prints for a miss, and it
    /// arrives on stdout in the same string the parser is handed.
    func testBrewsNoResultsProseIsNotAPackage() {
        XCTAssertEqual(BrewSearchParser.parse("Error: No formulae or casks found for \"zzqqxx\".").count, 0)
    }
}

/// Cross-checks the search parser's `isCask` against brew itself. Depends on
/// the installed Homebrew and its index, so it informs rather than gates:
/// `HELM_BENCH=1 swift test --filter BrewSearchKindLiveScan`.
final class BrewSearchKindLiveScan: XCTestCase {
    private func brew(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["brew"] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func testSearchHitsCarryTheKindBrewItselfReports() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let query = "firefox"
        // The same two calls the engine makes: brew no longer labels a flat
        // list, so the kind comes from which call produced the name.
        let hits = BrewSearchParser.parse(try brew(["search", "--formula", query]), kind: false)
                 + BrewSearchParser.parse(try brew(["search", "--cask", query]), kind: true)
        let casks = Set(try brew(["search", "--cask", query])
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") })
        XCTAssertFalse(hits.isEmpty, "no hits at all — brew index may be cold")
        let mislabelled = hits.filter { casks.contains($0.name) && !$0.isCask }
        print("search '\(query)': \(hits.count) hits, \(casks.count) casks, \(mislabelled.count) mislabelled")
        for hit in mislabelled { print("  cask shown as formula: \(hit.name)") }
        XCTAssertTrue(mislabelled.isEmpty,
                      "Install on these rows runs `brew install <name>` without --cask: "
                      + mislabelled.map(\.name).joined(separator: ", "))
    }
}
