import XCTest
@testable import HelmUI

/// The other direction of `StringsCoverageTests`.
///
/// That one asks whether every English key reached the other seven files, which
/// catches a translation that was never written. This asks whether anything
/// still *wants* the key — and a key nothing asks for is not merely weight.
///
/// **An orphan is a trap for the next person.** CLAUDE.md's rule is that one
/// English key means one thing, and seventeen keys had already come to mean two
/// each before twelve of them had to be split. The orphans found when this was
/// written were `Medium`, `Small`, `Large`, `Empty`, `Filled`, `Dot`, `Tiny`
/// and `Very small` — left behind when the menu-bar icon's five size names were
/// replaced by S/M/L — plus `System item`, `Extras to basket`, `FOLDERS` and
/// four more. Those are the most reusable words in any interface. The next
/// `L("Medium")`, written about something else entirely, would have silently
/// inherited seven translations describing the size of an icon, and the person
/// who saw it would have been reading Russian.
///
/// English cannot show the fault, which is why it needed a machine: `L()` falls
/// back to the key, so a wrong or stale translation is invisible in the
/// language this app is written in and total in the other seven.
final class NoOrphanTranslationsTests: XCTestCase {

    /// Swift writes `\u{2014}` where the `.strings` file carries `—`, and the
    /// changelog is full of both dashes and curly quotes. Comparing the two
    /// without this reported twenty-seven live keys as dead, and then sixteen
    /// dead ones as live when the same mistake was made the other way round.
    ///
    /// The escaped double quote is the same trap one level in: four changelog
    /// entries quote a control by name — `"Date Added"`, `"1000 KB"` — which
    /// Swift spells `\"` and the loaded table hands back as `"`. They were this
    /// check's first four accusations, and all four were wrong.
    private func decodingEscapes(_ source: String) -> String {
        decodingUnicodeEscapes(source).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private func decodingUnicodeEscapes(_ source: String) -> String {
        var out = ""
        var rest = Substring(source)
        while let start = rest.range(of: "\\u{") {
            out += rest[rest.startIndex..<start.lowerBound]
            guard let close = rest.range(of: "}", range: start.upperBound..<rest.endIndex),
                  let scalar = UInt32(rest[start.upperBound..<close.lowerBound], radix: 16),
                  let character = Unicode.Scalar(scalar)
            else {
                out += rest[start.lowerBound..<start.upperBound]
                rest = rest[start.upperBound...]
                continue
            }
            out.append(Character(character))
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    func testNoTranslationIsKeptForAKeyNothingAsksFor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")

        var swift = ""
        var scanned = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            scanned += 1
            swift += decodingEscapes(source) + "\n"
        }
        XCTAssertGreaterThan(scanned, 100,
                             "only \(scanned) source files were read, so a pass means nothing")

        let path = try XCTUnwrap(Localized.stringsFile(for: .en)?.path)
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertGreaterThan(english.count, 100, "en.lproj carries almost nothing")

        // An interpolated string keeps its table at the call site and never
        // reaches these files, so every key here is one somebody wrote as a
        // literal and one a literal should still be asking for.
        let orphans = english.keys.filter { !swift.contains("\"\($0)\"") }.sorted()

        XCTAssertTrue(orphans.isEmpty,
                      "\(orphans.count) key(s) carry seven translations that nothing asks "
                      + "for. Remove them from all eight files — left in place, the next "
                      + "person to write one of these words about something else inherits "
                      + "a translation of the old meaning:\n"
                      + orphans.map { "  \"\($0)\"" }.joined(separator: "\n"))
    }
}
