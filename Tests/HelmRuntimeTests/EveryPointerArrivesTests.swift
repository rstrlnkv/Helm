import HelmTestSupport
import XCTest

/// Every pointer the code and the documents write arrives: a section sign names a
/// heading its document has, a backticked path names something the tree holds, and
/// the pages the pointers land on are laid out so that a name means one place.
///
/// One test, because a pointer is a sentence in one file naming a place in
/// another and no compiler joins the two: one reader of headings and one
/// resolver serve every side, so they cannot disagree.
///
/// A pointer is read from where it is written: a section nobody points at is
/// fine, a pointer at a section nobody wrote is the finding. Matching is
/// case-insensitive, headings are read outside fenced code only, and the
/// longest heading is tried first so a short one never wins a longer one's
/// match.
///
/// Every check here is green over no text, so each has a canary count that a
/// reader which silently stopped reading cannot reach.
final class EveryPointerArrivesTests: XCTestCase {

    // MARK: - Reading

    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    /// A document's heading texts outside fenced code, lowercased, longest first.
    private static func headings(in text: String) -> [String] {
        var fenced = false
        var found: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle(); continue }
            guard !fenced, line.hasPrefix("#") else { continue }
            let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { found.append(title.lowercased()) }
        }
        return found.sorted { $0.count > $1.count }
    }

    /// The heading a pointer's text names, or nil: a heading, then an optional
    /// closing mark, then a terminator, whitespace before another section sign or an arrow or a table cell edge,
    /// or the end. `headings` are lowercased, longest first.
    private static func resolve(_ rest: String, headings: [String]) -> String? {
        var text = Substring(rest.lowercased().drop(while: { $0 == " " || $0 == "\t" }))
        if let first = text.first, "«\"“`*".contains(first) {
            text = text.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        for heading in headings where text.hasPrefix(heading) {
            var after = text.dropFirst(heading.count)
            if let c = after.first, "`\"»”*'".contains(c) { after = after.dropFirst() }
            guard let next = after.first else { return heading }
            if ".,;:)]|\n".contains(next) { return heading }
            let trimmed = after.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.isEmpty || trimmed.hasPrefix("\u{A7}") || trimmed.hasPrefix("|") || trimmed.hasPrefix("→") { return heading }
        }
        return nil
    }

    /// Soft line breaks removed: a newline between two non-blank lines becomes a
    /// space, a quote marker or list indent dropped; a blank line stays a break.
    private static func softJoined(_ text: String) -> String {
        regex(#"(?<=\S)[ \t]*\n[ \t]*(?:>[ \t]*)?(?=\S)(?![-*+|#][ \t]|\d+\.[ \t]|#)"#)
            .stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// Swift text with a string split by `+` and a wrapped `//` or `///` comment
    /// read as one run, so a name ending one line and a section sign starting the
    /// next sit side by side.
    private static func codeJoined(_ text: String) -> String {
        let concatenated = regex(#""\n[ \t]*\+[ \t]*""#)
            .stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return regex(#"\n[ \t]*/{2,3}[ \t]?"#).stringByReplacingMatches(
            in: concatenated, range: NSRange(concatenated.startIndex..., in: concatenated), withTemplate: " ")
    }

    /// What follows each section sign up to the next one, so a list of two
    /// pointers reads as two. `before` is the text ahead of that sign.
    private static func tails(of text: String) -> [(before: String, tail: String)] {
        let parts = text.components(separatedBy: "\u{A7}")
        return parts.indices.dropFirst().map { (parts[$0 - 1], parts[$0]) }
    }

    private static func excerpt(_ tail: String) -> String {
        String(tail.replacingOccurrences(of: "\n", with: " ").prefix(60))
    }

    // MARK: - The documents

    private static let standing = ["ARCHITECTURE.md", "README.md", "CHANGELOG.md"]
    private static let hubLink = regex(#"\[([^\]]+)\]\(Architecture/([A-Za-z0-9]+\.md)\)"#)

    private func hub() throws -> String { try RepoSource.text(of: "ARCHITECTURE.md") }

    /// `(link text, file name)` of every page the hub links, in link order.
    private func hubLinks() throws -> [(text: String, file: String)] {
        let hub = try hub() as NSString
        return Self.hubLink.matches(in: hub as String, range: NSRange(location: 0, length: hub.length)).map {
            (hub.substring(with: $0.range(at: 1)), hub.substring(with: $0.range(at: 2)))
        }
    }

    private func page(_ file: String) throws -> String { try RepoSource.text(of: "Architecture/" + file) }

    /// The `.md` files of `Architecture/`, by directory listing.
    private func pagesOnDisk() -> [String] {
        let dir = RepoSource.root.appendingPathComponent("Architecture").path
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
    }

    /// The standing documents: three of the tree and every page the hub links.
    private func standingDocuments() throws -> [String] {
        Self.standing + (try hubLinks().map { "Architecture/" + $0.file })
    }

    /// The hub's headings and every linked page's.
    private func architectureHeadings() throws -> [String] {
        var all = Self.headings(in: try hub())
        for link in try hubLinks() { all += Self.headings(in: try page(link.file)) }
        return all.sorted { $0.count > $1.count }
    }

    private func requireRules() throws -> String {
        guard let text = try RepoSource.rules() else {
            throw XCTSkip("No local AGENTS.md in this checkout or its main checkout")
        }
        return text
    }

    // MARK: - 1. Every section sign resolves

    private static let codeDocumentPointer = regex(#"\b(ARCHITECTURE|AGENTS)(?:\.md)?`?[ \t]*\x{A7}[ \t]*"#)
    private static let codePagePointer = regex(#"Architecture/([A-Za-z0-9]+)\.md`?[ \t]*\x{A7}[ \t]*"#)
    private static let codePageMention = regex(#"Architecture/([A-Za-z0-9]+)\.md"#)

    private static func pointerFinding(file: String, label: String, tail: String, headings: [String]?) -> String? {
        if let headings, resolve(tail, headings: headings) != nil { return nil }
        let pointer = "\(file) — \(label)\(excerpt(tail))"
        return headings == nil ? "\(pointer) (private rules unavailable)" : pointer
    }

    private struct CodeScan { var files = 0, architecturePointers = 0; var dead: [String] = [] }

    private func scanSwift() throws -> CodeScan {
        var scan = CodeScan()
        let architecture = try architectureHeadings()
        let rulesHeadings = try RepoSource.rules().map(Self.headings(in:))
        let pages = Set(pagesOnDisk())
        for file in try RepoSource.swiftFiles(under: "Sources") + RepoSource.swiftFiles(under: "Tests") {
            scan.files += 1
            let text = Self.codeJoined(try RepoSource.text(of: file)) as NSString
            let whole = NSRange(location: 0, length: text.length)
            func rest(after match: NSTextCheckingResult) -> String {
                let end = match.range.location + match.range.length
                return text.substring(with: NSRange(location: end, length: min(220, text.length - end)))
            }
            for match in Self.codeDocumentPointer.matches(in: text as String, range: whole) {
                let document = text.substring(with: match.range(at: 1))
                if document == "ARCHITECTURE" { scan.architecturePointers += 1 }
                if let finding = Self.pointerFinding(file: file, label: "\(document) \u{A7} ", tail: rest(after: match),
                                                     headings: document == "AGENTS" ? rulesHeadings : architecture) {
                    scan.dead.append(finding)
                }
            }
            for match in Self.codePagePointer.matches(in: text as String, range: whole) {
                let name = text.substring(with: match.range(at: 1)) + ".md"
                guard pages.contains(name), let own = try? page(name) else { continue }  // the mention check names it
                if Self.resolve(rest(after: match), headings: Self.headings(in: own)) == nil {
                    scan.dead.append("\(file) — Architecture/\(name) \u{A7} \(Self.excerpt(rest(after: match)))")
                }
            }
            for match in Self.codePageMention.matches(in: text as String, range: whole)
            where !pages.contains(text.substring(with: match.range(at: 1)) + ".md") {
                scan.dead.append("\(file) — names the page \(text.substring(with: match.range)), which does not exist")
            }
        }
        return scan
    }

    func testRulesPointersAcceptBothDocumentSpellings() {
        for name in ["AGENTS", "`AGENTS.md`"] {
            let citation = "\(name) \u{A7} Commands"
            XCTAssertTrue(Self.codeDocumentPointer.firstMatch(in: citation, range: NSRange(citation.startIndex..., in: citation)) != nil, name)
            XCTAssertTrue(Self.namedBefore.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil, name)
        }
    }

    func testEverySectionTheSwiftFilesNameExists() throws {
        let dead = try scanSwift().dead
        XCTAssertTrue(dead.isEmpty, "\(dead.count) Swift pointer(s) could not be validated:\n" + dead.joined(separator: "\n"))
    }

    /// Before which document a section sign stands: a named document or page, or
    /// neither, which reads against the hub and all its pages.
    private static let namedBefore = regex(
        #"(?:\b(ARCHITECTURE|AGENTS)(?:\.md)?|Architecture/([A-Za-z0-9]+)\.md)`?[ \t]*$"#)

    private func scanDocuments() throws -> [String] {
        let architecture = try architectureHeadings()
        let rulesHeadings = try RepoSource.rules().map(Self.headings(in:))
        var dead: [String] = []
        for file in try standingDocuments() {
            let text = Self.softJoined(try RepoSource.text(of: file))
            for (before, tail) in Self.tails(of: text) {
                let tailEnd = String(before.suffix(80))
                let named = Self.namedBefore.firstMatch(in: tailEnd, range: NSRange(tailEnd.startIndex..., in: tailEnd))
                var headings: [String]? = architecture
                var label = "\u{A7} "
                if let named, let range = Range(named.range(at: 1), in: tailEnd), tailEnd[range] == "AGENTS" {
                    headings = rulesHeadings
                    label = "AGENTS \u{A7} "
                } else if let named, let range = Range(named.range(at: 2), in: tailEnd) {
                    let name = tailEnd[range] + ".md"
                    guard let own = try? page(String(name)) else { dead.append("\(file) — names the page Architecture/\(name), which does not exist"); continue }
                    headings = Self.headings(in: own)
                    label = "Architecture/\(name) \u{A7} "
                }
                if let finding = Self.pointerFinding(file: file, label: label, tail: tail, headings: headings) {
                    dead.append(finding)
                }
            }
        }
        return dead
    }

    func testEverySectionTheStandingDocumentsNameExists() throws {
        let dead = try scanDocuments()
        XCTAssertTrue(dead.isEmpty, "\(dead.count) standing document pointer(s) could not be validated:\n" + dead.joined(separator: "\n"))
    }

    /// The rules file points with a bare sign at the headings of the architecture
    /// documents; its header's own notation (a sign, then `X`) names no section.
    private func scanRules(_ text: String) throws -> (read: Int, dead: [String]) {
        let architecture = try architectureHeadings()
        let tails = Self.tails(of: Self.softJoined(text)).map(\.tail)
        let dead = tails.filter { !$0.hasPrefix(" X ") && Self.resolve($0, headings: architecture) == nil }
        return (tails.count, dead.map { "AGENTS.md — \u{A7} \(Self.excerpt($0))" })
    }

    func testEverySectionTheRulesFileNamesExists() throws {
        let dead = try scanRules(requireRules()).dead
        XCTAssertTrue(dead.isEmpty, "\(dead.count) pointer(s) of the rules file arrive nowhere:\n" + dead.joined(separator: "\n"))
    }

    // MARK: - 2. Every named path exists

    private struct PathScan { var read = 0, modulesExpanded = 0, tweaksExpanded = 0; var dead: [String] = [] }

    /// Every file name of the checkout, for a bare `Name.swift`.
    private func treeFileNames() -> Set<String> {
        let skip: Set<String> = [".git", ".build", "build", ".backstage", "DerivedData", ".superpowers"]
        var names: Set<String> = []
        let walk = FileManager.default.enumerator(at: RepoSource.root, includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles])
        while let url = walk?.nextObject() as? URL {
            if skip.contains(url.lastPathComponent) { walk?.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false { names.insert(url.lastPathComponent) }
        }
        return names
    }

    private func directories(under relative: String) -> [String] {
        let dir = RepoSource.root.appendingPathComponent(relative).path
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    private func scanPaths() throws -> PathScan {
        var scan = PathScan()
        let roots: Set = ["Sources", "Tests", "Scripts", "Resources", "Architecture"]
        let sourceDirectories = Set(directories(under: "Sources"))
        let modules = directories(under: "Sources/Modules"), tweaks = directories(under: "Sources/Tweaks")
        let names = treeFileNames()
        XCTAssertFalse(modules.isEmpty, "Sources/Modules lists nothing — `<Module>` would expand over nothing")
        XCTAssertFalse(tweaks.isEmpty, "Sources/Tweaks lists nothing — `<Tweak>` would expand over nothing")
        // Any other `<…>` names a family, not a file, so it is not read as a path.
        let span = Self.regex("`([^`\n]+)`"), lineSuffix = Self.regex(#"^(.+):\d+(?:[-,]\d+)*$"#)
        let family = Self.regex("<(?!Module>|Tweak>)[^>]*>")
        for file in try standingDocuments() {
            var fenced = false
            for line in try RepoSource.lines(of: file) {
                if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle(); continue }
                guard !fenced else { continue }
                for match in span.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    var token = (line as NSString).substring(with: match.range(at: 1))
                    guard !token.contains(where: \.isWhitespace), let first = token.first, !"/~$<".contains(first),
                          family.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) == nil else { continue }
                    let withLine = lineSuffix.firstMatch(in: token, range: NSRange(token.startIndex..., in: token))
                    if let withLine { token = (token as NSString).substring(with: withLine.range(at: 1)) }
                    let head = String(token.prefix { $0 != "/" })
                    if ["Engine", "UI", "Logic"].contains(head), token.contains("/") || token.hasSuffix(".swift") {
                        scan.dead.append("\(file) — `\(token)` is written from inside a module; write the path from the root"); continue
                    }
                    var targets: [String]
                    if roots.contains(head) { targets = [token] }
                    else if sourceDirectories.contains(head) { targets = ["Sources/" + token] }
                    else if !token.contains("/") && token.hasSuffix(".swift") { targets = [] }
                    else { continue }
                    scan.read += 1
                    if withLine != nil { scan.dead.append("\(file) — `\(token)` carries a line number; name a symbol"); continue }
                    if targets.first?.contains("<Module>") == true { scan.modulesExpanded += 1; targets = modules.map { targets[0].replacingOccurrences(of: "<Module>", with: $0) } }
                    if targets.first?.contains("<Tweak>") == true { scan.tweaksExpanded += 1; targets = tweaks.map { targets[0].replacingOccurrences(of: "<Tweak>", with: $0) } }
                    if targets.isEmpty ? !names.contains(token)
                        : !targets.allSatisfy({ FileManager.default.fileExists(atPath: RepoSource.root.appendingPathComponent($0).path) }) {
                        scan.dead.append("\(file) — `\(token)` is not in the tree")
                    }
                }
            }
        }
        return scan
    }

    func testEveryPathTheStandingDocumentsNameExists() throws {
        let scan = try scanPaths()
        XCTAssertGreaterThan(scan.read, 0, "no backticked path was read — the check is over nothing")
        XCTAssertGreaterThan(scan.modulesExpanded, 0, "no `<Module>` path was read — the per-module rows went unchecked")
        XCTAssertGreaterThan(scan.tweaksExpanded, 0, "no `<Tweak>` path was read — the per-tweak rows went unchecked")
        XCTAssertTrue(scan.dead.isEmpty, "\(scan.dead.count) path(s) arrive nowhere:\n" + scan.dead.joined(separator: "\n"))
    }

    // MARK: - 3. The structure the pointers need

    func testTheHubLinksExactlyThePagesOnDisk() throws {
        let linked = try hubLinks().map(\.file), onDisk = pagesOnDisk()
        XCTAssertFalse(linked.isEmpty, "the hub links no page")
        XCTAssertEqual(linked.count, Set(linked).count, "a page is linked twice: \(linked)")
        XCTAssertEqual(Set(linked).subtracting(onDisk).sorted(), [], "the hub links page(s) that do not exist")
        XCTAssertEqual(Set(onDisk).subtracting(linked).sorted(), [], "page(s) on disk the hub does not link")
    }

    func testEachPageOpensWithItsLinkTextAndIsNamedAfterIt() throws {
        for (text, file) in try hubLinks() {
            let first = try page(file).components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            XCTAssertTrue(first.hasPrefix("# "), "Architecture/\(file) does not open with an H1: \(first.debugDescription)")
            let h1 = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(h1, text, "Architecture/\(file): the H1 differs from the hub's link text")
            let camel = h1.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            XCTAssertEqual(file, camel + ".md", "Architecture/\(file) is not the H1 \(h1.debugDescription) in UpperCamelCase")
        }
    }

    func testNoHeadingIsWrittenTwiceAcrossTheHubAndItsPages() throws {
        var owners: [String: [String]] = [:]
        for file in ["ARCHITECTURE.md"] + (try hubLinks().map { "Architecture/" + $0.file }) {
            for heading in Self.headings(in: try RepoSource.text(of: file)) { owners[heading, default: []].append(file) }
        }
        let twice = owners.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        XCTAssertTrue(twice.isEmpty, "heading(s) written more than once — a pointer at them names two places:\n"
            + twice.map { "\($0.key) — \($0.value.joined(separator: ", "))" }.joined(separator: "\n"))
    }

    /// A hub line says in one sentence what its page is for; the headings are the
    /// page's to list, and a list of them here is a second copy to keep.
    func testEachHubLineStatesOnePurposeAndPointsAtNothing() throws {
        let shape = Self.regex(#"^- \[[^\]]+\]\(Architecture/[A-Za-z0-9]+\.md\) \x{2014} (\S.*)$"#)
        let breaks = Self.regex(#"\. [A-Z]"#)
        var wrong: [String] = []
        for line in try hub().components(separatedBy: "\n") where line.contains("](Architecture/") {
            guard let match = shape.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                wrong.append("no purpose after the link: \(line.prefix(80))"); continue
            }
            let purpose = (line as NSString).substring(with: match.range(at: 1))
            if purpose.contains("\u{A7}") { wrong.append("carries a section sign: \(line.prefix(80))") }
            if !purpose.hasSuffix(".") { wrong.append("does not end in a full stop: \(line.prefix(80))") }
            if breaks.firstMatch(in: purpose, range: NSRange(purpose.startIndex..., in: purpose)) != nil { wrong.append("holds more than one sentence: \(line.prefix(80))") }
        }
        XCTAssertTrue(wrong.isEmpty, "\(wrong.count) hub line(s) do not read as a list item, a link and a purpose:\n" + wrong.joined(separator: "\n"))
    }

    // MARK: - 4. The rules file's ceiling

    func testTheRulesFileStaysInsideItsCeiling() throws {
        let text = try requireRules()
        let size = text.utf8.count
        let ceiling = 10_240
        XCTAssertGreaterThan(size, 4_000, "the rules file is \(size) bytes — an emptied file is under every ceiling")
        XCTAssertLessThanOrEqual(size, ceiling, "the rules file is \(size) bytes, ceiling \(ceiling) — move a story to a page")
    }

    // MARK: - 5. The canaries

    func testNoCheckIsGreenOverNothing() throws {
        let code = try scanSwift()
        XCTAssertGreaterThan(code.files, 200, "only \(code.files) Swift files read")
        XCTAssertGreaterThan(code.architecturePointers, 20, "only \(code.architecturePointers) ARCHITECTURE pointers found in Swift")
        XCTAssertGreaterThan(try architectureHeadings().count, 20, "the hub's and its pages' headings were not read")
        XCTAssertGreaterThan(try scanPaths().read, 0, "no backticked path was read")
    }

    func testTheRulesChecksReadTheirSubjects() throws {
        let text = try requireRules()
        XCTAssertGreaterThan(Self.headings(in: text).count, 3, "the rules file's headings were not read")
        XCTAssertGreaterThan(try scanRules(text).read, 20, "too few pointers read from the rules file")
    }

    func testResolveTakesAHeadingOnlyWhereItEnds() {
        for ok in ["Removal", "removal.", "Removal, and", "Removal`", "`Removal`.", "Removal \u{A7} Other", "Removal \u{2192} x", "Removal\n", "Removal |", "Removal| next"] {
            XCTAssertEqual(Self.resolve(ok, headings: ["removal"]), "removal", ok)
        }
        for bad in ["Removals", "Removal takes its traces", "Removalx.", "Nothing"] {
            XCTAssertNil(Self.resolve(bad, headings: ["removal"]), bad)
        }
    }
}
