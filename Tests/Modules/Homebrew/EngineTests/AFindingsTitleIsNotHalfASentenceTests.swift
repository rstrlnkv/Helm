import XCTest
@testable import Module_Homebrew_Engine

/// **brew hard-wraps its findings, and the first physical line is not always a
/// whole sentence.** `DoctorParser` starts the title with the rest of the
/// `Warning:` line and joins the unindented lines after it until the sentence
/// ends (`.`, `!`, `?` or `:`); everything after is the body. For most checks
/// that first line is a sentence; for some it is where brew's heredoc happened
/// to break — and the Health tab draws a closed finding as its title alone, so
/// a title taken from the first physical line alone would be half a sentence
/// that a person reads without a click, with the other half at the top of the
/// body. These cases hold that join.
///
/// Captured on this Mac, Homebrew 7.0.7, 2026-09-29 (`diagnostic.rb`'s sbin
/// check, whose heredoc breaks after «installed»):
///
///     $ env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin HOMEBREW_NO_AUTO_UPDATE=1 \
///           /opt/homebrew/bin/brew doctor > out 2>&1; echo "EXIT=$?"
///     EXIT=1
///
/// The same shape stands in brew's source for at least two more titles
/// (`Some frameworks can be picked up by CMake's build system and will likely`,
/// `A '.pydistutils.cfg' file was found in $HOME, which may cause Python`).
///
/// The check is structural rather than a spelling of the fix: a title ends
/// where brew's sentence ends, and no word of the block is lost between the
/// title and the body.
final class AFindingsTitleIsNotHalfASentenceTests: XCTestCase {

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
}
