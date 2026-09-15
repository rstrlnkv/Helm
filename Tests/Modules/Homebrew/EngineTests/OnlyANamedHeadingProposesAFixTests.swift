import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorFixCandidate` — the bridge from an issue's body to a candidate argv.
///
/// The fixture is captured verbatim from:
///
///     $ /opt/homebrew/bin/brew doctor > /tmp/doc.out 2> /tmp/doc.err
///     exit=1
///        1 /tmp/doc.out
///     1194 /tmp/doc.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15 — the same 1194 bytes
/// `DoctorParserTests` holds, re-captured rather than copied across.
///
/// **The finding this whole file is shaped by: neither block in that run
/// printed a literal `brew …` command line, and no block did.** There is no
/// command in `brew doctor`'s real output to lift out. What exists is a heading
/// followed by an indented list of names, so the cases below are about
/// recognising that shape and refusing everything else — not about parsing a
/// command out of prose, which would have nothing to parse.
///
/// Every issue under test is produced by running `DoctorParser.parse` over that
/// captured text, so no case can pass against a body somebody typed to suit it.
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

    /// The real `postflight` block — the one whose body is a sentence and a
    /// path.
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
    /// candidate is that name as the operand of `uninstall`. Both halves are
    /// asserted: the subcommand the heading maps to, and the name lifted off
    /// the indented line — a candidate carrying the right name under the wrong
    /// verb, or the reverse, is a different command.
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

    /// The same issue, the same argv, and a `.copyOnly` fix — because the name
    /// came out of prose and this Mac does not have it. The extractor is
    /// unchanged between this case and the one above; **the judge is what
    /// differs**, which is the point: nothing in `DoctorFixCandidate` decides
    /// `.runnable`.
    func testTheSameIssueIsCopyOnlyWhenTheNameIsNotInstalled() throws {
        let issue = try deprecatedFormulaeIssue()
        for installed in [[], ["wget", "jq"], ["periphery-extra"]] as [[String]] {
            let judged = DoctorFixCandidate.judging(issue, installed: installed)
            XCTAssertEqual(judged.fix?.argv, ["uninstall", "periphery"], "\(installed)")
            XCTAssertEqual(judged.fix?.kind, .copyOnly, "\(installed)")
        }
    }

    // MARK: - Everything else is nothing

    /// The real `postflight` issue carries no fix at all — not a `.copyOnly`
    /// one, which would draw a command in the inspector for a person to copy.
    ///
    /// **Why it is nil is worth stating, because it is not the reason a reader
    /// expects:** its body names a path, but the path never gets looked at. The
    /// body holds no line matching any `Heading`, so the scan stops before rule
    /// 4 is ever reached. This case would stay green with the path rule
    /// deleted — `testAPathUnderTheHeadingIsNotAName` below is the one that
    /// holds that rule up, and it exists because this one cannot.
    func testThePostflightIssueProposesNothing() throws {
        let issue = try postflightIssue()
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: issue.body))
        XCTAssertNil(DoctorFixCandidate.judging(issue, installed: ["periphery"]).fix)
    }

    /// An indented item under the **real** heading that is an absolute path
    /// rather than a name proposes nothing. Brew prints paths on indented lines
    /// of their own throughout its output, so the day a heading on the list
    /// gains one this is the rule standing between it and
    /// `brew uninstall /opt/homebrew/…`.
    ///
    /// The heading line is lifted from the captured fixture and the item line
    /// from the `postflight` block's own path line, so neither is invented.
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
    /// sentence proposes nothing. Without this, the first word of the sentence
    /// becomes the operand — `brew uninstall consider` — which is a real
    /// command against a real machine and would have been offered as a button.
    ///
    /// The heading is the real one, so this case is not passing because nothing
    /// matched; it reaches the item rules and is refused by them.
    func testAPackageNameInsideASentenceIsNotAnItem() throws {
        let heading = "You should find replacements for the following formulae:"
        for line in ["  consider periphery's replacement before upgrading",
                     "  periphery is deprecated",
                     "  run brew uninstall periphery"] {
            XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: heading + "\n\n" + line), line)
        }
    }

    /// Two names under the heading propose **nothing** — the decision this file
    /// makes, written in `argv(inBodyOf:)`'s doc comment and pinned here.
    ///
    /// Two reasons, either sufficient: `DoctorIssue.fix` is one optional fix,
    /// so two argvs cannot both be carried; and taking one of two names offered
    /// is not the act the person read. The trap is a scan that stops at the
    /// first item and offers `brew uninstall periphery` over a list that also
    /// named `qt@5`.
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

    /// The same heading printed twice in one body proposes nothing. Brew
    /// repeats whole blocks — the fixture holds the `postflight` one three
    /// times — so two lists in one body is a shape this output can reach, and
    /// two lists are two acts of which only one would have been offered.
    func testTwoHeadingsInOneBodyProposeNothing() {
        let heading = "You should find replacements for the following formulae:"
        XCTAssertNil(DoctorFixCandidate.argv(
            inBodyOf: heading + "\n\n  periphery\n" + heading + "\n\n  qt@5"))
    }

    /// A heading is matched by equality on the whole line, so the same words
    /// carried inside a longer line are not a heading. A substring or
    /// case-folded match would let brew's ordinary prose — which quotes its own
    /// headings back at the reader — open a list of names, and the widening
    /// would be invisible until the day a sentence quoting the heading also
    /// indented something under it.
    func testAHeadingEmbeddedInALongerLineIsNotAHeading() {
        let heading = "You should find replacements for the following formulae:"
        for line in ["Note: " + heading,
                     heading + " see the list below",
                     heading.uppercased()] {
            XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: line + "\n\n  periphery"), line)
        }
    }

    /// The extraction never reads a title. An issue whose *title* is the
    /// heading and whose body holds only the name proposes nothing — the
    /// signature takes the body alone, and this pins that the body is genuinely
    /// where the heading has to be.
    func testAHeadingInTheTitleIsNotAHeading() {
        let issue = DoctorIssue(
            severity: .caution,
            title: "You should find replacements for the following formulae:",
            body: "\n  periphery")
        XCTAssertNil(DoctorFixCandidate.argv(inBodyOf: issue.body))
        XCTAssertNil(DoctorFixCandidate.judging(issue, installed: ["periphery"]).fix)
    }

    // MARK: - The list itself

    /// The hand-written heading list, named entry by entry. CLAUDE.md's rule
    /// for a hand-written list: adding one without coming here is a failure,
    /// not a silent widening of what this app will offer to run.
    ///
    /// Both halves of each entry are spelled out — the line brew prints and the
    /// subcommand it maps to — because the mapping is Helm's reading of brew's
    /// sentence and not a quotation of it.
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
    /// against the captured output rather than against itself. A heading nobody
    /// can reach is a rule that will never fire and will never be noticed.
    func testEveryHeadingOnTheListAppearsInTheCapturedOutput() {
        let lines = Self.capturedOutput.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for heading in DoctorFixCandidate.Heading.allCases {
            XCTAssertTrue(lines.contains(heading.rawValue), heading.rawValue)
        }
    }

    /// Every subcommand a heading maps to is one `DoctorFix.Allowed` can admit.
    /// A heading mapping to a verb no entry admits produces an argv that can
    /// only ever be copied — legal, but it should be a decision rather than an
    /// accident, and today it is not the case.
    func testEverySubcommandAHeadingMapsToCanBeAdmitted() {
        for heading in DoctorFixCandidate.Heading.allCases {
            let argv = [heading.subcommand, "periphery"]
            XCTAssertEqual(DoctorFix.judge(argv, installed: ["periphery"]).kind, .runnable,
                           heading.rawValue)
        }
    }
}
