import HelmTestSupport
import XCTest

/// Every directory the map in `ARCHITECTURE.md` names must be a directory.
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
/// all four of them; checking one module would pass while nine were wrong.
final class TheMapNamesRealDirectoriesTests: XCTestCase {

    private static let heading = "### Where things are"

    /// The rows of the map, as the paths they name.
    ///
    /// Throws rather than returning nothing when the table is gone: an empty
    /// list would let every assertion below pass over no subject at all.
    private func mappedPaths() throws -> [String] {
        let file = RepoSource.root.appendingPathComponent("ARCHITECTURE.md")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw XCTSkip("ARCHITECTURE.md is not in this checkout")
        }
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0 == Self.heading }) else {
            XCTFail("the map is gone from ARCHITECTURE.md — delete this test or put it back")
            return []
        }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { $0.hasPrefix("#") }) ?? rest.endIndex
        let table = lines[(start + 1)..<end]

        let pattern = try NSRegularExpression(pattern: "`([^`]*/[^`]*)`")
        var paths: [String] = []
        for line in table where line.hasPrefix("|") {
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                if let span = Range(match.range(at: 1), in: line) {
                    paths.append(String(line[span]))
                }
            }
        }
        return paths
    }

    /// The modules the tree actually has, so a per-module row is checked
    /// against all of them rather than against a name written here.
    private func modules() throws -> [String] {
        let dir = RepoSource.root.appendingPathComponent("Sources/Modules")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        XCTAssertFalse(names.isEmpty, "Sources/Modules is empty — nothing was checked")
        return names
    }

    func testEveryDirectoryTheMapNamesExists() throws {
        let paths = try mappedPaths()
        XCTAssertFalse(paths.isEmpty, "the map named no paths — the table shape changed")

        let modules = try modules()
        var checked = 0
        var expandedAtLeastOneRow = false

        for path in paths {
            let targets: [String]
            if path.contains("<Module>") {
                expandedAtLeastOneRow = true
                targets = modules.map { path.replacingOccurrences(of: "<Module>", with: $0) }
            } else {
                targets = [path]
            }
            for target in targets {
                var isDirectory: ObjCBool = false
                let full = RepoSource.root.appendingPathComponent(target).path
                let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
                XCTAssertTrue(exists && isDirectory.boolValue,
                              "the map says `\(target)`, and the tree has no such directory")
                checked += 1
            }
        }

        XCTAssertTrue(expandedAtLeastOneRow,
                      "no `<Module>` row was expanded — the per-module half of the map went unchecked")
        XCTAssertGreaterThan(checked, paths.count,
                             "expansion produced nothing: every row was checked once, as a literal")
    }
}
