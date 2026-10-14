import XCTest
@testable import HelmRuntime

final class SystemExtensionParserTests: XCTestCase {
    /// Verbatim `systemextensionsctl list` output from a real machine.
    private let sample = """
    3 extension(s)
    --- com.apple.system_extension.network_extension (Go to 'System Settings > General > Login Items & Extensions > Network Extensions' to modify these system extension(s))
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tTNPM9PFX3W\tcom.nebula.karing.karingServiceSE (1.2.21/2408)\tkaringServiceSE\t[activated enabled]
    \t*\t2XZUN9L63Z\tcom.databridges.privacy.v2RayTun.snextension (2.2/19)\tsnextension\t[activated waiting for user]
    *\t*\tTC3Q7MAJXF\tcom.adguard.mac.adguard.network-extension (2.19.0/2258)\tAdGuard Network Extension\t[activated enabled]
    """

    func testListsEveryActivatedExtension() {
        let found = SystemExtensionParser.parse(sample)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map(\.identifier).sorted(), [
            "com.adguard.mac.adguard.network-extension",
            "com.databridges.privacy.v2RayTun.snextension",
            "com.nebula.karing.karingServiceSE",
        ])
    }

    /// The host app id is what the uninstaller matches against.
    func testDerivesHostAppIdentifiers() {
        let hosts = SystemExtensionParser.hostIdentifiers(sample)
        XCTAssertTrue(hosts.contains("com.nebula.karing"))
        XCTAssertTrue(hosts.contains("com.databridges.privacy.v2RayTun"))
        XCTAssertTrue(hosts.contains("com.adguard.mac.adguard"))
    }

    func testCarriesTeamStateAndName() {
        let found = SystemExtensionParser.parse(sample)
        let waiting = found.first { $0.identifier.contains("v2RayTun") }
        XCTAssertEqual(waiting?.teamID, "2XZUN9L63Z")
        XCTAssertEqual(waiting?.state, "activated waiting for user")
        XCTAssertEqual(waiting?.name, "snextension")
        XCTAssertFalse(waiting?.enabled ?? true)          // no `*` in the enabled column
        let adguard = found.first { $0.identifier.contains("adguard") }
        XCTAssertTrue(adguard?.enabled ?? false)
        XCTAssertEqual(adguard?.name, "AdGuard Network Extension")
    }

    func testIgnoresHeadersAndEmptyOutput() {
        XCTAssertTrue(SystemExtensionParser.parse("0 extension(s)\n").isEmpty)
        XCTAssertTrue(SystemExtensionParser.parse("").isEmpty)
    }

    // MARK: - The query over a stand-in tool

    /// One extension line of the listing, with each column given, so a row can
    /// damage exactly one of them.
    private func line(bundle: String = "com.acme.app.ext (1.0/1)", name: String = "Acme Extension") -> String {
        "*\t*\tABCDE12345\t\(bundle)\t\(name)\t[activated enabled]"
    }

    /// What `SystemExtensionCLI.listing(running:)` answered, and the deadline
    /// the stand-in tool was handed (`nil` when it was handed none).
    private struct Asked {
        var answer: String?
        var deadline: TimeInterval?
    }

    private func ask(status: Int32, output: String) -> Asked {
        var deadline: TimeInterval?
        let answer = SystemExtensionCLI.listing { asked in
            deadline = asked
            return HelmProcess.Result(status: status, output: output)
        }
        return Asked(answer: answer, deadline: deadline)
    }

    func testAToolThatExitedZeroGivesItsListing() {
        XCTAssertEqual(ask(status: 0, output: sample).answer, sample)
    }

    /// The text of a tool that failed is not a listing, whatever it printed.
    func testAToolThatExitedNonZeroGivesNothing() {
        XCTAssertNil(ask(status: 1, output: sample).answer)
    }

    /// A tool that was cut off at its deadline has no listing: nothing is not
    /// the empty list.
    func testAToolThatTimedOutGivesNothing() {
        XCTAssertNil(ask(status: HelmProcess.timedOutStatus, output: "").answer)
    }

    /// A damaged display name is not a reason to lose the listing: no caller
    /// acts on the name.
    func testADamagedNameStillGivesTheListing() {
        let damaged = [line(), line(bundle: "com.acme.other.ext (2.0/2)", name: "Ac\u{FFFD}me")]
            .joined(separator: "\n")
        XCTAssertEqual(ask(status: 0, output: damaged).answer, damaged)
    }

    /// The query is bounded: the tool is handed the listing deadline.
    func testTheQueryHandsTheToolADeadline() {
        let asked = ask(status: 0, output: sample)
        XCTAssertEqual(asked.deadline, SystemExtensionCLI.listingDeadline)
    }

    /// A damaged identifier gives nothing, and so does a damaged identifier on
    /// one line among clean ones: a caller reads the absence of an id as leave
    /// to call something a leftover, and a damaged id matches nothing.
    func testADamagedIdentifierGivesNothing() {
        let damaged = line(bundle: "com.acme.ap\u{FFFD}p.ext (1.0/1)")
        XCTAssertNil(ask(status: 0, output: damaged).answer)
        XCTAssertNil(ask(status: 0, output: [line(), damaged, line(bundle: "com.acme.b.ext (3.0/3)")]
            .joined(separator: "\n")).answer)
    }

    /// A damaged identifier on a line the parser skips (no "(" or no ".") still
    /// gives nothing: the parser drops that id just as it drops a damaged one it
    /// accepts, so the absence is the same.
    func testADamagedIdentifierOnASkippedLineGivesNothing() {
        let noParenthesis = line(bundle: "com.acme.app.ext \u{FFFD}1.0/1)")
        let noDot = line(bundle: "com\u{FFFD}acme (1)")
        for damaged in [noParenthesis, noDot] {
            XCTAssertTrue(SystemExtensionParser.parse(damaged).isEmpty,
                          "the row is about a line the parser skips: \(damaged)")
            XCTAssertNil(ask(status: 0, output: damaged).answer, damaged)
            XCTAssertNil(ask(status: 0, output: [line(), damaged].joined(separator: "\n")).answer, damaged)
        }
    }

    // MARK: - The query over a real tool

    /// `listing(tool:)` over a script that prints the sample and exits 0 gives
    /// that text back, through the real bounded `HelmProcess.run`.
    func testARealToolThatPrintsAListingGivesIt() throws {
        let dir = scratchDirectory("system-extension-listing-prints")
        let body = "cat <<'LISTING'\n\(sample)\nLISTING"
        let tool = ScratchTool.script(body, named: "prints-a-listing", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let answer = try XCTUnwrap(SystemExtensionCLI.listing(tool: tool))
        XCTAssertEqual(SystemExtensionParser.parse(answer).count, 3)
        XCTAssertEqual(answer.trimmingCharacters(in: .whitespacesAndNewlines),
                       sample.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `listing(tool:)` over a script that records its pid and then sleeps far
    /// past the deadline gives nothing, and is back within the deadline, the
    /// kill's grace and settle, and a second of slack. The sleep is 20 s, so a
    /// query that waits for the tool is seen as a long wait and ends by itself.
    func testARealToolThatNeverAnswersGivesNothingWithinTheDeadline() throws {
        let dir = scratchDirectory("system-extension-listing-silent")
        let tool = ScratchTool.script("""
            echo $$ > "$(dirname "$0")/tool"
            exec /bin/sleep 20
            """, named: "never-answers", in: dir)
        ScratchTool.removeAtTeardown(self, dir: dir)

        let started = Date()
        let answer = SystemExtensionCLI.listing(tool: tool)
        let elapsed = Date().timeIntervalSince(started)

        let pid = try XCTUnwrap(ScratchTool.pid(dir.appendingPathComponent("tool")),
                                "the script never recorded its own pid")
        XCTAssertNil(answer, "a tool that never answered (pid \(pid)) gave \(String(describing: answer))")
        XCTAssertLessThan(elapsed, SystemExtensionCLI.listingDeadline + 2 + 0.1 + 1, """
            the query was bounded at \(SystemExtensionCLI.listingDeadline) s and came back \
            only after \(elapsed) s
            """)
    }
}
