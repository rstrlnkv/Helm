import HelmTestSupport
import XCTest

/// Every § pointer written in the standing documents and on the pages of the wiki names a
/// heading that exists, spelled exactly, and no page names one by a page's path;
/// `CLAUDE.md` stays inside its byte ceiling, and no span of a page runs past the aim
/// except where the list holds it.
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
/// **Why every sign of a page is read.** Whatever names a heading writes it the way
/// `ARCHITECTURE.md § How these pages are kept` says: the document's name, then the sign.
/// On a page, the sign after `ARCHITECTURE` or `CLAUDE` was read from the start; a sign
/// with neither before it, the one after `Architecture/<File>.md` among them, was read by
/// nothing, so a renamed heading left it dead with every row green. Now each sign of a
/// page is one of three: a named pointer, resolved against the document it names; the
/// page-path spelling, refused even when its heading exists, since that is not the way a
/// heading is named; or a sign with neither name before it, read and resolved against
/// `ARCHITECTURE` as the arrow pointers of `CLAUDE.md` are. The number of pointers read
/// must equal the number of signs the pages hold, so a sign the reader skips is red; a
/// sign read and given no verdict is not, and the fixtures below hold each verdict.
///
/// **Why spans, and why a list.** A span runs from a heading line to the next, and a page
/// with no heading under its H1 is one span: a reader who wants one paragraph reads all
/// of it. The aim is `pageCeiling` bytes for every span; the spans over it are listed by
/// name, each with the bytes it had when it was listed (`spansHeldOverTheAim`). A span
/// over the aim is written down, not excused: unlisted, or past its number, it is red, and
/// the way out is a heading inside it or a page of its own; a listed span at the aim or
/// under it, or gone, is red until it comes off the list. No row can see a number raised
/// or a span added, so the list says of itself that neither is done.
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

        /// The sign's offset in the text and the pointer, for each pointer that names its
        /// document. `text` is already joined.
        private static func namedSigns(in text: NSString) -> [(sign: Int, pointer: Named)] {
            let regex = try! NSRegularExpression(
                pattern: #"\b(ARCHITECTURE|CLAUDE)(?:\.md)?`?[ \t]*\x{A7}"#)
            return regex.matches(in: text as String,
                                 range: NSRange(location: 0, length: text.length)).map { m in
                let end = m.range.location + m.range.length
                return (end - 1, Named(document: text.substring(with: m.range(at: 1)),
                                       rest: text.substring(from: end)))
            }
        }

        /// Pointers that name their document: the architecture document name and the sign,
        /// a backticked document name and the sign, the bare name and the sign. Text is joined first.
        static func named(in text: String) -> [Named] {
            namedSigns(in: joined(text) as NSString).map(\.pointer)
        }

        /// One sign of a page, read as exactly one of three things.
        enum Sign {
            /// `ARCHITECTURE` or `CLAUDE`, with or without `.md`, before the sign.
            case named(Named)
            /// `Architecture/<File>.md` before the sign: refused even when the heading exists,
            /// since a heading is named by its document and not by its page
            /// (`ARCHITECTURE.md § How these pages are kept`).
            case refused(page: String, rest: String)
            /// Neither before it — nothing, or any other word: a pointer into `ARCHITECTURE`.
            case bare(rest: String)
        }

        /// Every sign of a page's text, in order, each read as one `Sign`. Text is joined first.
        static func signs(onPage text: String) -> [Sign] {
            let joinedText = joined(text) as NSString
            let named = Dictionary(uniqueKeysWithValues: namedSigns(in: joinedText).map { ($0.sign, $0.pointer) })
            let pageSpelling = try! NSRegularExpression(pattern: #"Architecture/([A-Za-z0-9]+\.md)`?[ \t]*\x{A7}"#)
            let refused = Dictionary(uniqueKeysWithValues: pageSpelling.matches(
                in: joinedText as String, range: NSRange(location: 0, length: joinedText.length)).map {
                ($0.range.location + $0.range.length - 1, joinedText.substring(with: $0.range(at: 1)))
            })
            return (0..<joinedText.length).filter { joinedText.character(at: $0) == 0xA7 }.map { at -> Sign in
                if let pointer = named[at] { return .named(pointer) }
                let rest = joinedText.substring(from: at + 1)
                if let page = refused[at] { return .refused(page: page, rest: rest) }
                return .bare(rest: rest)
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

    func testEverySignOnEveryPageIsALivePointerSpelledRight() throws {
        let architecture = try StandingDocuments.headings(of: "ARCHITECTURE")
        let claude = try StandingDocuments.headings(of: "CLAUDE")
        let pages = try pagesOnDisk()
        XCTAssertFalse(pages.isEmpty, "Architecture/ holds no page — every verdict below is over no text")
        var signs = 0
        var pagesWithASign = 0
        var read = 0
        var dead: [String] = []
        var refused: [String] = []
        for page in pages {
            let text = try pageText(page)
            let onPage = text.unicodeScalars.filter { $0 == "\u{A7}" }.count
            signs += onPage
            if onPage > 0 { pagesWithASign += 1 }
            let got = Self.pointers(ofPage: text, architecture: architecture, claude: claude)
            read += got.read
            dead += got.dead.map { "Architecture/\(page) — \($0)" }
            refused += got.refused.map { "Architecture/\(page) — \($0)" }
        }
        print("signs on the pages: \(signs) on \(pagesWithASign) page(s), \(read) read as pointers")
        XCTAssertGreaterThan(signs, 0, "the pages hold no section sign — the pointers of the wiki are read by nothing")
        XCTAssertEqual(read, signs,
            "the pages hold \(signs) section sign(s) and the guard read \(read) pointer(s) — a sign no one reads goes dead on a rename")
        XCTAssertTrue(refused.isEmpty,
            "\(refused.count) pointer(s) spelled with the page path, which is not an address; write `ARCHITECTURE.md \u{A7} X`:\n\(refused.joined(separator: "\n"))")
        XCTAssertTrue(dead.isEmpty, "\(dead.count) dead pointer(s) on the pages:\n\(dead.joined(separator: "\n"))")
    }

    /// The spans over the aim, by `File.md § heading`, each with the bytes it had when it was
    /// listed. A number here is not raised and a span is not added: no row can hold that,
    /// since a row sees the list as it stands and not as it was, so it is the order of this
    /// comment alone. What the rows hold: a span past its number is red until it takes a
    /// heading inside it, or a page of its own; a span that fell to the aim or under it, or
    /// is gone, is red until it comes off the list.
    private static let spansHeldOverTheAim = [
        "Screenshots.md \u{A7} Screenshots": 55_701,
        "ThePageHeader.md \u{A7} The tabs and the search field": 13_213,
    ]

    /// What the list of held spans gets wrong of the spans measured, by `File.md § heading`
    /// and bytes: a span over the aim that is not listed, a listed span that is gone or has
    /// fallen to the aim or under it, and one past its own number.
    private static func spanDefects(measured: [String: Int], held: [String: Int], aim: Int) -> [String] {
        var defects: [String] = []
        for (name, bytes) in measured.sorted(by: { $0.key < $1.key }) where bytes > aim && held[name] == nil {
            defects.append("\(name): \(bytes) B, \(bytes - aim) over the aim \(aim) and not listed — give it a heading inside it, or a page of its own")
        }
        for (name, number) in held.sorted(by: { $0.key < $1.key }) {
            guard let bytes = measured[name] else {
                defects.append("\(name): listed at \(number) B and gone — take it off the list"); continue
            }
            if bytes <= aim {
                defects.append("\(name): \(bytes) B, at or under the aim \(aim) — take it off the list")
            } else if bytes > number {
                defects.append("\(name): \(bytes) B, past its number \(number) — a heading inside it, or a page of its own; the number is not raised")
            }
        }
        return defects
    }

    func testNoSpanOfAPageRunsPastTheAimExceptWhereHeld() throws {
        let pages = try pagesOnDisk()
        XCTAssertFalse(pages.isEmpty, "Architecture/ holds no page — every verdict below is over no text")
        var read = 0
        var pageBytes = 0
        var spanBytes = 0
        var measured: [String: Int] = [:]
        var drift: [String] = []
        for page in pages {
            let text = try pageText(page)
            let got = Self.spans(ofPage: text, ceiling: 0)
            read += got.read
            pageBytes += text.utf8.count
            spanBytes += got.over.reduce(0) { $0 + $1.bytes }
            for span in got.over { measured["\(page) \u{A7} \(span.heading)"] = span.bytes }
            // The spans' walk restates the fence-and-heading rule of `StandingDocuments`; the
            // two must give the same headings (a text with none is one span with an empty one).
            let fromSpans = got.over.map(\.heading).filter { !$0.isEmpty }.sorted()
            let fromDocuments = StandingDocuments.headings(in: text).sorted()
            if fromSpans != fromDocuments {
                func minus(_ a: [String], _ b: [String]) -> [String] {
                    var rest = b
                    return a.filter { heading in
                        guard let i = rest.firstIndex(of: heading) else { return true }
                        rest.remove(at: i); return false
                    }
                }
                drift.append("Architecture/\(page) — only in the spans: \(minus(fromSpans, fromDocuments)); only in headings(in:): \(minus(fromDocuments, fromSpans))")
            }
        }
        XCTAssertGreaterThanOrEqual(read, pages.count, "\(pages.count) page(s) and only \(read) span(s) read — every page is at least one")
        XCTAssertEqual(measured.count, read, "\(read) span(s) read and \(measured.count) named — a heading is written twice on one page, or a page is empty and its span of no bytes is not named")
        XCTAssertEqual(spanBytes, pageBytes, "the spans hold \(spanBytes) B and the pages \(pageBytes) B — a stretch of a page is in no span")
        XCTAssertTrue(drift.isEmpty,
            "\(drift.count) page(s) whose spans carry other headings than StandingDocuments.headings(in:) gives:\n\(drift.joined(separator: "\n"))")

        for (name, number) in Self.spansHeldOverTheAim.sorted(by: { $0.key < $1.key }) {
            if let bytes = measured[name] {
                print("held span: \(name) — \(bytes) B measured, \(number) B listed, aim \(Self.pageCeiling) B")
            }
        }
        if let largest = measured.filter({ Self.spansHeldOverTheAim[$0.key] == nil }).max(by: { $0.value < $1.value }) {
            print("largest span not held: \(largest.key) — \(largest.value) B, aim \(Self.pageCeiling) B")
        }
        let defects = Self.spanDefects(measured: measured, held: Self.spansHeldOverTheAim, aim: Self.pageCeiling)
        XCTAssertTrue(defects.isEmpty, "\(defects.count) span(s) against the aim of \(Self.pageCeiling) B:\n\(defects.joined(separator: "\n"))")
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

    // MARK: - Parser fixtures: what a page's text says, and how long its sections run
    //
    // Two seams over TEXT, no file reads. `pointers(ofPage:architecture:claude:)` reads
    // every sign of one page's text; `spans(ofPage:ceiling:)` is the measure of a page's
    // sections. The document rows call them over the pages; the rows below feed them text
    // a live page may not hold.

    /// What the guard says of one page's text: the pointers it read, those that name no
    /// heading, and the spellings it refuses outright.
    struct PagePointers {
        var read: Int
        var dead: [String]
        var refused: [String]
    }

    /// One run of a page from a heading line to the next heading line (any level, fences
    /// skipped), the heading line counted in it, and its size in UTF-8 bytes.
    struct PageSpan {
        var heading: String
        var bytes: Int
    }

    /// What the measure says of one page's text: how many spans it read, and those over
    /// the ceiling.
    struct PageSpans {
        var read: Int
        var over: [PageSpan]
    }

    /// The pointers of one page's text, judged against the headings of `ARCHITECTURE`
    /// and of `CLAUDE`. Every sign of the page is read, so `read` is the number of signs;
    /// a refused spelling is counted there and named in `refused`, never in `dead`.
    static func pointers(ofPage text: String, architecture: [String], claude: [String]) -> PagePointers {
        let headingsByDocument = ["ARCHITECTURE": architecture, "CLAUDE": claude]
        var read = 0
        var dead: [String] = []
        var refused: [String] = []
        for sign in Parser.signs(onPage: text) {
            read += 1
            switch sign {
            case .named(let pointer):
                if Parser.resolve(pointer.rest, headings: headingsByDocument[pointer.document] ?? []) == nil {
                    dead.append("\(pointer.document) \u{A7}\(pointer.rest.prefix(50))")
                }
            case .bare(let rest):
                if Parser.resolve(rest, headings: architecture) == nil { dead.append("\u{A7}\(rest.prefix(50))") }
            case .refused(let page, let rest):
                refused.append("Architecture/\(page) \u{A7}\(rest.prefix(50))")
            }
        }
        return PagePointers(read: read, dead: dead, refused: refused)
    }

    /// The spans of one page's text, with those that exceed `ceiling` bytes in `over`. A
    /// span is counted from its heading line to the next, a heading being any line outside
    /// a fence that opens with `#` and has a title (the reading `StandingDocuments`
    /// gives); the lines before the first heading belong to the first span, and a text
    /// with no heading is one span with an empty heading. `ceiling: 0` names every span
    /// that has a byte: an empty text is one span of none, counted in `read` and not named.
    /// The row over the pages compares the headings this reading gives for each page with
    /// `StandingDocuments.headings(in:)`, so it is red only for a drift in a rule some page
    /// exercises; a `#` line inside a fence is held by the fixtures below, for this reader
    /// alone.
    static func spans(ofPage text: String, ceiling: Int) -> PageSpans {
        let lines = text.components(separatedBy: "\n")
        var spans: [PageSpan] = []
        var before = 0
        var inFence = false
        for (index, line) in lines.enumerated() {
            let bytes = line.utf8.count + (index < lines.count - 1 ? 1 : 0)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
            } else if !inFence, line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { spans.append(PageSpan(heading: title, bytes: spans.isEmpty ? before : 0)) }
            }
            if spans.isEmpty { before += bytes } else { spans[spans.count - 1].bytes += bytes }
        }
        if spans.isEmpty { spans = [PageSpan(heading: "", bytes: before)] }
        return PageSpans(read: spans.count, over: spans.filter { $0.bytes > ceiling })
    }

    /// The aim for one span of a page, in bytes.
    private static let pageCeiling = 8_192

    /// `bytes` bytes of ASCII in lines of 79 letters, no line opening with a mark.
    private static func filler(_ bytes: Int) -> String {
        String((0..<bytes).map { ($0 + 1) % 80 == 0 ? Character("\n") : Character("a") })
    }

    private let architectureHeadings = ["Release", "The updater", "Signing and grants", "Where things go"]
    private let claudeHeadings = ["Where things go", "Commands"]

    // MARK: Pointers of a page

    func testABareSignOnAPageNamesAHeadingThatWasRenamedSoItIsDead() {
        // "The updater" is renamed to "The update channel": nothing resolves the pointer.
        let renamed = ["Release", "The update channel", "Signing and grants"]
        let got = Self.pointers(ofPage: "# Page\n\nThe rule holds here (\u{A7} The updater).\n",
                                architecture: renamed, claude: claudeHeadings)
        XCTAssertEqual(got.read, 1, "a bare sign on a page is read; the guard read \(got.read)")
        XCTAssertEqual(got.dead.count, 1,
            "a bare sign whose heading was renamed is dead; the guard reported \(got.dead)")
    }

    func testABareSignOnAPageIsReadAndResolvedWhenItsHeadingStands() {
        let got = Self.pointers(ofPage: "# Page\n\nThe rule holds here (\u{A7} The updater).\n",
                                architecture: architectureHeadings, claude: claudeHeadings)
        XCTAssertEqual(got.read, 1,
            "resolved needs read: a bare sign nobody read resolves to nothing; the guard read \(got.read)")
        XCTAssertTrue(got.dead.isEmpty, "the heading stands, the pointer is live: \(got.dead)")
        XCTAssertTrue(got.refused.isEmpty, "a bare sign is read and resolved, not refused: \(got.refused)")
    }

    func testAPointerFollowedByProseIsDeadWhetherOrNotItsHeadingExists() {
        let page = "# Page\n\nA grant is the signature's doing (\u{A7} Signing and grants on the Release page): a hash.\n"
        let present = Self.pointers(ofPage: page, architecture: architectureHeadings, claude: claudeHeadings)
        XCTAssertEqual(present.read, 1, "the pointer is read; the guard read \(present.read)")
        XCTAssertEqual(present.dead.count, 1,
            "prose after a pointer reads as dead even when the heading exists; the guard reported \(present.dead)")

        let absent = Self.pointers(ofPage: page, architecture: ["Release", "The updater"], claude: claudeHeadings)
        XCTAssertEqual(absent.read, 1, "the pointer is read; the guard read \(absent.read)")
        XCTAssertEqual(absent.dead.count, 1,
            "and dead when the heading is gone; the guard reported \(absent.dead)")
    }

    func testThePagePathSpellingIsRefusedEvenWhenItsHeadingExists() {
        let page = "# Page\n\nThe tabs (Architecture/ThePageHeader.md \u{A7} The tabs and the search field) hold.\n"
        let present = Self.pointers(ofPage: page,
                                    architecture: architectureHeadings + ["The tabs and the search field"],
                                    claude: claudeHeadings)
        XCTAssertEqual(present.refused.count, 1,
            "the page-path spelling is refused as a spelling although its heading stands; refused \(present.refused)")

        let absent = Self.pointers(ofPage: page, architecture: architectureHeadings, claude: claudeHeadings)
        XCTAssertEqual(absent.refused.count, 1,
            "and refused when the heading is gone; refused \(absent.refused)")
    }

    func testTheNamedSpellingsOnAPageAreReadOnceEachNeverAgainAsABareSign() {
        for (label, page) in [("backticked", "# Page\n\nThe reason is in `ARCHITECTURE.md \u{A7} The updater`.\n"),
                              ("plain", "# Page\n\nThe reason is in ARCHITECTURE.md \u{A7} The updater.\n")] {
            let live = Self.pointers(ofPage: page, architecture: architectureHeadings, claude: claudeHeadings)
            XCTAssertEqual(live.read, 1, "\(label): read once, not again as a bare sign; the guard read \(live.read)")
            XCTAssertTrue(live.dead.isEmpty, "\(label): the heading stands: \(live.dead)")
            XCTAssertTrue(live.refused.isEmpty, "\(label): a named spelling is not refused: \(live.refused)")

            let renamed = Self.pointers(ofPage: page, architecture: ["Release", "The update channel"],
                                        claude: claudeHeadings)
            XCTAssertEqual(renamed.read, 1, "\(label): read once; the guard read \(renamed.read)")
            XCTAssertEqual(renamed.dead.count, 1, "\(label): renamed, so dead: \(renamed.dead)")
        }
    }

    func testAClaudePointerOnAPageIsReadAgainstClaudeNeverAsABareOne() {
        let page = "# Page\n\nIt is not here (CLAUDE.md \u{A7} Where things go).\n"
        // The heading is CLAUDE's only: a bare reading into ARCHITECTURE would call it dead.
        let inClaudeOnly = Self.pointers(ofPage: page, architecture: ["Release", "The updater"],
                                         claude: claudeHeadings)
        XCTAssertEqual(inClaudeOnly.read, 1, "read once, against CLAUDE; the guard read \(inClaudeOnly.read)")
        XCTAssertTrue(inClaudeOnly.dead.isEmpty, "CLAUDE has the heading: \(inClaudeOnly.dead)")
        XCTAssertTrue(inClaudeOnly.refused.isEmpty, "a CLAUDE pointer is not a refused spelling: \(inClaudeOnly.refused)")
        // The heading is ARCHITECTURE's only: a CLAUDE pointer must not resolve there.
        let inArchitectureOnly = Self.pointers(ofPage: page, architecture: architectureHeadings,
                                               claude: ["Commands"])
        XCTAssertEqual(inArchitectureOnly.read, 1, "read once; the guard read \(inArchitectureOnly.read)")
        XCTAssertEqual(inArchitectureOnly.dead.count, 1,
            "CLAUDE lacks the heading, so dead whatever ARCHITECTURE holds: \(inArchitectureOnly.dead)")
    }

    // MARK: Spans of a page

    func testAPageOfNineKilobytesWithoutSubHeadingsIsOneSpanOverTheCeiling() {
        let page = "# A page\n" + Self.filler(9_000)
        XCTAssertGreaterThan(page.utf8.count, Self.pageCeiling, "the fixture is over the ceiling")
        let got = Self.spans(ofPage: page, ceiling: Self.pageCeiling)
        XCTAssertEqual(got.read, 1, "an H1 and no `##` is one span; the measure read \(got.read)")
        XCTAssertEqual(got.over.count, 1, "the whole page is over \(Self.pageCeiling) bytes; the measure named \(got.over.count) span(s)")
        XCTAssertEqual(got.over.first?.bytes, page.utf8.count, "the H1 preamble is part of the span")
        XCTAssertEqual(got.over.first?.heading, "A page")
    }

    func testTheSameTextSplitByHeadingsUnderTheCeilingIsCleanAndReadAsThreeSpans() {
        let page = "# A page\n" + Self.filler(3_000) + "\n## One\n" + Self.filler(3_000)
            + "\n## Two\n" + Self.filler(3_000)
        XCTAssertGreaterThan(page.utf8.count, Self.pageCeiling, "the page as a whole is over the ceiling")
        let got = Self.spans(ofPage: page, ceiling: Self.pageCeiling)
        XCTAssertEqual(got.read, 3, "clean must be a verdict over three spans, not over none; the measure read \(got.read)")
        XCTAssertTrue(got.over.isEmpty, "each span is about 3 KB: \(got.over.map { "\($0.heading) \($0.bytes)" })")
    }

    func testAHashLineInsideAFenceDoesNotSplitASpan() {
        let page = "# A page\n" + Self.filler(5_000) + "\n```sh\n# comment\n```\n" + Self.filler(5_000)
        XCTAssertGreaterThan(page.utf8.count, Self.pageCeiling)
        let got = Self.spans(ofPage: page, ceiling: Self.pageCeiling)
        XCTAssertEqual(got.read, 1, "the comment is not a heading; the measure read \(got.read) span(s)")
        XCTAssertEqual(got.over.count, 1,
            "split at the comment the halves would each be 5 KB and clean; the whole is over: \(got.over.count)")
    }

    func testTheCeilingCountsBytesOfUTF8AndNotCharacters() {
        let page = "# A page\n" + String(repeating: "\u{E9}", count: 4_500)
        XCTAssertLessThan(page.count, Self.pageCeiling, "fewer characters than the ceiling")
        XCTAssertGreaterThan(page.utf8.count, Self.pageCeiling, "more bytes than the ceiling")
        let got = Self.spans(ofPage: page, ceiling: Self.pageCeiling)
        XCTAssertEqual(got.read, 1, "one span; the measure read \(got.read)")
        XCTAssertEqual(got.over.count, 1, "bytes, not characters; the measure named \(got.over.count) span(s)")
    }

    func testASpanOfExactlyTheCeilingIsCleanAndOneByteMoreIsOver() {
        let exact = "# A page\n" + Self.filler(Self.pageCeiling - 9)
        XCTAssertEqual(exact.utf8.count, Self.pageCeiling)
        let atCeiling = Self.spans(ofPage: exact, ceiling: Self.pageCeiling)
        XCTAssertEqual(atCeiling.read, 1, "clean must be a verdict over one span; the measure read \(atCeiling.read)")
        XCTAssertTrue(atCeiling.over.isEmpty, "exactly at the ceiling is not over it")

        let oneMore = "# A page\n" + Self.filler(Self.pageCeiling - 8)
        XCTAssertEqual(oneMore.utf8.count, Self.pageCeiling + 1)
        let past = Self.spans(ofPage: oneMore, ceiling: Self.pageCeiling)
        XCTAssertEqual(past.over.count, 1, "one byte past the ceiling is over; the measure named \(past.over.count) span(s)")
    }

    func testTheMeasureCountsEveryHeadingLevelAndNoFencedLine() {
        let page = """
            # T
            a
            ## A
            a
            ### B
            a
            ```
            # not a heading
            ```
            ## C
            a
            """
        let got = Self.spans(ofPage: page, ceiling: Self.pageCeiling)
        XCTAssertEqual(got.read, 4, "H1, `##`, `###`, `##` are four spans and the fenced line none; the measure read \(got.read)")
        XCTAssertTrue(got.over.isEmpty)
    }

    // MARK: Held spans

    func testTheHeldSpansAreRedWhenUnlistedPastTheirNumberGoneOrAtTheAim() {
        func defects(_ measured: [String: Int]) -> [String] {
            Self.spanDefects(measured: measured, held: ["A.md \u{A7} Held": 9_000], aim: 8_192)
        }
        // Green: a held span at its number or under it, and any span at or under the aim.
        XCTAssertEqual(defects(["A.md \u{A7} Held": 9_000, "B.md \u{A7} Fine": 8_192]), [])
        XCTAssertEqual(defects(["A.md \u{A7} Held": 8_193]), [], "under its number is not red")
        // Red, one way each.
        XCTAssertEqual(defects(["A.md \u{A7} Held": 9_000, "B.md \u{A7} New": 8_193]).count, 1, "an unlisted span over the aim")
        XCTAssertEqual(defects(["A.md \u{A7} Held": 9_001]).count, 1, "a listed span over its number")
        XCTAssertEqual(defects(["B.md \u{A7} Other": 100]).count, 1, "a listed span that is gone")
        XCTAssertEqual(defects(["A.md \u{A7} Held": 8_192]).count, 1, "a listed span at the aim")
        XCTAssertEqual(defects(["A.md \u{A7} Held": 100]).count, 1, "a listed span under the aim")
    }
}
