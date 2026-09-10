import HelmTestSupport
import XCTest

/// Every `ARCHITECTURE.md` § and `CLAUDE.md` § pointer in the source names a
/// heading its document still has.
///
/// **Why this is a test.** `ARCHITECTURE.md` was reorganised and the pointers
/// into it were not: before this guard existed, most of its citations named
/// headings the document no longer had, and following one arrived nowhere.
/// Nothing failed, because a comment is not compiled and a document is not
/// parsed — the two halves of one sentence lived in two files with nothing
/// between them. `DocumentsNameTheTreeTests` reads the other direction, names
/// the documents use that the tree must still have; this reads names the
/// *code* uses to point back into the documents.
///
/// **Why it reads the code and not the document.** The document is allowed to
/// grow a section nobody points at yet; the code is not allowed to point at a
/// section nobody wrote. So the direction of the check is from the pointer to
/// the heading, and a heading with no pointer is not a finding.
///
/// **Why both documents.** An early reader written for this repair covered
/// `ARCHITECTURE.md` alone and reported nothing dead — over a tree that also
/// carries pointers into `CLAUDE.md`, left unread entirely. Pointers land in
/// both documents, so a guard built to watch one is blind to every pointer
/// aimed at the other, whichever one that is; `testTheCanaryReadsBothTreesAndBothDocuments`
/// is what pins this, asserting pointers into each document separately so a
/// reader that silently stopped covering one of them fails there before it
/// can fail anywhere else.
///
/// **Why both spellings.** Nothing here stops a comment from writing the
/// `.md`-less form of either document's name right before `§`, and a guard
/// that only recognises the spelling everyone happened to use so far accepts
/// the next writer's pointer unread — no such pointer survives in this tree
/// today, and that is exactly why one has to be accepted rather than assumed
/// away.
///
/// **Why lines are joined before matching.** Three readers were written for
/// the plan this test comes from, and each found more pointers than the last:
/// a line-by-line reader missed a `§` that opened the next line, a second
/// missed the spelling without `.md`, and a third missed the pointers whose
/// document name ends one `///` line and whose `§` begins the next —
/// `Sources/HelmRuntime/LockedMemo.swift` and `Sources/Modules/VPN/Engine/VPNEngine.swift`
/// among them, both citing `CLAUDE.md` § What not to do, and what breaks if
/// you do. A Swift string literal split by `+` concatenation is a fourth
/// continuation shape with no comment marker anywhere near it:
/// `Tests/HelmAppTests/PanelBarsCarryNoLifetimeTests.swift` closes one line
/// with the document name, `§`, and an opening quote, then reopens the next
/// with `+ "` and the heading text. An independent reader that did not join
/// that boundary reported this exact, real pointer as the only dead one in
/// the tree — checked by hand against `ARCHITECTURE.md`'s own heading before
/// this guard existed to say so on its own.
///
/// **Why headings are matched by prefix and not cut at the first comma.**
/// `CLAUDE.md`'s own headings carry commas and em dashes — `## What not to
/// do, and what breaks if you do` is pointed at from dozens of call sites —
/// so a name is not "the text up to the first punctuation mark a heading
/// cannot contain"; there is no such mark a heading is guaranteed to lack. It
/// is "the document's actual heading text", tried longest heading first so a
/// short heading that is also a prefix of a longer one never wins a match a
/// longer one deserved.
///
/// **Its cost.** SwiftPM has no declared-inputs list to read a cost from, so
/// the command that answers it lives here instead of a number that would
/// simply go stale like any other count written into prose: `swift test
/// --filter 'EverySectionNamedInTheCodeExistsTests' 2>&1 | command grep
/// 'EverySectionNamedInTheCodeExistsTests.*passed'`. Run when this was
/// written, it printed `testEverySectionThePointersNameExists]' passed
/// (0.364 seconds)`, `testTheCanaryReadsBothTreesAndBothDocuments]' passed
/// (0.313 seconds)` and `Test Suite 'EverySectionNamedInTheCodeExistsTests'
/// passed` — re-run the command rather than trusting those numbers once the
/// tree has grown.
final class EverySectionNamedInTheCodeExistsTests: XCTestCase {

