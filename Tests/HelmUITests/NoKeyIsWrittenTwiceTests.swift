import XCTest
@testable import HelmUI

/// **A key written twice is a string nobody can see is wrong.**
///
/// Every other check on these files reads them through
/// `NSDictionary(contentsOfFile:)`, and so does macOS: a repeated key is
/// resolved silently, the last one winning, and no count changes. So
/// `StringsCoverageTests` passes over a duplicate, `plutil -lint` passes over
/// it, and the app draws the wrong sentence.
///
/// It happened while the tab-label pop-up was being restored: `Names` was given
/// to the option that draws a tab's name, and `HostsStr.names` had held it since
/// the hosts file's table shipped — «Имена», the column of hostnames. Russian
/// drew «Имена» in a pop-up about tabs, and eight files linted clean. That is
/// «one English key means one thing» read from the other side: the rule was
/// prose with nothing under it.
///
/// The file is read as **lines** for exactly that reason. Any check that parses
/// it into a table first is a check that cannot fail here.
final class NoKeyIsWrittenTwiceTests: XCTestCase {

    func testNoLanguageWritesAKeyTwice() {
        for language in AppLanguage.allCases {
            var seen: [String: Int] = [:]
            for key in keys(of: language) { seen[key, default: 0] += 1 }
            let repeated = seen.filter { $0.value > 1 }.keys.sorted()
            XCTAssertTrue(repeated.isEmpty, """
                \(language.rawValue).lproj writes \(repeated.count) key(s) twice, and the \
                later one wins in silence: \(repeated.prefix(5))
                """)
        }
    }

    /// The reading has to be able to see a duplicate at all. Proven on a fixture
    /// rather than on the tree, because the tree is expected to be clean — and a
    /// scan that reads nothing is clean too.
    func testTheReadingCanSeeADuplicate() {
        let fixture = """
        "One" = "Один";
        "Two" = "Два";
        "One" = "Единица";
        """
        XCTAssertEqual(Self.keys(inLines: fixture.split(separator: "\n").map(String.init)),
                       ["One", "Two", "One"],
                       "a repeated key was collapsed before it could be counted")
    }

    /// Every key each file declares, in the order it declares them — including
    /// the repeats, which is the whole point.
    private func keys(of language: AppLanguage) -> [String] {
        guard let path = Localized.stringsFile(for: language)?.path,
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            XCTFail("no Localizable.strings for \(language.rawValue)")
            return []
        }
        return Self.keys(inLines: text.split(separator: "\n").map(String.init))
    }

    /// A key is what stands between the first quote of a line and the quote
    /// before its `=`. Escaped quotes inside a key would break that, and none of
    /// the eight files has one — `testNoLanguageWritesAKeyTwice` would report a
    /// truncated key rather than miss a real duplicate, which is the direction a
    /// wrong reading should fail in.
    private static func keys(inLines lines: [String]) -> [String] {
        lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let end = trimmed.range(of: "\" = ") else { return nil }
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end.lowerBound])
        }
    }
}
