import HelmTestSupport
import XCTest

/// Every directory the map in `ARCHITECTURE.md` names must be a directory, every
/// directory directly under `Sources` and `Tests` must be named by a row, and every row
/// must point at a heading of a page the hub links.
///
/// **Why this is a test.** `DocumentsNameTheTreeTests` reads the backticked
/// names in the standing documents, but only those shaped like a symbol or a
/// `.swift` file — a path with slashes in it falls straight through, and so does
/// a row of a table. The map moved out of `CLAUDE.md` into `ARCHITECTURE.md`
/// when the documents were split by mood: a table saying where a thing lives
/// describes how Helm is built, and that is the other document's genre. Moving
/// it did not make it checkable — `TheDocumentsDoNotDriftTests` drops the block a
/// table sits in whenever the block's first line begins with `|`, before it
/// reads a word — so this is still the only thing standing between a renamed
/// directory and the next reader being sent to it.
///
/// **`<Module>` is expanded, not skipped.** A row naming a per-module
/// directory is a claim about *every* module, and the manifest already requires
/// all four of them; checking one module would pass while the others were wrong.
///
/// **The third cell is read here and nowhere else.** A bare section sign in a table
/// cell is read by no other guard: the sections guard reads on the hub only the named
/// spelling with a terminator, and bare signs only on its link lines. So the third cell
/// is read with that guard's own `Parser.tails(of:)` and `Parser.resolve(_:headings:)`,
/// against the headings of the pages the hub links and not of the hub, since a row
/// pointing at a hub heading names no page. A link in the cell is refused, because the
/// pages the hub links are counted from its links and a second link would count one twice.
/// The number of signs in a row must equal the number of pointers read from its third
/// cell, so a sign in another cell is red and not passed over.
///
/// **What it prints.** On every run that finds the map, one line counting the rows, the
/// directories, the linked pages and their headings. Then, for the tree against the map: a
/// directory of `Sources` or `Tests` that no row names, equal or under; a row with no sign in
/// its third cell, with a sign outside it, or with a link in it; a row whose pointer is no
/// heading of a linked page; a module with no page of its name among the links; a map that is
/// no table or has no rows, a root with no directory, or pages with no heading, each of which
/// would leave every other verdict over nothing.
final class TheMapNamesRealDirectoriesTests: XCTestCase {

    private static let heading = "Where things are"

    private typealias Parser = EverySectionNamedInTheDocumentsExistsTests.Parser

    /// The rows of the map, without the header and the separator line.
    ///
    /// A hub without the section fails the test here and gives no rows; a section
    /// without a table gives no rows and says nothing. Either way the caller's
    /// assertion that the map named paths is red, so no run passes over no subject.
    private func mapRows() throws -> [String] {
        let hub = try RepoSource.text(of: "ARCHITECTURE.md")
        guard let table = StandingDocuments.section(Self.heading, in: hub) else {
            XCTFail("the map is gone from ARCHITECTURE.md — delete this test or put it back")
            return []
        }
        return Array(table.filter { $0.hasPrefix("|") }.dropFirst(2))
    }

    /// The modules the tree actually has, so a per-module row is checked
    /// against all of them rather than against a name written here.
    private func modules() throws -> [String] {
        let names = try Self.directories(under: "Sources/Modules")
        XCTAssertFalse(names.isEmpty, "Sources/Modules is empty — nothing was checked")
        return names
    }

    /// The names of the directories directly under `root`, sorted, hidden ones left out.
    static func directories(under root: String) throws -> [String] {
        let dir = RepoSource.root.appendingPathComponent(root)
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }
            .filter { name in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: dir.appendingPathComponent(name).path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
            .sorted()
    }

