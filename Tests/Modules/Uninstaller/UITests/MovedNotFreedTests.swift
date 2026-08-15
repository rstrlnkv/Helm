import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Uninstaller_UI

/// The uninstaller may not say space came back.
///
/// The button says "Move to Trash", and one click later the screen said
/// "Removed — 4 KB freed". `~/.Trash` is a folder on the same volume: the bytes
/// changed parent and the disk gained nothing until somebody empties it.
///
/// Disk landed this correction first, and its verb and noun per language were
/// read out of Finder's own `AL13` key rather than translated again — so this
/// compares the four tables instead of asserting a second phrasing of my own.
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

    /// **Four modules say this sentence, and the guard used to hold two of
    /// them.** `DupStr.movedToTrash`'s own doc claimed word-for-word agreement
    /// while its es table had drifted to a colon and its de table to an en
    /// dash — a promise written in prose with nothing under it. Duplicates must
    /// match Disk exactly; Leftovers carries a count as well as a size, so what
    /// is pinned there is the verb phrase — the part Finder's `AL13` key
    /// settled — opening the sentence in every language.
    func testAllFourModulesOpenWithDisksVerbPhrase() throws {
        let disk = try table(in: diskStrings(), function: "movedToTrash")
        XCTAssertFalse(disk.isEmpty, "the Disk table was not found — this compares nothing")

        let duplicates = try table(in: moduleStrings("Duplicates"), function: "movedToTrash")
        XCTAssertEqual(duplicates, disk,
                       "Duplicates has drifted from the sentence its own doc promises")

        let leftovers = try table(in: moduleStrings("Leftovers"), function: "movedToTrash")
        for (language, sentence) in disk {
            let verb = try XCTUnwrap(sentence.components(separatedBy: " — ").first,
                                     "\(language): the Disk sentence has no verb phrase")
            let theirs = try XCTUnwrap(leftovers[language], "\(language) is missing in Leftovers")
            XCTAssertTrue(theirs.hasPrefix(verb), """
                \(language): Leftovers opens «\(theirs)» where Disk's verb phrase \
                is «\(verb)» — the fourth module has drifted.
                """)
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

    private func uninstallerStrings() throws -> String {
        try moduleStrings("Uninstaller")
    }

    private func diskStrings() throws -> String {
        try moduleStrings("Disk")
    }

    /// Every module spells the file the same way, and `RepoSource` walks to the
    /// root from any depth — the hand-counted `deletingLastPathComponent`s this
    /// replaces were a fact about where *this* test sat.
    private func moduleStrings(_ module: String) throws -> String {
        try RepoSource.text(of: "Sources/Modules/\(module)/UI/\(module)Strings.swift")
    }

    /// `static func name(…) -> String { L("…", [.ru: "…", …]) }` as a
    /// language → text dictionary, English under "en".
    ///
    /// Over the function's whole body, not its first line: Leftovers and
    /// Duplicates declare theirs across several lines, and a parser that read
    /// one line answered an empty table — a check that cannot fail. The chunk
    /// ends at the next member, so a neighbouring function's table cannot leak
    /// into this one.
    private func table(in source: String, function: String) throws -> [String: String] {
        let opens = try XCTUnwrap(source.range(of: "static func \(function)("),
                                  "\(function) is not declared")
        let tail = source[opens.upperBound...]
        let end = tail.range(of: "\n    static ")?.lowerBound
            ?? tail.range(of: "\n}")?.lowerBound
            ?? tail.endIndex
        let body = String(source[opens.lowerBound..<end])
        let english = try XCTUnwrap(NSRegularExpression(pattern: "L\\(\"([^\"]*)\""))
        let tagged = try XCTUnwrap(NSRegularExpression(pattern: "\\.([a-z]{2}): \"([^\"]*)\""))
        let whole = NSRange(body.startIndex..., in: body)

        var out: [String: String] = [:]
        if let first = english.firstMatch(in: body, range: whole),
           let range = Range(first.range(at: 1), in: body) {
            out["en"] = String(body[range])
        }
        for match in tagged.matches(in: body, range: whole) {
            guard let key = Range(match.range(at: 1), in: body),
                  let value = Range(match.range(at: 2), in: body) else { continue }
            out[String(body[key])] = String(body[value])
        }
        return out
    }
}
