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

    /// The one line of `CLAUDE.md` that mentions the section sign as notation and names no
    /// section: the header explaining the arrow.
    private static let notation = "\u{A7} X is a heading"

    func testEveryBarePointerOfClaudeNamesAHeadingOfArchitecture() throws {
        let claude = try RepoSource.text(of: "CLAUDE.md")
        let headings = try StandingDocuments.headings(of: "ARCHITECTURE")
        XCTAssertGreaterThan(headings.count, 20, "the hub's and its pages' headings were not read")

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
            "ARCHITECTURE": try StandingDocuments.headings(of: "ARCHITECTURE"),
            "CLAUDE": try StandingDocuments.headings(of: "CLAUDE"),
        ]
        var read = 0
        var dead: [String] = []
        for file in StandingDocuments.all() {
            for pointer in Parser.named(in: try RepoSource.text(of: file)) {
                read += 1
                if Parser.resolve(pointer.rest, headings: headingsByDocument[pointer.document] ?? []) == nil {
                    dead.append("\(file) — \(pointer.document) \u{A7}\(pointer.rest.prefix(50))")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(read, 1,
            "no named pointer read from the standing documents — ARCHITECTURE.md carries at least one")
        XCTAssertTrue(dead.isEmpty, "\(dead.count) dead pointer(s):\n\(dead.joined(separator: "\n"))")
    }

    func testClaudeStaysInsideItsCeiling() throws {
        let size = try RepoSource.text(of: "CLAUDE.md").utf8.count
        XCTAssertGreaterThan(size, 4_000,
            "CLAUDE.md is \(size) bytes — an emptied file is under every ceiling, and the rules are gone")
        XCTAssertLessThanOrEqual(size, Self.claudeCeilingBytes,
            "CLAUDE.md is \(size) bytes, ceiling \(Self.claudeCeilingBytes) — move a story to ARCHITECTURE.md")
    }

    // MARK: - The pages of the wiki
    //
    // `ARCHITECTURE.md` is a hub; each subject lives on a page of its own in the
    // flat `Architecture/` directory. These checks list that directory
    // themselves and read the hub's links with their own pattern, so a resolver
    // that forgot a page, or a hub that forgot one, cannot make them agree by
    // reading the same wrong list twice.

    /// File names (`Localization.md`) of `Architecture/*.md`, by directory listing.
    private func pagesOnDisk() throws -> [String] {
        let dir = RepoSource.root.appendingPathComponent("Architecture")
        // A missing directory is "no page", an assertion's business, not a thrown error.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
    }

    private func pageText(_ file: String) throws -> String {
        try RepoSource.text(of: "Architecture/" + file)
    }

    /// `(text, file)` of every hub line shaped `- [H1](Architecture/File.md) — purpose`.
    /// `rest` is the text of the line after the link, the purpose and its `\u{A7}` pointers.
    private func hubLinks() throws -> [(text: String, file: String, rest: String)] {
        let hub = try RepoSource.text(of: "ARCHITECTURE.md")
        let regex = try NSRegularExpression(
            pattern: #"^- \[([^\]]+)\]\(Architecture/([A-Za-z0-9]+\.md)\)([ \t]\x{2014} \S[^\n]*)"#,
            options: [.anchorsMatchLines])
        let ns = hub as NSString
        return regex.matches(in: hub, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2)),
             ns.substring(with: $0.range(at: 3)))
        }
    }

    /// What a hub line gets wrong about the sub-headings of its page: the pointers that
    /// resolve to none of them (or to one already named), and the sub-headings no pointer names.
    private static func hubLineDefects(rest: String, subHeadings: [String])
        -> (extra: [String], missing: [String]) {
        var extra: [String] = []
        var named: [String] = []
        for tail in Parser.tails(of: rest) {
            if let heading = Parser.resolve(tail, headings: subHeadings), !named.contains(heading) {
                named.append(heading)
            } else {
                extra.append("\u{A7}" + tail.prefix(40))
            }
        }
        return (extra, subHeadings.filter { !named.contains($0) }.sorted())
    }

    /// A page's headings minus its H1 (the first one in the file).
    private static func subHeadings(ofPage text: String) -> [String] {
        var all = StandingDocuments.headings(in: text)
        let first = text.components(separatedBy: "\n").first { $0.hasPrefix("# ") }
            .map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
        if let first, let i = all.firstIndex(of: first) { all.remove(at: i) }
        return all
    }

    func testEachHubLineNamesEveryHeadingOfItsPage() throws {
        let links = try hubLinks()
        XCTAssertFalse(links.isEmpty, "ARCHITECTURE.md links no page — nothing to compare")
        var wrong: [String] = []
        for link in links {
            guard let text = try? pageText(link.file) else { continue }
            let subs = Self.subHeadings(ofPage: text)
            let d = Self.hubLineDefects(rest: link.rest, subHeadings: subs)
            if !d.extra.isEmpty || !d.missing.isEmpty {
                wrong.append("Architecture/\(link.file) — extra (named, not a sub-heading of the page): \(d.extra); missing (sub-heading the hub line does not name): \(d.missing)")
            }
        }
        XCTAssertTrue(wrong.isEmpty,
            "\(wrong.count) hub line(s) do not name exactly the headings of their page:\n\(wrong.joined(separator: "\n"))")
    }

    func testEveryHeadingOfEveryPageResolves() throws {
        let pages = try pagesOnDisk()
        XCTAssertFalse(pages.isEmpty, "Architecture/ holds no page — the hub has nothing split out, and every verdict below is over no text")
        let known = Set(try StandingDocuments.headings(of: "ARCHITECTURE"))
        var read = 0
        var lost: [String] = []
        for page in pages {
            for heading in StandingDocuments.headings(in: try pageText(page)) {
                read += 1
                if !known.contains(heading) { lost.append("Architecture/\(page) — \(heading)") }
            }
        }
        if !pages.isEmpty {
            XCTAssertGreaterThan(read, 0, "the pages on disk carry no heading at all")
        }
        XCTAssertTrue(lost.isEmpty,
            "\(lost.count) heading(s) of the pages are not among headings(of: \"ARCHITECTURE\") — a pointer at them would read as dead:\n\(lost.joined(separator: "\n"))")
    }

    func testTheHubLinksExactlyThePagesOnDisk() throws {
        let onDisk = Set(try pagesOnDisk())
        let links = try hubLinks()
        XCTAssertFalse(links.isEmpty, "ARCHITECTURE.md has no line shaped `- [H1](Architecture/File.md) — purpose`")
        let linked = links.map(\.file)
        XCTAssertEqual(linked.count, Set(linked).count, "a page is linked twice: \(linked)")
        let missing = Set(linked).subtracting(onDisk).sorted()
        XCTAssertTrue(missing.isEmpty, "the hub links page(s) that do not exist: \(missing)")
        let orphans = onDisk.subtracting(linked).sorted()
        XCTAssertTrue(orphans.isEmpty, "page(s) on disk the hub does not link: \(orphans)")
        XCTAssertFalse(onDisk.isEmpty, "Architecture/ holds no page — an empty directory agrees with an empty hub")
    }

    func testEachPageOpensWithItsLinkText() throws {
        let links = try hubLinks()
        XCTAssertFalse(links.isEmpty, "ARCHITECTURE.md links no page — nothing to compare")
        for link in links {
            let stem = String(link.file.dropLast(3))
            guard let text = try? pageText(link.file) else {
                XCTFail("Architecture/\(link.file) is linked and cannot be read"); continue
            }
            let first = text.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            XCTAssertTrue(first.hasPrefix("# ") && !first.hasPrefix("## "),
                "Architecture/\(link.file) does not open with an H1: \(first.debugDescription)")
            let h1 = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(h1, link.text, "Architecture/\(link.file): H1 differs from the hub's link text")
            // The file name is the H1 in UpperCamelCase: every non-letter/digit dropped,
            // the first letter of each word uppercased ("menu-bar" -> "MenuBar").
            let camel = h1.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            XCTAssertEqual(stem, camel,
                "Architecture/\(link.file): the file name is not UpperCamelCase of the H1 \(h1.debugDescription) (expected \(camel).md)")
            XCTAssertTrue(stem.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } && stem.first?.isUppercase == true,
                "file stem \(stem.debugDescription) is not ASCII letters and digits starting uppercase")
        }
    }

    func testNoHeadingIsWrittenTwiceAcrossTheHubAndItsPages() throws {
        let pages = try pagesOnDisk()
        XCTAssertFalse(pages.isEmpty, "Architecture/ holds no page — uniqueness over the hub alone is the old check")
        var owners: [String: [String]] = [:]
        for heading in StandingDocuments.headings(in: try RepoSource.text(of: "ARCHITECTURE.md")) {
            owners[heading, default: []].append("ARCHITECTURE.md")
        }
        for page in pages {
            for heading in StandingDocuments.headings(in: try pageText(page)) {
                owners[heading, default: []].append("Architecture/" + page)
            }
        }
        let twice = owners.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        XCTAssertTrue(twice.isEmpty,
            "heading(s) written more than once — a pointer to them names two places:\n"
            + twice.map { "\($0.key) — \($0.value.joined(separator: ", "))" }.joined(separator: "\n"))
        // The resolver must not hide a duplicate by collapsing: it lists as many as the files hold.
        let all = try StandingDocuments.headings(of: "ARCHITECTURE")
        XCTAssertEqual(all.count, owners.values.reduce(0) { $0 + $1.count },
            "headings(of: \"ARCHITECTURE\") lists \(all.count) headings; the hub and the pages hold \(owners.values.reduce(0) { $0 + $1.count })")
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

    func testLinkedPagesReadsOnlyPageLinksInLinkOrder() {
        let hub = """
            # Hub
            - [Zeta](Architecture/Zeta.md) \u{2014} last by name, first by link
            - [Alpha](Architecture/Alpha.md) \u{2014} second
            See [the readme](README.md), [site](https://example.com/Architecture/Site.md),
            [anchor](#Alpha), [nested](Architecture/sub/Deep.md), [dashed](Architecture/Bad-Name.md),
            [other dir](docs/Architecture/Other.md) and [text](Architecture/Mid2.md).
            """
        XCTAssertEqual(StandingDocuments.linkedPages(in: hub),
                       ["Architecture/Zeta.md", "Architecture/Alpha.md", "Architecture/Mid2.md"])
        XCTAssertEqual(StandingDocuments.linkedPages(in: "no links here"), [])
    }

    func testAHubLineIsComparedWithTheSubHeadingsOfItsPage() {
        let subs = ["Alpha", "Beta, and more"]
        let ok = Self.hubLineDefects(rest: " \u{2014} purpose; \u{A7} Alpha, \u{A7} Beta, and more.", subHeadings: subs)
        XCTAssertTrue(ok.extra.isEmpty && ok.missing.isEmpty, "a correct line is green")

        let short = Self.hubLineDefects(rest: " \u{2014} purpose; \u{A7} Alpha.", subHeadings: subs)
        XCTAssertEqual(short.missing, ["Beta, and more"], "a line missing one heading is red")
        XCTAssertTrue(short.extra.isEmpty)

        let foreign = Self.hubLineDefects(rest: " \u{2014} purpose; \u{A7} Alpha, \u{A7} Beta, and more, \u{A7} Release.", subHeadings: subs)
        XCTAssertEqual(foreign.extra.count, 1, "a heading of another page is red")
        XCTAssertTrue(foreign.missing.isEmpty)

        let twice = Self.hubLineDefects(rest: " \u{2014} purpose; \u{A7} Alpha, \u{A7} Alpha, \u{A7} Beta, and more.", subHeadings: subs)
        XCTAssertEqual(twice.extra.count, 1, "a heading named twice is red")

        let none = Self.hubLineDefects(rest: " \u{2014} purpose, no pointer.", subHeadings: [])
        XCTAssertTrue(none.extra.isEmpty && none.missing.isEmpty, "no section sign for a page without sub-headings is green")

        let stray = Self.hubLineDefects(rest: " \u{2014} purpose; \u{A7} Alpha.", subHeadings: [])
        XCTAssertEqual(stray.extra.count, 1, "a pointer on a page without sub-headings is red")
    }

    func testSubHeadingsOfAPageExcludeItsH1() {
        XCTAssertEqual(Set(Self.subHeadings(ofPage: "# Page\n## A\n```\n# c\n```\n### B\n")), ["A", "B"])
    }

    func testHeadingsInsideAFenceAreNotSections() {
        let text = "# Real\n```sh\n# Comment\n```\n## Also real\n"
        XCTAssertEqual(Set(StandingDocuments.headings(in: text)), ["Real", "Also real"])
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
