import HelmTestSupport
import XCTest

/// Every file `SwiftSource.code` reads back holds as many lines as the file
/// itself — the promise `code`'s own doc comment makes («every newline kept
/// where it was»), and the one a line number reported through
/// `SwiftSource.callSites`, or read straight off `SwiftSource.code(under:)`
/// by a caller such as `PortsAtConstruction`, depends on without saying so.
///
/// **Why this is a test.** `skip(to:escaping:keeping:)`'s escape branch hands
/// two characters to `delimiter(2, keeping: keeping)`, which drops both when the
/// text is not kept: right for an escaped quote, wrong for a `\` line
/// continuation inside an ordinary `"""` literal, whose escaped character *is*
/// the newline. Until the branch put that newline back, `code` came back one
/// line short from there to the end of the file. `command grep -rhE
/// '\\$' Tests | wc -l` counts lines shaped that way, along with the odd
/// comment that ends in `\`; a raw `#"""` literal never reaches the branch
/// at all, because its own `skip` call passes `escaping: false`. The model
/// for this guard is the identical per-file check
/// `NoDocCommentIsDetachedTests` already runs for `SwiftSource.uncommented`;
/// this is the same proof for `code`.
final class CodeKeepsAsManyLinesAsTheFileTests: XCTestCase {

    /// Every `.swift` file under `directory`, read as `code` reads it — no
    /// assertion here, so the canary below can count files without also
    /// being the guard: a shared asserting helper prints every drifting
    /// file twice when both tests call it.
    private func files(under directory: String) throws -> [SwiftSource.Read] {
        try SwiftSource.code(under: directory)
    }

    // MARK: - The canary

    /// A guard reading nothing is green over nothing. Floors match the ones
    /// `NoDocCommentIsDetachedTests` already keeps for the same two trees.
    func testTheCanaryWalksBothTreesInFull() throws {
        let sources = try files(under: "Sources")
        XCTAssertGreaterThanOrEqual(sources.count, 400,
            "only \(sources.count) Sources files — the walk found far fewer than the tree has")
        let tests = try files(under: "Tests")
        XCTAssertGreaterThanOrEqual(tests.count, 800,
            "only \(tests.count) Tests files — the walk found far fewer than the tree has")
    }

    // MARK: - The guard

    /// Checked per file against `RepoSource.lines` — an unreadable file is
    /// not skipped, since `RepoSource.lines` throws and this does not catch.
    func testEveryFileKeepsItsLineCountUnderCode() throws {
        for directory in ["Sources", "Tests"] {
            for read in try files(under: directory) {
                let raw = try RepoSource.lines(of: read.path)
                let masked = read.text.components(separatedBy: "\n")
                XCTAssertEqual(raw.count, masked.count,
                    "\(read.path): raw has \(raw.count) line(s), code(_:) reads \(masked.count) — "
                    + "the reading drifted and every line number below it would be a guess")
            }
        }
    }

    // MARK: - The fixture

    /// The exact shape the defect needed: an ordinary `"""` literal, a `\`
    /// line continuation inside it, and code after it whose line number must
    /// not move. Built with explicit `\n`/`\\` escapes in a single-line
    /// literal rather than written as a nested `"""` block, because a nested
    /// triple-quoted literal would let *this* file's own compiler collapse
    /// the continuation before `SwiftSource.code` ever saw it.
    func testALineContinuationInATripleQuotedLiteralKeepsItsLine() {
        let source = "let s = \"\"\"\nfirst \\\nsecond\n\"\"\"\nlet after = 1\n"
        let raw = source.components(separatedBy: "\n")
        let masked = SwiftSource.code(source).components(separatedBy: "\n")
        XCTAssertEqual(masked.count, raw.count,
            "code(_:) dropped a line: raw has \(raw.count) line(s), the masked reading has "
            + "\(masked.count) — a `\\` line continuation must keep its newline even when the "
            + "literal's body is blanked")
    }

    /// The other edge of the same branch: a `\` as the very last character of
    /// the input, inside a literal that never closes. The branch looks one
    /// character ahead to ask whether a newline follows, and that look must
    /// stop at the end of the input. No file in the tree ends this way, which
    /// is why the per-file walk above cannot see this edge and a fixture has
    /// to — without the bound, reading past the end traps the whole test
    /// process rather than failing one assertion.
    func testABackslashEndingTheInputInsideALiteralIsReadWithoutTrapping() {
        for source in ["let s = \"\"\"\nabc \\", "let s = \"abc \\"] {
            XCTAssertEqual(SwiftSource.code(source).components(separatedBy: "\n").count,
                           source.components(separatedBy: "\n").count,
                           "code(_:) misread an input ending in `\\` inside a literal: «\(source)»")
        }
    }
}