    func testEveryDirectoryTheMapNamesExists() throws {
        let rows = try mapRows()
        let modules = try modules()
        let paths = Self.paths(inRows: rows, modules: modules)
        XCTAssertFalse(paths.isEmpty, "the map named no paths — the table shape changed")

        for path in paths {
            var isDirectory: ObjCBool = false
            let full = RepoSource.root.appendingPathComponent(path).path
            let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
            XCTAssertTrue(exists && isDirectory.boolValue,
                          "the map says `\(path)`, and the tree has no such directory")
        }

        // Without a module a `<Module>` row names nothing; with one it names itself once.
        XCTAssertGreaterThan(paths.count, Self.paths(inRows: rows, modules: []).count,
                             "no `<Module>` row was expanded — the per-module half of the map went unchecked")
        XCTAssertGreaterThan(paths.count, Self.paths(inRows: rows, modules: Array(modules.prefix(1))).count,
                             "expansion produced nothing: every row was checked once, as a literal")
    }

    func testEveryDirectoryOfTheTreeIsMappedToAPageTheHubLinks() throws {
        let hub = try RepoSource.text(of: "ARCHITECTURE.md")
        guard let table = StandingDocuments.section(Self.heading, in: hub) else {
            XCTFail("the map is gone from ARCHITECTURE.md — delete this test or put it back")
            return
        }
        let linked = StandingDocuments.linkedPages(in: hub)
        var headings: [String] = []
        for page in linked {
            headings += StandingDocuments.headings(in: try RepoSource.text(of: page))
        }
        let directories = try ["Sources", "Tests"].flatMap { root in
            try Self.directories(under: root).map { root + "/" + $0 }
        }
        let modules = try modules()

        let lines = table.filter { $0.hasPrefix("|") }
        print("the map: \(max(0, lines.count - 2)) row(s), \(directories.count) directories under Sources and Tests, "
              + "\(linked.count) linked page(s) with \(headings.count) heading(s)")

        let defects = Self.mapDefects(tableLines: lines, directories: directories, modules: modules,
                                      pageHeadings: headings)
            + Self.modulePageDefects(modules: modules, linkedPages: linked)
        XCTAssertTrue(defects.isEmpty,
                      "\(defects.count) defect(s) in the map:\n\(defects.joined(separator: "\n"))")
    }

    // MARK: - The reading, over text and names only

