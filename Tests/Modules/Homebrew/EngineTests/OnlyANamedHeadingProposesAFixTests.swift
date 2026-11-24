import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorFixCandidate` — the bridge from an issue's body to a candidate argv.
///
/// The fixture is `brew doctor`'s real standard error, the same 1194 bytes
/// `DoctorParserTests` holds, captured separately rather than copied across.
///
/// **No block of real `brew doctor` output prints a literal `brew …` command
/// line.** What exists is a heading followed by an indented list of names, so
/// the cases are about recognising that shape and refusing everything else.
///
/// Every issue under test is produced by `DoctorParser.parse` over the captured
/// text, so no case can pass against a body typed to suit it.
final class OnlyANamedHeadingProposesAFixTests: XCTestCase {

    /// Byte-for-byte what `/tmp/doc.err` held.
    private static let capturedOutput = """
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!

        Warning: Some installed formulae are deprecated or disabled.
        You should find replacements for the following formulae:

          periphery
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        """

    /// The real `postflight` block, whose body is a sentence and a path.
    private func postflightIssue() throws -> DoctorIssue {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.capturedOutput))
        return try XCTUnwrap(issues.first { $0.title.hasPrefix("Calling `postflight`") })
    }

    /// The real deprecated-formulae block — heading, blank line, `  periphery`.
    private func deprecatedFormulaeIssue() throws -> DoctorIssue {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.capturedOutput))
        return try XCTUnwrap(issues.first { $0.title.hasPrefix("Some installed formulae") })
    }

    // MARK: - The one shape this machine produces

    /// The heading is on the list and the list under it holds one name, so the
    /// candidate is that name as the operand of `uninstall`. Both the verb and
    /// the name are asserted: either one wrong is a different command.
    func testTheDeprecatedFormulaeIssueProposesUninstallingTheNameItLists() throws {
        let issue = try deprecatedFormulaeIssue()
        XCTAssertEqual(DoctorFixCandidate.argv(inBodyOf: issue.body), ["uninstall", "periphery"])
    }

    /// With `periphery` on this Mac's installed list, the judge admits it and
    /// the issue carries a `.runnable` fix.
    func testTheFixIsRunnableWhenTheNameIsOnTheInstalledList() throws {
        let judged = DoctorFixCandidate.judging(try deprecatedFormulaeIssue(),
                                                installed: ["wget", "periphery", "jq"])
        XCTAssertEqual(judged.fix?.argv, ["uninstall", "periphery"])
        XCTAssertEqual(judged.fix?.kind, .runnable)
        // The rest of the issue is untouched — this call fills `fix` in and
        // re-spells nothing, so a body or title quietly rebuilt here would show.
        XCTAssertEqual(DoctorIssue(severity: judged.severity, title: judged.title,
                                   body: judged.body, fix: nil),
                       try deprecatedFormulaeIssue())
    }

    /// The same issue and argv give a `.copyOnly` fix when this Mac does not
    /// have the name: the judge decides `.runnable`, never `DoctorFixCandidate`.
    func testTheSameIssueIsCopyOnlyWhenTheNameIsNotInstalled() throws {
        let issue = try deprecatedFormulaeIssue()
        for installed in [[], ["wget", "jq"], ["periphery-extra"]] as [[String]] {
            let judged = DoctorFixCandidate.judging(issue, installed: installed)
            XCTAssertEqual(judged.fix?.argv, ["uninstall", "periphery"], "\(installed)")
            XCTAssertEqual(judged.fix?.kind, .copyOnly, "\(installed)")
        }
    }

    // MARK: - Everything else is nothing

    /// The real `postflight` issue carries no fix at all, not even a `.copyOnly`
    /// one, which would draw a command in the inspector for a person to copy.
    ///
    /// It is nil because its body holds no `Heading` line, not because of its
    /// path; `testAPathUnderTheHeadingIsNotAName` holds the path rule.
    func testThePostflightIssueProposesNothing() throws {
        let issue = try postflightIssue()
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: issue.body))
        XCTAssertNil(DoctorFixCandidate.judging(issue, installed: ["periphery"]).fix)
    }

    /// An indented absolute path under the real heading proposes nothing. Brew
    /// prints paths on indented lines throughout its output, so this rule is what
    /// stands between such a line and `brew uninstall /opt/homebrew/…`. Both
    /// lines are lifted from the captured fixture.
    func testAPathUnderTheHeadingIsNotAName() throws {
        let heading = try XCTUnwrap(
            Self.capturedOutput.components(separatedBy: "\n")
                .first { $0 == "You should find replacements for the following formulae:" })
        let path = "  /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18"

        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n" + path))
        // A relative one and a home-relative one, for the same reason.
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n  ~/Library/Caches/Homebrew"))
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n  ./Casks/kaset.rb"))
    }

    /// A line under the heading that *mentions* a package name inside a
    /// sentence proposes nothing, not `brew uninstall consider`. The heading is
    /// the real one, so the case reaches the item rules and is refused by them.
    func testAPackageNameInsideASentenceIsNotAnItem() throws {
        let heading = "You should find replacements for the following formulae:"
        for line in ["  consider periphery's replacement before upgrading",
                     "  periphery is deprecated",
                     "  run brew uninstall periphery"] {
            XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n" + line), line)
        }
    }

    /// Two names under the heading propose **nothing** (`argv(inBodyOf:)`'s doc
    /// comment): `DoctorIssue.fix` carries one fix, and taking one of two names
    /// offered is not the act the person read.
    func testTwoNamesUnderTheHeadingProposeNothing() {
        let heading = "You should find replacements for the following formulae:"
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n  periphery\n  qt@5"))
        // Separated by a blank line, which is why a blank line does not end the
        // list: if it did, this body would propose acting on the first of two.
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n  periphery\n\n  qt@5"))
    }

    /// A heading with nothing indented under it proposes nothing — an empty
    /// list is not an act, and `["uninstall"]` on its own is not
    /// argument-complete.
    func testAHeadingWithNoItemsProposesNothing() {
        let heading = "You should find replacements for the following formulae:"
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading))
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n"))
        // Flush against the left margin, the name is not part of the list: the
        // indentation is the only thing marking an item as one.
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\nperiphery"))
    }

    /// The same heading printed twice in one body proposes nothing. Brew repeats
    /// whole blocks, so two lists in one body is a reachable shape, and two lists
    /// are two acts of which only one would be offered.
    func testTwoHeadingsInOneBodyProposeNothing() {
        let heading = "You should find replacements for the following formulae:"
        XCTAssertNil(DoctorFixCandidate.argv(
            inBodyOf: heading + "\n\n  periphery\n" + heading + "\n\n  qt@5"))
    }

    /// A heading is matched by equality on the whole line. brew's prose quotes
    /// its own headings back at the reader, so a substring or case-folded match
    /// would let a sentence open a list of names.
    func testAHeadingEmbeddedInALongerLineIsNotAHeading() {
        let heading = "You should find replacements for the following formulae:"
        for line in ["Note: " + heading,
                     heading + " see the list below",
                     heading.uppercased()] {
            XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: line + "\n\n  periphery"), line)
        }
    }

    /// The extraction never reads a title: an issue whose *title* is the heading
    /// and whose body holds only the name proposes nothing.
    func testAHeadingInTheTitleIsNotAHeading() {
        let issue = DoctorIssue(
            severity: .caution,
            title: "You should find replacements for the following formulae:",
            body: "\n  periphery")
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: issue.body))
        XCTAssertNil(DoctorFixCandidate.judging(issue, installed: ["periphery"]).fix)
    }

    // MARK: - The list itself

    /// The hand-written heading list, named entry by entry, so adding one
    /// without coming here fails rather than silently widening what this app
    /// offers to run. Both halves of each entry are spelled out: the mapping is
    /// Helm's reading of brew's sentence, not a quotation of it.
    func testEveryHeadingOnTheListIsNamedHere() {
        XCTAssertEqual(DoctorFixCandidate.Heading.allCases.count, 1,
                       "A heading was added or removed. Name it here and read the checklist "
                       + "under DoctorFixCandidate.argv(inBodyOf:).")
        XCTAssertEqual(DoctorFixCandidate.Heading.deprecatedOrDisabledFormulae.rawValue,
                       "You should find replacements for the following formulae:")
        XCTAssertEqual(DoctorFixCandidate.Heading.deprecatedOrDisabledFormulae.subcommand,
                       "uninstall")
    }

    /// Every heading on the list is a line `brew doctor` really prints, checked
    /// against the captured output; a heading nobody can reach never fires.
    func testEveryHeadingOnTheListAppearsInTheCapturedOutput() {
        let lines = Self.capturedOutput.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for heading in DoctorFixCandidate.Heading.allCases {
            XCTAssertTrue(lines.contains(heading.rawValue), heading.rawValue)
        }
    }

    /// Every subcommand a heading maps to is one `DoctorFix.Allowed` can admit;
    /// otherwise its argv could only ever be copied.
    func testEverySubcommandAHeadingMapsToCanBeAdmitted() {
        for heading in DoctorFixCandidate.Heading.allCases {
            let argv = [heading.subcommand, "periphery"]
            XCTAssertEqual(DoctorFix.judge(argv, installed: ["periphery"]).kind, .runnable,
                           heading.rawValue)
        }
    }
}
