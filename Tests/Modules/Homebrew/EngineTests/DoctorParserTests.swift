import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorParser.parse` against `brew doctor`'s real answer.
///
/// The fixture is captured verbatim from `brew doctor`'s standard error on a
/// real Mac (exit 1, 1194 bytes). It holds a tap's `postflight` deprecation
/// warning three times, brew's own aside to the reader *between* the second and
/// third repeat, and «Some installed formulae are deprecated or disabled»
/// naming `periphery` on its own indented line.
final class DoctorParserTests: XCTestCase {

    /// Byte-for-byte what brew printed, shared so no two cases disagree about
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

    /// Three identical `postflight` blocks read back as one entry. The aside
    /// between the second and third repeat must stay out of their bodies, or the
    /// copies differ and do not collapse; this one equality catches both.
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

    /// A body line naming a path is kept exactly as brew printed it, leading
    /// spaces included: this module does not re-spell somebody's paths.
    func testAPathInABodyLineSurvivesVerbatim() {
        let issues = DoctorParser.parse(Self.capturedOutput)
        XCTAssertEqual(
            issues?.first?.body.components(separatedBy: "\n").last,
            "  /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18")
    }

    /// `Error:` and `Warning:` map to distinct severities. The `Error:` input is
    /// a small composed string; the real capture has none.
    func testErrorIsDangerAndWarningIsCaution() {
        let text = "Error: Your Command Line Tools are outdated.\nRun `xcode-select --install`.\n"
        let issues = DoctorParser.parse(text)

        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.severity, .danger)
        XCTAssertEqual(issues?.first?.title, "Your Command Line Tools are outdated.")

        let warningText = "Warning: Something is off.\nA detail.\n"
        XCTAssertEqual(DoctorParser.parse(warningText)?.first?.severity, .caution)
    }

    /// Real output with no `Warning:`/`Error:` line (brew's aside, lifted from
    /// the fixture) reads as "doctor ran and found nothing": an empty array.
    func testOutputWithNoWarningOrErrorLineIsAnEmptyArray() {
        let prose = """
            Please note that these warnings are just used to help the Homebrew maintainers
            with debugging if you file an issue. If everything you use Homebrew for is
            working fine: please don't worry or file an issue; just ignore this. Thanks!
            """

        XCTAssertEqual(DoctorParser.parse(prose), [])
    }

    /// Empty input is nil: the tool said nothing, which is not "the tool ran and
    /// the machine is clean". Read wrong, a refused or never-run query reads as a
    /// healthy machine.
    func testEmptyInputIsNil() {
        XCTAssertNil(DoctorParser.parse(""))
    }

    // MARK: - A block is kept whole

    /// brew's own text for these three, assembled from `Finding#to_s` and the
    /// sources that name them (`diagnostic.rb`: `check_for_stray_dylibs`,
    /// `check_for_unlinked_but_not_keg_only`, `check_user_path_1`; `cmd/doctor.rb`
    /// for the aside and the support-tier message). Each has a blank line and
    /// then an unindented line *inside* the one finding. The file and package
    /// names are invented; the sentences are brew's.
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

    /// The dylibs warning reaches the person with its list: the file names a
    /// person would delete sit after a blank line inside the body.
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

    /// brew's aside to the reader is a frame around the findings and stays out
    /// of every body, wherever it lands. **The input is composed**: brew prints
    /// the aside once, before its first warning. The scan stops at a frame line
    /// whatever its place, so after a long block whose body runs on past blank
    /// lines the aside is not the body's last paragraph.
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

    // MARK: - A findings's title is a whole sentence

    /// **brew hard-wraps its findings, and the first physical line is not always a
    /// whole sentence.** `DoctorParser` starts the title with the rest of the
    /// `Warning:` line and joins the unindented lines after it until the sentence
    /// ends (`.`, `!`, `?` or `:`); everything after is the body. The Health tab
    /// draws a closed finding as its title alone, so a title cut at the first
    /// physical line would be half a sentence.
    ///
    /// Captured from `brew doctor` (`diagnostic.rb`'s sbin check, whose heredoc
    /// breaks after «installed»):
    ///
    ///     $ env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin HOMEBREW_NO_AUTO_UPDATE=1 \
    ///           /opt/homebrew/bin/brew doctor > out 2>&1; echo "EXIT=$?"
    ///     EXIT=1
    ///
    /// The check is structural rather than a spelling of the fix: a title ends
    /// where brew's sentence ends, and no word of the block is lost between the
    /// title and the body.
    private static let captured = """
        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!

        Warning: /usr/bin occurs before /opt/homebrew/bin in your PATH.
        This means that system-provided programs will be used instead of those
        provided by Homebrew.

        The following tools exist at both paths:
          openssl
          pip3
          pp
          python3

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/bin:$PATH' >> ~/.zshrc

        Warning: Homebrew's "sbin" was not found in your PATH but you have installed
        formulae that put executables in /opt/homebrew/sbin.

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/sbin:$PATH' >> ~/.zshrc


        """

    private func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: \.isWhitespace)
    }

    func testEveryTitleEndsWhereBrewsSentenceEnds() throws {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.captured))
        XCTAssertEqual(issues.count, 2, "the capture holds two findings")
        for issue in issues {
            let last = issue.title.last
            XCTAssertTrue(last.map { ".!?:".contains($0) } ?? false,
                          "a closed finding reads as half a sentence: «\(issue.title)» — "
                          + "and its body opens on the rest: «\(issue.body.prefix(60))…»")
        }
    }

    /// The other half of the structure: whatever moves from the body into the
    /// title, nothing of brew's text is dropped or said twice.
    func testTitleAndBodyTogetherAreTheWholeBlock() throws {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.captured))
        let sbin = try XCTUnwrap(issues.last)
        let block = """
            Homebrew's "sbin" was not found in your PATH but you have installed
            formulae that put executables in /opt/homebrew/sbin.

            Consider setting your PATH for example like so:
              echo 'export PATH=/opt/homebrew/sbin:$PATH' >> ~/.zshrc
            """
        XCTAssertEqual(words(sbin.title) + words(sbin.body), words(block))
    }

    // MARK: - A title does not run into what follows it

    /// **A title joined across wrapped lines must stop where brew's sentence stops,
    /// including when brew's first line carries no full stop at all.** Two shapes
    /// where what follows the first line is not the rest of its sentence:
    ///
    /// 1. brew's crash report. An exception inside a check lands in `brew.rb`'s
    ///    last rescue: `Error: <message>` (a Ruby message, no full stop), the
    ///    backtrace one frame per line at the left margin, then a closing notice.
    ///    Captured read-only (`public_send` of a helper that takes an argument
    ///    makes a check raise without touching anything):
    ///
    ///        $ env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 \
    ///              /opt/homebrew/bin/brew doctor user_tilde > out 2>&1; echo "EXIT=$?"
    ///        EXIT=1                                  (571 bytes)
    ///
    ///    The engine hands this on as a finding, rightly. The join stops at a
    ///    source location (`DoctorParser.isBacktraceFrame`), so the frames and the
    ///    notice are the body's.
    ///
    /// 2. A first sentence that ends mid-line. `check_for_pydistutils_cfg_in_home`
    ///    wraps as «…which may cause Python» / «builds to fail. See:». The title
    ///    ends at «fail.», and «See:» opens the body above the links it
    ///    introduces. Composed from brew's source: producing it would mean
    ///    creating a file in the home folder.
    private static let crashed = """
        Error: wrong number of arguments (given 0, expected 1)
        /opt/homebrew/Library/Homebrew/diagnostic.rb:92:in 'Homebrew::Diagnostic::Checks#user_tilde'
        /opt/homebrew/Library/Homebrew/cmd/doctor.rb:67:in 'Kernel#public_send'
        /opt/homebrew/Library/Homebrew/cmd/doctor.rb:67:in 'block in Homebrew::Cmd::Doctor#run'
        /opt/homebrew/Library/Homebrew/cmd/doctor.rb:60:in 'Array#each'
        /opt/homebrew/Library/Homebrew/cmd/doctor.rb:60:in 'Homebrew::Cmd::Doctor#run'
        /opt/homebrew/Library/Homebrew/brew.rb:147:in '<main>'
        Please report this issue:
          https://docs.brew.sh/Troubleshooting

        """

    private static let pydistutils = """
        Warning: A '.pydistutils.cfg' file was found in $HOME, which may cause Python
        builds to fail. See:
          https://bugs.python.org/issue6138
          https://bugs.python.org/issue4655

        """

    /// The capture is the one described above, byte for byte in length, so an
    /// edit to the literal cannot quietly turn it into a different case.
    func testTheCrashFixtureIsTheCapture() {
        XCTAssertEqual(Self.crashed.utf8.count, 571)
    }

    /// Structural: no line of the block that is a source location may be part
    /// of the title.
    func testABacktraceIsNotPartOfTheTitle() throws {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.crashed))
        let crash = try XCTUnwrap(issues.first)
        XCTAssertEqual(crash.severity, .danger)
        let frames = Self.crashed.components(separatedBy: "\n").filter { $0.contains(".rb:") }
        XCTAssertEqual(frames.count, 6, "the capture holds six frames")
        for frame in frames {
            XCTAssertFalse(crash.title.contains(frame),
                           "a backtrace frame was read as the title's sentence: «\(crash.title)»")
        }
    }

    /// Structural: a joined title is one sentence, and the cut moves words
    /// rather than losing them: what the title gives up opens the body, so title
    /// and body together are still every word of the block.
    func testAJoinedTitleHoldsOneSentence() throws {
        let issues = try XCTUnwrap(DoctorParser.parse(Self.pydistutils))
        let issue = try XCTUnwrap(issues.first)
        let title = issue.title
        XCTAssertNil(title.range(of: #"[.!?] \S"#, options: .regularExpression),
                     "the title runs past the end of brew's first sentence: «\(title)»")
        let words: (String) -> [Substring] = { $0.split(whereSeparator: \.isWhitespace) }
        let block = String(Self.pydistutils.dropFirst("Warning:".count))
        XCTAssertEqual(words(title) + words(issue.body), words(block),
                       "the cut lost or moved words: title «\(title)», body «\(issue.body)»")
    }
}
