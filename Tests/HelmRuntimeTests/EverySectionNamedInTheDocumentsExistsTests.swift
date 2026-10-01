import HelmTestSupport
import XCTest

/// Every § pointer written in the standing documents names a heading that
/// exists, spelled exactly, and `CLAUDE.md` stays inside its byte ceiling.
///
/// **Why this is a test.** `CLAUDE.md` points at the reason for most of its
/// orders with a bare `→` then the sign and a heading of `ARCHITECTURE.md`; the
/// few that point with `→` at a file or a script header are not read here.
/// `EverySectionNamedInTheCodeExistsTests` reads Swift files only and wants a
/// document name before the section sign, so these pointers were read by nothing: a heading
/// renamed in `ARCHITECTURE.md` left an order whose reason was nowhere.
///
/// **Why exact and not by prefix.** The sibling matches a heading as a prefix
/// of whatever follows the section sign, which is right for code that quotes a heading with
/// prose after it, and wrong here: a pointer reading `Release notes` would resolve to a
/// heading `Release`, and one reading `Hosts and SSH` would stay green if that section were
/// renamed `Hosts`, the heading being only a prefix of the pointer's text. A pointer here ends at a terminator — `.`, `,`, `;`, `:`,
/// `)`, `]`, the next §, an arrow or the end of the paragraph, a closing mark
/// (a backtick, quote or asterisk) being allowed between the heading and the
/// terminator — and the text before it has to equal a heading, case included. The price is
/// that prose after a pointer with no punctuation (a pointer followed by a bare word)
/// reads as dead; punctuate it.
///
/// **Why headings come only from outside fenced blocks.** A `# comment` line
/// in a shell block is not a section, and counting it would let a pointer at
/// one resolve.
///
/// **Why the parser is separate from the documents.** Its edge cases — a
/// pointer before each terminator, a heading that is only a prefix of another
/// text, a heading with an em dash or a comma, a pointer wrapped over a line
/// break — are fed to it directly in the fixture tests below, so a parser that
/// stopped handling one fails there whatever the documents happen to hold.
final class EverySectionNamedInTheDocumentsExistsTests: XCTestCase {

    /// The ceiling the owner set for `CLAUDE.md` (15 KB); a sentence added past
    /// it has to take a sentence out or move a story to `ARCHITECTURE.md`.
    static let claudeCeilingBytes = 15_360

    // MARK: - The parser

    enum Parser {
        /// Closing marks a pointer may carry directly after its heading.
        private static let closers: Set<Character> = ["`", "\"", "»", "”", "*", "'"]
        /// Marks that end a pointer.
        private static let terminators: Set<Character> = [".", ",", ";", ":", ")", "]"]