    /// A pointer's own shape: the document's bare name, an optional `.md`,
    /// then `§`. Group 1 is the document name alone, which is also the key
    /// `headings(of:)` is read under.
    private static let pointer = try! NSRegularExpression(
        pattern: #"\b(ARCHITECTURE|CLAUDE)(?:\.md)?[ \t]*§[ \t]*"#)

    /// A Swift string literal split across lines by `+` concatenation: a
    /// closing quote, a line break and its indentation, then the reopening
    /// `+ "`. Dropping the whole boundary joins the two literal halves into
    /// one uninterrupted run of characters, which is what a pointer split
    /// this way needs to read as one thing again.
    private static let stringConcatenationJoin = try! NSRegularExpression(
        pattern: #""\n[ \t]*\+[ \t]*""#)

    /// A `///` or `//` comment that wraps: a line break, its indentation,
    /// two or three slashes and at most one space after them, collapsed to a
    /// single space — so a document name ending one comment line and a `§`
    /// starting the next read as neighbours, the way the sentence around them
    /// always meant them to.
    private static let commentContinuationJoin = try! NSRegularExpression(
        pattern: #"\n[ \t]*/{2,3}[ \t]?"#)

    /// Both joins, string concatenation before comment wrapping — the two
    /// patterns touch different characters (a quote versus a slash) so the
    /// order between them does not matter, but each has to run over the
    /// whole file, not line by line, or a boundary spanning three or more
    /// lines only gets half-joined.
    private static func joined(_ text: String) -> String {
        let afterConcat = Self.stringConcatenationJoin.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return Self.commentContinuationJoin.stringByReplacingMatches(
            in: afterConcat, range: NSRange(afterConcat.startIndex..., in: afterConcat), withTemplate: " ")
    }

    /// A document's headings, lowercased and longest first. Longest first is
    /// what lets a short heading that is also a prefix of a longer one never
    /// win a match the longer heading deserved.
    private func headings(of document: String) throws -> [String] {
        try RepoSource.lines(of: document)
            .filter { $0.hasPrefix("#") }
            .map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased() }
            .sorted { $0.count > $1.count }
    }

    /// Every `.swift` file of the package, source and test alike.
    private func swiftFiles() throws -> [String] {
        try RepoSource.swiftFiles(under: "Sources") + RepoSource.swiftFiles(under: "Tests")
    }

    private struct Found {
        let file: String
        let document: String
        let alive: Bool
        let excerpt: String
    }

    /// Every pointer in the tree, joined and matched against the heading list
    /// of the document it names.
    private func pointers() throws -> [Found] {
        let headingsByDocument: [String: [String]] = [
            "ARCHITECTURE": try headings(of: "ARCHITECTURE.md"),
            "CLAUDE": try headings(of: "CLAUDE.md"),
        ]
        var out: [Found] = []
        for relative in try swiftFiles() {
            let raw: String
            do {
                raw = try RepoSource.text(of: relative)
            } catch {
                XCTFail("\(relative) could not be read as text: \(error)")
                continue
            }
            let text = Self.joined(raw) as NSString
            let whole = NSRange(location: 0, length: text.length)
            for match in Self.pointer.matches(in: text as String, range: whole) {
                let document = text.substring(with: match.range(at: 1))
                let end = match.range.location + match.range.length
                let windowLength = max(0, min(220, text.length - end))
                var rest = text.substring(with: NSRange(location: end, length: windowLength))
                // An opening quote of some kind — «, ", ` or * — sits between
                // `§` and the heading about as often as nothing does; strip at
                // most one, and any whitespace on either side of it.
                rest = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
                if let first = rest.first, "«\"`*".contains(first) {
                    rest.removeFirst()
                    rest = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
                }
                let candidate = rest.lowercased()
                let heading = headingsByDocument[document]?.first { candidate.hasPrefix($0) }
                out.append(Found(file: relative, document: document, alive: heading != nil,
                                 excerpt: String(candidate.prefix(60))))
            }
        }
        return out
    }

    // MARK: - The checks

    /// The canary: a guard reading nothing is a guard that is green over
    /// nothing, and nothing below it would ever be able to tell the
    /// difference on its own.
    func testTheCanaryReadsBothTreesAndBothDocuments() throws {
        let files = try swiftFiles()
        XCTAssertGreaterThan(files.count, 200,
            "only \(files.count) Swift files — the walk found nothing and every verdict below is over no text")

        let architecture = try headings(of: "ARCHITECTURE.md")
        XCTAssertGreaterThan(architecture.count, 20,
            "only \(architecture.count) ARCHITECTURE.md headings — the document was not read")
        let claude = try headings(of: "CLAUDE.md")
        XCTAssertGreaterThan(claude.count, 3,
            "only \(claude.count) CLAUDE.md headings — the document was not read")

        let found = try pointers()
        XCTAssertGreaterThan(found.filter { $0.document == "ARCHITECTURE" }.count, 20,
            "no pointer into ARCHITECTURE.md was found — a guard finding nothing is green over nothing")
        XCTAssertGreaterThan(found.filter { $0.document == "CLAUDE" }.count, 20,
            "no pointer into CLAUDE.md was found — a guard finding nothing is green over nothing")
    }

    func testEverySectionThePointersNameExists() throws {
        let dead = try pointers().filter { !$0.alive }
        XCTAssertTrue(dead.isEmpty, """
            \(dead.count) pointer(s) name a section its document does not have:
            \(dead.map { "\($0.file) — \($0.document) § \($0.excerpt)" }.joined(separator: "\n"))
            Either the section is owed to the document, or the pointer belongs to a lesson \
            and goes to role knowledge — the pointer is not deleted to make this pass.
            """)
    }
}
