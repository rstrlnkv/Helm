import XCTest
@testable import Module_Homebrew_Engine

/// **A title joined across wrapped lines must stop where brew's sentence stops,
/// including when brew's first line carries no full stop at all.** `DoctorParser`
/// joins unindented lines onto the title until one ends with `.`, `!`, `?` or
/// `:`. That is right for brew's own hard-wrapped heredocs, and wrong for the
/// two shapes below, where what follows the first line is not the rest of its
/// sentence.
///
/// 1. brew's crash report. Any exception raised inside a check lands in
///    `brew.rb`'s last rescue: `onoe e` prints `Error: <message>` — a Ruby
///    message, which has no full stop — then the cleaned backtrace, one frame
///    per line at the left margin, then a closing notice. Captured on this Mac,
///    Homebrew 7.0.7, 2026-09-29, read-only (`public_send` of a helper that
///    takes an argument is the cheapest way to make a check raise without
///    touching anything):
///
///        $ env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 \
///              /opt/homebrew/bin/brew doctor user_tilde > out 2>&1; echo "EXIT=$?"
///        EXIT=1                                  (571 bytes)
///
///    The exit is non-zero and a block is read, so the engine hands this on as
///    a finding rather than nil — which is right. A join that knew only about
///    terminal punctuation would make the title the message, every backtrace
///    frame and the notice, in one line; the join stops at a source location
///    (`DoctorParser.isBacktraceFrame`), so the frames and the notice are the
///    body's.
///
/// 2. A first sentence that ends mid-line. `check_for_pydistutils_cfg_in_home`
///    (`diagnostic.rb`) wraps as «…which may cause Python» / «builds to fail.
///    See:», and a join that took the whole line would take «See:» along. The
///    title ends inside that line, at «fail.», and «See:» opens the body above
///    the links it introduces. Composed from brew's source, not captured:
///    producing it would mean creating a file in the home folder.
final class ATitleDoesNotRunIntoWhatFollowsItTests: XCTestCase {

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

    /// The capture is the one described above, byte for byte in length, so a
    /// later edit to the literal cannot quietly turn it into a different case.
    func testTheCrashFixtureIsTheCapture() {
        XCTAssertEqual(Self.crashed.utf8.count, 571)
    }

    /// Structural: no line of the block that is a source location may be part
    /// of the title. Before the title was joined this held for free; a join
    /// that knows only about terminal punctuation takes the whole backtrace.
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

    /// Structural: a joined title is one sentence — it does not carry a second
    /// one that begins after a full stop in the middle of a wrapped line —
    /// and the cut moves words rather than losing them: what the title gives
    /// up opens the body, so title and body together are still every word of
    /// the block. A cut that dropped the rest of the line (`See:`, the word
    /// that introduces the links) passed the first half alone.
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
