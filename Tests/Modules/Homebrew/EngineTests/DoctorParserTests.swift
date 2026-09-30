import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorParser.parse` against `brew doctor`'s real answer.
///
/// The fixture below is captured verbatim — not tidied, not reduced to two
/// invented duplicates — from:
///
///     $ /opt/homebrew/bin/brew doctor > /tmp/doctor.out 2> /tmp/doctor.err
///     exit=1
///        1 /tmp/doctor.out
///     1194 /tmp/doctor.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15. It holds a tap's `postflight`
/// deprecation warning three times, brew's own aside to the reader sitting
/// *between* the second and third repeat rather than only at the end, and
/// «Some installed formulae are deprecated or disabled» naming `periphery` on
/// its own indented line.
final class DoctorParserTests: XCTestCase {

    /// Byte-for-byte what `/tmp/doctor.err` held. Reused across cases so a
    /// slip while retyping the fixture cannot make two tests disagree about
    /// what "real output" is.
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

    /// The real repetition collapses to one issue: three identical
    /// `postflight` blocks (indices 0, 1 and the very last block in the
    /// fixture) must read back as a single entry, not three, and the
    /// disclaimer paragraph sitting between the second and third repeat must
    /// not have leaked into any of their bodies — if it had, the second copy
    /// would carry different text from the first and dedup would fail to
    /// collapse them, so this single equality assertion is what catches that.
    func testTwoDistinctIssuesWithTheRepeatedBlockCollapsed() {
        let postflightBody = """
            Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
              /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18
            """
        let deprecatedFormulaeBody = """
            You should find replacements for the following formulae:

              periphery
            """
        let expected = [
            DoctorIssue(
                severity: .caution,
                title: "Calling `postflight` is deprecated! Use `postflight_steps` instead.",
                body: postflightBody),
            DoctorIssue(
                severity: .caution,
                title: "Some installed formulae are deprecated or disabled.",
                body: deprecatedFormulaeBody),
        ]

        XCTAssertEqual(DoctorParser.parse(Self.capturedOutput), expected)
    }

    /// A body line naming a path is kept exactly as brew printed it —
    /// including its leading two spaces — because this module does not
    /// re-spell somebody's paths. Failing this while the count-and-equality
    /// test above still passes would mean the assertion above stopped being
    /// specific enough on its own; this pins the one line that matters most.
    func testAPathInABodyLineSurvivesVerbatim() {
        let issues = DoctorParser.parse(Self.capturedOutput)
        XCTAssertEqual(
            issues?.first?.body.components(separatedBy: "\n").last,
            "  /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18")
    }

    /// `Error:` and `Warning:` map to distinct severities. Homebrew 7.0.1
    /// produced no `Error:` line on this machine, so this half of the fixture
    /// is a small, isolated string rather than a real capture — unlike the
    /// repetition above, nothing here depends on this being brew's own text.
    func testErrorIsDangerAndWarningIsCaution() {
        let text = "Error: Your Command Line Tools are outdated.\nRun `xcode-select --install`.\n"
        let issues = DoctorParser.parse(text)

        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.severity, .danger)
        XCTAssertEqual(issues?.first?.title, "Your Command Line Tools are outdated.")

        let warningText = "Warning: Something is off.\nA detail.\n"
        XCTAssertEqual(DoctorParser.parse(warningText)?.first?.severity, .caution)
    }

    /// Real output naming no `Warning:`/`Error:` line at all — brew's own
    /// aside to the reader, lifted verbatim from the middle of the captured
    /// fixture above — reads as "doctor ran and found nothing": an empty
    /// array, not nil.
    func testOutputWithNoWarningOrErrorLineIsAnEmptyArray() {
        let prose = """
            Please note that these warnings are just used to help the Homebrew maintainers
            with debugging if you file an issue. If everything you use Homebrew for is
            working fine: please don't worry or file an issue; just ignore this. Thanks!
            """

        XCTAssertEqual(DoctorParser.parse(prose), [])
    }

    /// Empty input is nil — the tool said nothing, which is not the same
    /// claim as "the tool ran and the machine is clean". This is the case the
    /// stderr measurement exists to guard: get it wrong and a refused or
    /// never-run query reads as a healthy machine.
    func testEmptyInputIsNil() {
        XCTAssertNil(DoctorParser.parse(""))
    }

    // MARK: - A block is kept whole

    /// brew's own text for these three, assembled from `Finding#to_s`
    /// (`text`, a newline, the remediation stripped) and the sources that
    /// name them in Homebrew 7.0.7 on this machine — `diagnostic.rb`
    /// (`check_for_stray_dylibs`, `check_for_unlinked_but_not_keg_only`,
    /// `check_user_path_1`) and `cmd/doctor.rb` for the aside and the
    /// support-tier message. Each of them has a blank line followed by an
    /// unindented line *inside* the one finding, which is what the old
    /// boundary took for the end of it. The file names and package names are
    /// invented; the sentences are brew's.
    private static let dylibs = """
        Warning: Unbrewed dylibs were found in /usr/local/lib.
        If you didn't put them there on purpose they could cause problems when
        building Homebrew formulae and may need to be deleted.

        Unexpected dylibs:
          /usr/local/lib/libcrypto.dylib
          /usr/local/lib/libssl.dylib
        """

    private static let unlinkedKegs = """
        Warning: You have unlinked kegs in your Cellar.
        Leaving kegs unlinked can lead to build-trouble and cause formulae that depend on
        those kegs to fail to run properly once built.

        Run `brew link` on these:
          python@3.12
          node
        """

    private static let pathConflicts = """
        Warning: /usr/bin occurs before /opt/homebrew/bin in your PATH.
        This means that system-provided programs will be used instead of those
        provided by Homebrew.

        The following tools exist at both paths:
          git
          python3
        """

    /// The dylibs warning reaches the person with its list: the file names
    /// are the thing a person would delete, and they sit after the blank line
    /// that the old boundary treated as the end of the body.
    func testTheListAfterABlankLineIsPartOfTheBody() {
        let issues = DoctorParser.parse(Self.dylibs + "\n")
        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.title, "Unbrewed dylibs were found in /usr/local/lib.")
        XCTAssertEqual(issues?.first?.body, """
            If you didn't put them there on purpose they could cause problems when
            building Homebrew formulae and may need to be deleted.

            Unexpected dylibs:
              /usr/local/lib/libcrypto.dylib
              /usr/local/lib/libssl.dylib
            """)
    }

    /// `Run `brew link` on these:` starts an unindented line after a blank
    /// one, and the names under it are the answer to the warning.
    func testTheRemediationAfterABlankLineIsPartOfTheBody() {
        let issues = DoctorParser.parse(Self.unlinkedKegs + "\n")
        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.body.components(separatedBy: "\n").suffix(3),
                       ["Run `brew link` on these:", "  python@3.12", "  node"])
        XCTAssertTrue(issues?.first?.body.contains("those kegs to fail to run properly once built.") == true)
    }

    /// Three findings in one run — each keeps its own list, and none swallows
    /// its neighbour: the next `Warning:` is still the boundary.
    func testSeveralFindingsEachKeepTheirWholeBlock() {
        let text = [Self.pathConflicts, Self.dylibs, Self.unlinkedKegs].joined(separator: "\n\n") + "\n"
        let issues = DoctorParser.parse(text)
        XCTAssertEqual(issues?.map(\.title), [
            "/usr/bin occurs before /opt/homebrew/bin in your PATH.",
            "Unbrewed dylibs were found in /usr/local/lib.",
            "You have unlinked kegs in your Cellar.",
        ])
        XCTAssertEqual(issues?[0].body.components(separatedBy: "\n").suffix(3),
                       ["The following tools exist at both paths:", "  git", "  python3"])
        XCTAssertEqual(issues?[1].body.components(separatedBy: "\n").last,
                       "  /usr/local/lib/libssl.dylib")
        XCTAssertEqual(issues?[2].body.components(separatedBy: "\n").last, "  node")
    }

    /// brew's aside to the reader is a frame around the findings and stays
    /// out of every body, wherever it lands. **The input here is composed and
    /// not observed**: `cmd/doctor.rb` prints the aside once, before its first
    /// warning, so between two blocks is a place brew does not put it. The
    /// scan stops at a frame line and does not depend on that, and this holds
    /// it to that — after a long block whose body runs on past blank lines,
    /// the aside is not the body's last paragraph.
    func testTheAsideAfterALongBlockIsNotItsBody() {
        let aside = """
            Please note that these warnings are just used to help the Homebrew maintainers
            with debugging if you file an issue. If everything you use Homebrew for is
            working fine: please don't worry or file an issue; just ignore this. Thanks!
            """
        let text = Self.dylibs + "\n\n" + aside + "\n\n" + Self.unlinkedKegs + "\n"
        let issues = DoctorParser.parse(text)
        XCTAssertEqual(issues?.count, 2)
        XCTAssertEqual(issues?[0].body.components(separatedBy: "\n").last, "  /usr/local/lib/libssl.dylib")
        XCTAssertFalse(issues?[0].body.contains("Please note") == true)
        XCTAssertFalse(issues?[0].body.contains("Thanks!") == true)
    }

    /// The support-tier message `brew doctor` prints on standard output after
    /// the last finding (`cmd/doctor.rb`, `Finding.support_tier_message`) is
    /// merged into the same capture; it is about the configuration, not about
    /// the last warning, and it does not belong to that warning's body.
    func testTheSupportTierMessageAfterTheLastBlockIsNotItsBody() {
        let tier = """
            This is a Tier 2 configuration:
              https://docs.brew.sh/Support-Tiers#tier-2
            You can report issues with Tier 2 configurations to Homebrew/* repositories!
              https://github.com/Homebrew/brew/issues
            Read the above document before opening any issues or PRs.
            """
        let issues = DoctorParser.parse(Self.unlinkedKegs + "\n\n" + tier + "\n")
        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.body.components(separatedBy: "\n").last, "  node")
    }
}