        /// Soft line breaks removed: a newline between two non-blank lines
        /// becomes a space, with a quote marker or list indent dropped. A blank
        /// line stays a paragraph break.
        static func joined(_ text: String) -> String {
            let regex = try! NSRegularExpression(pattern: #"(?<=\S)[ \t]*\n[ \t]*(?:>[ \t]*)?(?=\S)(?![-*+|#][ \t]|\d+\.[ \t]|#)"#)
            return regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        /// Heading texts of a document, outside fenced code, as written.
        static func headings(in text: String) -> [String] {
            var inFence = false
            var out: [String] = []
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
                guard !inFence, line.hasPrefix("#") else { continue }
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { out.append(title) }
            }
            return out.sorted { $0.count > $1.count }
        }

        /// The heading a pointer's text names, or nil. `rest` is everything
        /// after the section sign; a match is a heading followed by an optional closing
        /// mark and then a terminator, whitespace before another § or an
        /// arrow, or the end of the text.
        static func resolve(_ rest: String, headings: [String]) -> String? {
            var text = Substring(rest.drop(while: { $0 == " " || $0 == "\t" }))
            if let first = text.first, "«\"“`*".contains(first) { text = text.dropFirst() }
            for heading in headings where text.hasPrefix(heading) {
                var after = text.dropFirst(heading.count)
                if let c = after.first, closers.contains(c) { after = after.dropFirst() }
                guard let next = after.first else { return heading }
                if terminators.contains(next) || next == "\n" { return heading }
                let trimmed = after.drop(while: { $0 == " " || $0 == "\t" })
                if trimmed.isEmpty || trimmed.hasPrefix("\u{A7}") || trimmed.hasPrefix("→") { return heading }
            }
            return nil
        }

        /// What follows each § of a text, up to the next § — so a pointer
        /// list `sign A, sign B.` gives two, and each carries its own terminator.
        static func tails(of text: String) -> [String] {
            let parts = text.components(separatedBy: "\u{A7}")
            return parts.dropFirst().map { $0 }
        }

        struct Named { let document: String; let rest: String }

        /// Pointers that name their document: the architecture document name and the sign,
        /// a backticked document name and the sign, the bare name and the sign. Text is joined first.
        static func named(in text: String) -> [Named] {
            let joinedText = joined(text) as NSString
            let regex = try! NSRegularExpression(
                pattern: #"\b(ARCHITECTURE|CLAUDE)(?:\.md)?`?[ \t]*\x{A7}"#)
            return regex.matches(in: joinedText as String,
                                 range: NSRange(location: 0, length: joinedText.length)).map { m in
                let end = m.range.location + m.range.length
                return Named(document: joinedText.substring(with: m.range(at: 1)),
                             rest: joinedText.substring(from: end))
            }
        }

        /// The bare pointers of `CLAUDE.md`: every § after the first arrow of
        /// a line. Returns the pointers and the lines carrying a § outside
        /// that shape.
        static func arrowPointers(in claude: String) -> (pointers: [String], stray: [String]) {
            var pointers: [String] = []
            var stray: [String] = []
            for line in claude.components(separatedBy: "\n") where line.contains("\u{A7}") {
                guard let arrow = line.range(of: "→") else { stray.append(line); continue }
                let after = String(line[arrow.upperBound...])
                if line[..<arrow.lowerBound].contains("\u{A7}") { stray.append(line) }
                pointers += tails(of: after)
            }
            return (pointers, stray)
        }
    }

    // MARK: - The documents

    private static let standing = ["ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md"]

    /// The one line of `CLAUDE.md` that mentions the section sign as notation and names no
    /// section: the header explaining the arrow.
    private static let notation = "\u{A7} X is a heading"

    func testEveryBarePointerOfClaudeNamesAHeadingOfArchitecture() throws {
        let claude = try RepoSource.text(of: "CLAUDE.md")
        let headings = Parser.headings(in: try RepoSource.text(of: "ARCHITECTURE.md"))
        XCTAssertGreaterThan(headings.count, 20, "ARCHITECTURE.md headings were not read")

        let read = Parser.arrowPointers(in: claude)
        XCTAssertGreaterThan(read.pointers.count, 40,
            "only \(read.pointers.count) bare pointers read from CLAUDE.md — the parser reads nothing and every verdict is over no text")

        let stray = read.stray.filter { !$0.contains(Self.notation) }
        XCTAssertTrue(stray.isEmpty,
            "a section sign outside the arrow shape is read by nothing:\n\(stray.joined(separator: "\n"))")

        let dead = read.pointers.filter { Parser.resolve($0, headings: headings) == nil }
        XCTAssertTrue(dead.isEmpty, """
            \(dead.count) pointer(s) of CLAUDE.md name no heading of ARCHITECTURE.md exactly:
            \(dead.map { "\u{A7}" + $0.prefix(50) }.joined(separator: "\n"))
            """)
    }

    func testEveryNamedPointerOfTheStandingDocumentsNamesAHeading() throws {
        let headingsByDocument = [
            "ARCHITECTURE": Parser.headings(in: try RepoSource.text(of: "ARCHITECTURE.md")),
            "CLAUDE": Parser.headings(in: try RepoSource.text(of: "CLAUDE.md")),
        ]
        var read = 0
        var dead: [String] = []
        for file in Self.standing {
            for pointer in Parser.named(in: try RepoSource.text(of: file)) {
                read += 1
                if Parser.resolve(pointer.rest, headings: headingsByDocument[pointer.document] ?? []) == nil {
                    dead.append("\(file) — \(pointer.document) \u{A7}\(pointer.rest.prefix(50))")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(read, 1,
            "no named pointer read from the four documents — ARCHITECTURE.md carries at least one")
        XCTAssertTrue(dead.isEmpty, "\(dead.count) dead pointer(s):\n\(dead.joined(separator: "\n"))")
    }

    func testClaudeStaysInsideItsCeiling() throws {
        let size = try RepoSource.text(of: "CLAUDE.md").utf8.count
        XCTAssertGreaterThan(size, 4_000,
            "CLAUDE.md is \(size) bytes — an emptied file is under every ceiling, and the rules are gone")
        XCTAssertLessThanOrEqual(size, Self.claudeCeilingBytes,
            "CLAUDE.md is \(size) bytes, ceiling \(Self.claudeCeilingBytes) — move a story to ARCHITECTURE.md")
    }

    // MARK: - Parser fixtures

    private let sample = ["Release", "The updater", "Helm — architecture",
                          "What not to do, and what breaks if you do"]

    func testAPointerBeforeEachTerminatorResolves() {
        for tail in [" Release.", " Release,", " Release;", " Release)", " Release:",
                     " Release", " Release\n", " `Release`.", " \"Release\")", " Release \u{A7}", " Release →", " Release]"] {
            XCTAssertEqual(Parser.resolve(tail, headings: sample), "Release", "tail \(tail.debugDescription)")
        }
    }

    func testAPointerThatIsOnlyAPrefixOfAHeadingOrOfProseIsDead() {
        XCTAssertNil(Parser.resolve(" Releases.", headings: sample))
        XCTAssertNil(Parser.resolve(" Release notes.", headings: sample))
        XCTAssertNil(Parser.resolve(" release.", headings: sample), "case is part of the name")
        XCTAssertNil(Parser.resolve(" The upd.", headings: sample))
        XCTAssertNil(Parser.resolve(" No such heading.", headings: sample))
    }

    func testAHeadingWithADashOrACommaResolvesWhole() {
        XCTAssertEqual(Parser.resolve(" Helm — architecture.", headings: sample), "Helm — architecture")
        XCTAssertEqual(Parser.resolve(" What not to do, and what breaks if you do)", headings: sample),
                       "What not to do, and what breaks if you do")
        XCTAssertNil(Parser.resolve(" What not to do.", headings: sample))
    }

    func testAPointerWrappedOverALineBreakIsRead() {
        let wrapped = "see (CLAUDE.md\n\u{A7} The updater). Then\nmore.\n"
        let found = Parser.named(in: wrapped)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(Parser.resolve(found.first?.rest ?? "", headings: sample), "The updater")

        let wrappedHeading = Parser.named(in: "`ARCHITECTURE.md` \u{A7} Helm —\narchitecture, the rest")
        XCTAssertEqual(Parser.resolve(wrappedHeading.first?.rest ?? "", headings: sample), "Helm — architecture")

        let quoted = Parser.named(in: "> CLAUDE.md \u{A7}\n> What not to do, and what breaks if you do.")
        XCTAssertEqual(Parser.resolve(quoted.first?.rest ?? "", headings: sample),
                       "What not to do, and what breaks if you do")
    }

    func testAParagraphBreakIsNotJoined() {
        let found = Parser.named(in: "CLAUDE.md \u{A7} Release\n\nThe updater is next.")
        XCTAssertEqual(Parser.resolve(found.first?.rest ?? "", headings: sample), "Release")
    }

    func testHeadingsInsideAFenceAreNotSections() {
        let text = "# Real\n```sh\n# Comment\n```\n## Also real\n"
        XCTAssertEqual(Set(Parser.headings(in: text)), ["Real", "Also real"])
    }

    func testAnArrowListGivesOnePointerPerSection() {
        let line = "- Order → \u{A7} Release, \u{A7} The updater.\n- Notation: \u{A7} X is a heading.\n- Bad \u{A7} Release → \u{A7} Release."
        let read = Parser.arrowPointers(in: line)
        XCTAssertEqual(read.pointers.count, 3)
        XCTAssertEqual(read.stray.count, 2)
        XCTAssertEqual(read.pointers.map { Parser.resolve($0, headings: sample) },
                       ["Release", "The updater", "Release"])
    }
}
