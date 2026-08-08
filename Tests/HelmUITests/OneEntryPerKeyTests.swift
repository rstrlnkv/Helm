import XCTest
@testable import HelmUI

/// A key written twice in one `.strings` file, which nothing else can see.
///
/// `NSDictionary(contentsOfFile:)` keeps the **last** entry for a repeated key
/// and says nothing, so every check the app already had passed over eight of
/// them: `plutil -lint` calls the file valid, `StringsCoverageTests` reads the
/// same collapsed dictionary and finds every key present, and English shows
/// nothing at all because `L()` falls back to the key. Which of the two
/// translations shipped was decided by which one was further down the file.
///
/// So this reads the files as **text**, line by line, which is the one way to
/// see an entry that the loader has already thrown away. The eight it was
/// written for were `General`, `Media`, `Network`, `Paused`, `Show`,
/// `Show Quit button`, `Show Settings button` and `System` — four appended by
/// the glyph picker, the rest by three later features, each re-adding a key
/// that was already there under a translation written for something else.
///
/// **A duplicate key is CLAUDE.md's "one English key means one thing" rule
/// wearing a disguise**: two entries under one key are two meanings that
/// somebody translated separately, and the file quietly picks one.
final class OneEntryPerKeyTests: XCTestCase {

    /// The key of `"key" = "value";`, with its escapes resolved the way the
    /// loader resolves them — four keys quote a control by name (`\"Date
    /// Added\"`) and would not otherwise match what the dictionary holds.
    private func key(inLine line: String) -> String? {
        guard line.hasPrefix("\"") else { return nil }
        var key = ""
        var escaped = false
        for character in line.dropFirst() {
            if escaped {
                key.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return key
            } else {
                key.append(character)
            }
        }
        return nil
    }

    func testNoKeyIsWrittenTwiceInOneStringsFile() throws {
        for language in AppLanguage.allCases {
            let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path,
                                     "no Localizable.strings for \(language.rawValue)")
            let text = try String(contentsOfFile: path, encoding: .utf8)

            var lines: [String: [Int]] = [:]
            for (offset, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false).enumerated() {
                guard let key = key(inLine: String(line)) else { continue }
                lines[key, default: []].append(offset + 1)
            }

            // Read as text, checked against the file read as data: without this
            // a parser that recognised nothing would report no duplicates and
            // pass for ever.
            let loaded = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertGreaterThan(loaded.count, 100, "\(language.rawValue).lproj carries almost nothing")
            XCTAssertEqual(Set(lines.keys), Set(loaded.keys),
                           "\(language.rawValue): the lines read as text are not the entries "
                           + "the loader sees, so this check is measuring its own parser")

            let repeated = lines.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
            XCTAssertTrue(repeated.isEmpty,
                          "\(language.rawValue).lproj writes \(repeated.count) key(s) more than "
                          + "once. The loader keeps the last one and says nothing, so which "
                          + "translation ships is decided by file order — give each meaning its "
                          + "own English key, or delete the entry that is not the one:\n"
                          + repeated.map { "  \"\($0.key)\" on lines "
                              + $0.value.map(String.init).joined(separator: ", ") }
                              .joined(separator: "\n"))
        }
    }
}
