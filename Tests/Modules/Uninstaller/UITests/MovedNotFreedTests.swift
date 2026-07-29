import XCTest
import HelmUI
@testable import Module_Uninstaller_UI

/// The uninstaller may not say space came back.
///
/// The button says "Move to Trash", and one click later the screen said
/// "Removed — 4 KB freed". `~/.Trash` is a folder on the same volume: the bytes
/// changed parent and the disk gained nothing until somebody empties it.
///
/// Disk landed this correction first, and its verb and noun per language were
/// read out of Finder's own `AL13` key rather than translated again — so this
/// compares the two tables instead of asserting a second phrasing of my own.
/// `L()` answers in whichever language the machine is set to, so eight
/// languages cannot be exercised through the accessor; the tables are read from
/// the source, which is where the defect was.
final class MovedNotFreedTests: XCTestCase {

    private static let languages = ["ru", "es", "fr", "de", "ja", "zh", "pt"]

    // MARK: - The wording

    /// Word for word what Disk says, in all eight.
    func testTheOutcomeIsSpelledTheWayDiskAlreadySpellsIt() throws {
        let mine = try table(in: uninstallerStrings(), function: "movedToTrash")
        let disk = try table(in: diskStrings(), function: "movedToTrash")

        XCTAssertEqual(mine, disk,
                       "a second phrasing of a sentence macOS itself has words for")
        XCTAssertEqual(mine["en"], "Moved to the Trash — \\(size)")
        for language in Self.languages {
            XCTAssertNotNil(mine[language], "\(language) is missing")
        }
    }

    /// The bar on the review screen, one click before it happens. Disk has no
    /// counterpart for this one, so what is pinned is the shape: eight
    /// languages, and each naming the destination rather than a gain.
    func testThePreActionBarNamesTheDestination() throws {
        let bar = try table(in: uninstallerStrings(), function: "toTrash")

        XCTAssertEqual(bar["en"], "To the Trash — \\(size)")
        for language in Self.languages {
            let text = try XCTUnwrap(bar[language], "\(language) is missing")
            XCTAssertTrue(text.hasSuffix("\\(size)"), "\(language): \(text)")
        }
    }

    /// A table nobody reads would satisfy both tests above, so the accessors are
    /// checked against the entry for whatever language this machine is in —
    /// skipping on anything but English would leave this unrun on the machine
    /// it was written on, which is the one place it has ever been run.
    func testTheAccessorsReadFromThoseTables() throws {
        let source = try uninstallerStrings()
        let size = Bytes(4096)

        for (name, produced) in [("movedToTrash", UnStr.movedToTrash(size)),
                                 ("toTrash", UnStr.toTrash(size))] {
            let entry = try XCTUnwrap(table(in: source, function: name)[AppLanguage.current.rawValue],
                                      "\(name) has no entry for \(AppLanguage.current.rawValue)")
            XCTAssertEqual(produced, entry.replacingOccurrences(of: "\\(size)", with: size),
                           "\(name) does not read from its own table")
        }
    }

    /// And nothing anywhere in the module still promises freed space.
    func testNoStringInTheModuleStillClaimsSpaceCameBack() throws {
        let source = try uninstallerStrings()

        for claim in ["Freed", "freed", "Frees", "Освобожд", "freigegeben",
                      "liberados", "libérés", "释放", "解放"] {
            XCTAssertFalse(source.contains("\"\(claim)") || source.contains(" \(claim)"),
                           "\(claim): the files are in ~/.Trash, on the same volume")
        }
    }

    // MARK: - Reading the tables

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Uninstaller
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
    }

    private func uninstallerStrings() throws -> String {
        try String(contentsOf: repoRoot()
            .appendingPathComponent("Sources/Modules/Uninstaller/UI/UninstallerStrings.swift"),
                   encoding: .utf8)
    }

    private func diskStrings() throws -> String {
        try String(contentsOf: repoRoot()
            .appendingPathComponent("Sources/Modules/Disk/UI/DiskStrings.swift"),
                   encoding: .utf8)
    }

    /// `static func name(_ size: String) -> String { L("…", [.ru: "…", …]) }`
    /// as a language → text dictionary, English under "en".
    private func table(in source: String, function: String) throws -> [String: String] {
        let line = try XCTUnwrap(
            source.components(separatedBy: "\n").first { $0.contains("func \(function)(") },
            "\(function) is not declared")
        let quoted = try XCTUnwrap(NSRegularExpression(pattern: "\"([^\"]*)\""))
        let tagged = try XCTUnwrap(NSRegularExpression(pattern: "\\.([a-z]{2}): \"([^\"]*)\""))
        let whole = NSRange(line.startIndex..., in: line)

        var out: [String: String] = [:]
        if let first = quoted.firstMatch(in: line, range: whole),
           let range = Range(first.range(at: 1), in: line) {
            out["en"] = String(line[range])
        }
        for match in tagged.matches(in: line, range: whole) {
            guard let key = Range(match.range(at: 1), in: line),
                  let value = Range(match.range(at: 2), in: line) else { continue }
            out[String(line[key])] = String(line[value])
        }
        return out
    }
}