    /// The cells of a table line, trimmed, without the empty pieces outside the outer bars.
    static func cells(of line: String) -> [String] {
        var parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// The paths the second cell of each row names, `<Module>` expanded over `modules`,
    /// a trailing slash dropped.
    static func paths(inRows rows: [String], modules: [String]) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "`([^`]*/[^`]*)`")
        var out: [String] = []
        for row in rows {
            let cells = Self.cells(of: row)
            guard cells.count > 1 else { continue }
            let cell = cells[1]
            for match in pattern.matches(in: cell, range: NSRange(cell.startIndex..., in: cell)) {
                guard let span = Range(match.range(at: 1), in: cell) else { continue }
                let path = String(cell[span])
                let expanded = path.contains("<Module>")
                    ? modules.map { path.replacingOccurrences(of: "<Module>", with: $0) }
                    : [path]
                out += expanded.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            }
        }
        return out
    }

    /// What the map gets wrong of the tree, one line each. `tableLines` are the lines of
    /// the map that begin with `|`, header and separator first; `directories` are the
    /// directories directly under `Sources` and `Tests` as `Sources/Name`; `pageHeadings`
    /// are the headings of the pages the hub links.
    static func mapDefects(tableLines: [String], directories: [String], modules: [String],
                           pageHeadings: [String]) -> [String] {
        guard tableLines.count >= 2, tableLines[1].allSatisfy({ "|-: \t".contains($0) }) else {
            return ["the map is not a table with a header line and a separator line"]
        }
        let rows = Array(tableLines.dropFirst(2))
        guard !rows.isEmpty else { return ["the map has a header and no row"] }

        var defects: [String] = []
        for root in ["Sources", "Tests"] where !directories.contains(where: { $0.hasPrefix(root + "/") }) {
            defects.append("the tree gave no directory under \(root) — no row was checked against it")
        }
        if pageHeadings.isEmpty {
            defects.append("the pages the hub links gave no heading — every pointer would read as dead")
        }
        let headings = pageHeadings.sorted { $0.count > $1.count }

        let mapped = paths(inRows: rows, modules: modules)
        for directory in directories.sorted()
        where !mapped.contains(where: { $0 == directory || $0.hasPrefix(directory + "/") }) {
            defects.append("`\(directory)` is a directory of the tree and no row of the map names it")
        }

        for row in rows {
            let cells = Self.cells(of: row)
            let name = cells.first ?? ""
            let third = cells.count > 2 ? cells[2] : ""
            let tails = Parser.tails(of: third)
            let signs = row.components(separatedBy: "\u{A7}").count - 1
            if third.contains("](") {
                defects.append("row `\(name)` names its page by a link; the cell holds a bare section sign")
            }
            if tails.isEmpty {
                defects.append("row `\(name)` names no page — its third cell holds no section sign")
            }
            if signs != tails.count {
                defects.append("row `\(name)` holds \(signs) section sign(s) and its third cell \(tails.count)")
            }
            for tail in tails where Parser.resolve(tail, headings: headings) == nil {
                defects.append("row `\(name)` points at `\(tail.trimmingCharacters(in: .whitespaces))`, "
                    + "no heading of a page the hub links")
            }
        }
        return defects
    }

    /// The modules that have no page of their own name among the pages the hub links.
    static func modulePageDefects(modules: [String], linkedPages: [String]) -> [String] {
        modules.sorted().compactMap { module in
            linkedPages.contains("Architecture/\(module).md")
                ? nil
                : "module \(module) has no page Architecture/\(module).md among the pages the hub links"
        }
    }

    // MARK: - Fixtures

    private static let fixtureTable = [
        "| What a change touches | Where it lives | Its page |",
        "|---|---|---|",
        "| engines | `Sources/Modules/<Module>/Engine/` | \u{A7} Alpha |",
        "| shared | `Sources/Shared/` | \u{A7} Alpha two, \u{A7} Beta |",
        "| checks | `Tests/One/`, `Tests/Two/` | \u{A7} Beta |",
    ]
    private static let fixtureDirectories = ["Sources/Modules", "Sources/Shared", "Tests/One", "Tests/Two"]
    private static let fixtureModules = ["X", "Y"]
    private static let fixtureHeadings = ["Alpha", "Alpha two", "Beta"]

    private static func fixtureDefects(table: [String]? = nil, directories: [String]? = nil,
                                       headings: [String]? = nil) -> [String] {
        mapDefects(tableLines: table ?? fixtureTable, directories: directories ?? fixtureDirectories,
                   modules: fixtureModules, pageHeadings: headings ?? fixtureHeadings)
    }

    func testAMapThatNamesEveryDirectoryAndPointsAtRealHeadingsIsClean() {
        XCTAssertEqual(Self.fixtureDefects(), [])
    }

    func testARowRemovedLeavesItsDirectoriesUnnamed() {
        var table = Self.fixtureTable
        table.removeLast()
        let got = Self.fixtureDefects(table: table)
        XCTAssertEqual(got.count, 2, "two directories lost their row: \(got)")
        XCTAssertTrue(got.contains { $0.contains("`Tests/One`") && $0.contains("no row of the map names it") })
        XCTAssertTrue(got.contains { $0.contains("`Tests/Two`") })
    }

    func testADirectoryThatOnlyStartsLikeAMappedOneIsNotNamedByIt() {
        let got = Self.fixtureDefects(directories: Self.fixtureDirectories + ["Sources/Share"])
        XCTAssertEqual(got.count, 1, "\(got)")
        XCTAssertTrue(got.first?.contains("`Sources/Share`") ?? false)
    }

    func testAPathUnderAMappedPathNamesTheDirectoryAbove() {
        // The row names Sources/Modules/<Module>/Engine; the directory is Sources/Modules.
        XCTAssertEqual(Self.fixtureDefects(directories: ["Sources/Modules", "Tests/One", "Tests/Two"]), [])
    }

    func testARowWithAnEmptyThirdCellOrNoThirdCellNamesNoPage() {
        var empty = Self.fixtureTable
        empty[3] = "| shared | `Sources/Shared/` |  |"
        let a = Self.fixtureDefects(table: empty)
        XCTAssertEqual(a.count, 1, "\(a)")
        XCTAssertTrue(a.first?.contains("row `shared` names no page") ?? false)

        var short = Self.fixtureTable
        short[3] = "| shared | `Sources/Shared/` |"
        let b = Self.fixtureDefects(table: short)
        XCTAssertEqual(b.count, 1, "\(b)")
        XCTAssertTrue(b.first?.contains("row `shared` names no page") ?? false)
    }

    func testAPointerAtNoHeadingOfALinkedPageIsDead() {
        var dead = Self.fixtureTable
        dead[4] = "| checks | `Tests/One/`, `Tests/Two/` | \u{A7} Gamma |"
        let a = Self.fixtureDefects(table: dead)
        XCTAssertEqual(a.count, 1, "\(a)")
        XCTAssertTrue(a.first?.contains("points at `Gamma`") ?? false)

        // A heading that is only the start of the pointer's text is not the heading.
        var longer = Self.fixtureTable
        longer[4] = "| checks | `Tests/One/`, `Tests/Two/` | \u{A7} Beta twelve |"
        XCTAssertEqual(Self.fixtureDefects(table: longer).count, 1)

        // Of two headings where one is the start of the other, the longer one is found.
        XCTAssertEqual(Self.fixtureDefects(headings: ["Alpha two", "Alpha", "Beta"]), [])
    }

    func testASignInAnotherCellIsNotPassedOver() {
        var table = Self.fixtureTable
        table[2] = "| engines \u{A7} | `Sources/Modules/<Module>/Engine/` | \u{A7} Alpha |"
        let got = Self.fixtureDefects(table: table)
        XCTAssertEqual(got.count, 1, "\(got)")
        XCTAssertTrue(got.first?.contains("holds 2 section sign(s) and its third cell 1") ?? false)

        var onlyElsewhere = Self.fixtureTable
        onlyElsewhere[2] = "| engines | `Sources/Modules/<Module>/Engine/ \u{A7} Alpha` |  |"
        XCTAssertGreaterThanOrEqual(Self.fixtureDefects(table: onlyElsewhere).count, 2)
    }

    func testALinkInTheThirdCellIsRefused() {
        var table = Self.fixtureTable
        table[2] = "| engines | `Sources/Modules/<Module>/Engine/` | [Alpha](Architecture/Alpha.md) |"
        let got = Self.fixtureDefects(table: table)
        XCTAssertTrue(got.contains { $0.contains("by a link") }, "\(got)")
    }

    func testAMapOrATreeOrPagesWithNothingInThemIsRed() {
        XCTAssertEqual(Self.fixtureDefects(table: Array(Self.fixtureTable.prefix(2))).count, 1, "a header and no row")
        XCTAssertEqual(Self.fixtureDefects(table: []).count, 1, "no table")
        var noSeparator = Self.fixtureTable
        noSeparator.remove(at: 1)
        XCTAssertEqual(Self.fixtureDefects(table: noSeparator).count, 1, "no separator line")

        let noSources = Self.fixtureDefects(directories: ["Tests/One", "Tests/Two"])
        XCTAssertTrue(noSources.contains { $0.contains("no directory under Sources") }, "\(noSources)")
        let noTests = Self.fixtureDefects(directories: ["Sources/Modules", "Sources/Shared"])
        XCTAssertTrue(noTests.contains { $0.contains("no directory under Tests") }, "\(noTests)")

        let noHeadings = Self.fixtureDefects(headings: [])
        XCTAssertTrue(noHeadings.contains { $0.contains("gave no heading") }, "\(noHeadings)")
        XCTAssertGreaterThan(noHeadings.count, 1, "every pointer reads as dead as well: \(noHeadings)")
    }

    func testAModuleWithoutAPageOfItsNameIsRed() {
        XCTAssertEqual(Self.modulePageDefects(modules: ["A", "B"],
                                              linkedPages: ["Architecture/A.md", "Architecture/B.md"]), [])
        let got = Self.modulePageDefects(modules: ["A", "B"], linkedPages: ["Architecture/A.md"])
        XCTAssertEqual(got.count, 1)
        XCTAssertTrue(got.first?.contains("module B") ?? false)
        XCTAssertEqual(Self.modulePageDefects(modules: ["A", "B"], linkedPages: []).count, 2, "no page linked at all")
    }
}
