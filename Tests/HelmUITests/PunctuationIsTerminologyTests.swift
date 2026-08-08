import XCTest
@testable import HelmUI

/// Punctuation is terminology: which marks a language quotes with, and which
/// space it puts beside a mark, are looked up in macOS's own bundles rather
/// than remembered — the same rule the units and the pane names follow.
///
/// `Quoted` already carries that ruling for a name it wraps at runtime
/// (`L10n.swift`), and the `.lproj` files went their own way regardless: the
/// 0.8.0 entries quoted Spanish with `“…”` and the 0.9.0 entries with `«…»`,
/// which is one file disagreeing with itself about a language. Counted in
/// Finder's own `.lproj`: es 424 `“…”` against 0 `«…»`, pt-BR 419 against 0.
///
/// **Japanese is deliberately not here.** Helm is 118/118 consistent on 「…」
/// where macOS's interface uses “…” 551 times and 「…」 not at all — a real
/// inconsistency, but a wholesale one, and its own decision to take rather
/// than a stray to sweep up with these.
final class PunctuationIsTerminologyTests: XCTestCase {

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path,
                                 "no Localizable.strings for \(language.rawValue)")
        let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String],
                                 "\(language.rawValue).lproj did not parse")
        XCTAssertGreaterThan(dict.count, 100, "\(language.rawValue).lproj carries almost nothing")
        return dict
    }

    /// The marks a language never writes, so a value carrying one is a mark
    /// somebody translated instead of looking up.
    private static let foreignMarks: [AppLanguage: [Character]] = [
        .es: ["«", "»"],
        .pt: ["«", "»"],
        .de: ["«", "»"],   // „…“, and the guillemets were strays
        .zh: ["「", "」"],  // “…”, and the corner brackets were strays
        .fr: ["“", "”"],   // «…», the one language that keeps them
    ]

    func testNoLanguageQuotesWithAnotherLanguagesMarks() throws {
        var offenders: [(AppLanguage, Character, String)] = []
        for (language, marks) in Self.foreignMarks {
            for (key, value) in try table(for: language) {
                for mark in marks where value.contains(mark) {
                    offenders.append((language, mark, key))
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) value(s) quote with a mark their language does not use:\n"
                      + offenders
                        .map { "  \($0.0.rawValue) \($0.1) in \"\($0.2.prefix(60))…\"" }
                        .sorted()
                        .joined(separator: "\n"))
    }

    /// French's space is a character, and the wrong one breaks the line.
    ///
    /// macOS French is 413 for 413 on the unbreakable space inside guillemets
    /// and writes 129 before a colon and 121 before a question mark with never
    /// an ordinary one. An ordinary space there is not merely the wrong
    /// character: it is a *breaking* one, so the name can end up on the line
    /// below the mark that opened it, and the colon can start a line by itself.
    ///
    /// Cleanly expressible because French is the only language of the eight
    /// that spaces its punctuation at all, and because nothing in the file
    /// quotes an untranslated English label — the one value that names a macOS
    /// setting writes it in French inside French marks. Neither pattern has a
    /// legitimate occurrence to excuse.
    func testFrenchSpacesItsPunctuationTheWayMacOSDoes() throws {
        let breaking: Character = " "        // U+0020
        let unbreakable: Character = "\u{00A0}"
        var offenders: [String] = []
        for (key, value) in try table(for: .fr) {
            let characters = Array(value)
            for (index, character) in characters.enumerated() {
                let before = index > 0 ? characters[index - 1] : nil
                let after = index + 1 < characters.count ? characters[index + 1] : nil
                if character == "«", after != unbreakable {
                    offenders.append("« not followed by U+00A0 in \"\(key.prefix(50))…\"")
                }
                if character == "»", before != unbreakable {
                    offenders.append("» not preceded by U+00A0 in \"\(key.prefix(50))…\"")
                }
                if ":;?!".contains(character), before == breaking {
                    offenders.append("U+0020 before \(character) in \"\(key.prefix(50))…\"")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) French value(s) use an ordinary space where macOS "
                      + "uses an unbreakable one:\n"
                      + offenders.sorted().joined(separator: "\n").prefix(4000))
    }
}
