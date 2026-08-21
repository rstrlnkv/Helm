import XCTest
import HelmTestSupport
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

    /// **Every source file with its comments blanked and its literals kept, and
    /// both tests below read this and nothing else.**
    ///
    /// Neither half of that reading is optional, and neither is the sharing.
    ///
    /// **This sentence was here before the sharing was.** It was an instance
    /// method with no memo, and XCTest builds an instance per test case — so
    /// «both tests read this» described one walk and one parse of `Sources/`
    /// each, and the class cost 14.9 s of a suite whose other hundred-odd
    /// classes are milliseconds. A promise written in prose with no test under
    /// it reads as a fact, which is exactly how it survived: the reading is
    /// `SwiftSource.uncommented(under:)` now, cached once a process, and
    /// `TheTreeIsReadOnceAProcessTests` is the test this paragraph owed.
    ///
    /// *Raw* — which is what both scans did until 2026-08-21 — a key named in
    /// prose reads as asked for. This repository writes backticked names inside
    /// doc comments on purpose (`DocumentsNameTheTreeTests` exists to read them
    /// back), so `AppStrings.swift` really does say «Not `L("Off")`», and that
    /// one sentence really did keep the key «Off» alive by explaining why
    /// nothing uses it. Measured over the whole tree the day this changed, the
    /// two readings differed by **0 keys and 0 literals** — this is the hole
    /// closed before something fell in it.
    ///
    /// `SwiftSource.code` is the opposite mistake and the one that looks right:
    /// it blanks the insides of literals too, so every `L("Off")` becomes
    /// `L("")` and all 1055 keys orphan at once.
    ///
    /// **And the two scans must read the same text or they can contradict each
    /// other.** They point opposite ways at the same line: on a raw reading a
    /// commented-out `L("Old name")` is a literal the tables are *required* to
    /// carry, while on a stripped reading it is a key nothing asks for and the
    /// tables are required *not* to carry it. Split the reading between them and
    /// there is a line of source that no state of the eight files can satisfy.
    ///
    /// Escapes are decoded **after** this, never before: `\"` is what ends a
    /// literal, so a decoded source parses to a different place.
    private func uncommentedSources() throws -> [SwiftSource.Read] {
        try SwiftSource.uncommented(under: "Sources")
    }

    /// **A fast yes, and never a fast no.**
    ///
    /// The scan below asks `swift.contains("\"\(key)\"")` of a thousand keys
    /// against 1.84 million characters, and that — not the walk, not the parse
    /// — is what this class costs: measured 2026-08-21, read and parse
    /// `Sources/` 0.883 s, decode and join 0.089 s, load the table 0.006 s,
    /// **and the thousand searches 23.114 s**.
    ///
    /// So the searches get an index, and it is one-way on purpose. Every run of
    /// text between two *consecutive* quote characters is a key the source
    /// demonstrably asks for: if `source[i]` and `source[j]` are quotes with
    /// nothing quoted in between, then `source[i...j]` **is** `"key"`, so a hit
    /// here is a hit there and no orphan can hide behind it. A miss is not an
    /// answer at all — the caller still runs the original `contains`, which
    /// stays the authority. That asymmetry is the whole design: the index can
    /// only ever save work, never decide anything.
    ///
    /// The obvious version of this — split on `"` and keep the odd pieces —
    /// was tried and is wrong, by 160 keys of 1059. `decodingEscapes` turns
    /// `\"` into `"` before this ever runs, so the quotes do not alternate and
    /// a parity walk loses its place at the first escaped one. Consecutive
    /// pairs, overlapping, is the reading that survives it: `"a"b"` really does
    /// contain both `"a"` and `"b"`.
    static func runsBetweenConsecutiveQuotes(of source: String) -> Set<String> {
        var out: Set<String> = []
        var run = ""
        var open = false
        for character in source {
            guard character != "\"" else {
                if open { out.insert(run) }
                run = ""
                open = true
                continue
            }
            if open { run.append(character) }
        }
        return out
    }

    /// The property the fallback rests on, on input the tree does not contain:
    /// **whatever this index says is there, is there.**
    ///
    /// Not «the index agrees with `contains`» — it does not, and must not be
    /// asked to. It is allowed to miss. It is not allowed to invent, and an
    /// invention is what would turn a live key into a silent pass.
    /// The tail is the point of the fixture. `decodingEscapes` has already
    /// turned every `\"` into `"` by the time the scan runs, so the quote count
    /// of the joined source is arbitrary and a walk that assumes it alternates
    /// finishes one quote out of step — claiming the text after the last
    /// unmatched quote is a key. Here that is `neverClosed`, which nothing in
    /// the source asks for.
    func testTheIndexNeverClaimsAKeyTheSourceDoesNotAskFor() {
        let source = #"let a = "one"; let b = "two"say "three" and "sp ace" then ""x "neverClosed"#
        let runs = Self.runsBetweenConsecutiveQuotes(of: source)

        XCTAssertFalse(runs.isEmpty, "the index found nothing, so the check below is vacuous")
        for run in runs {
            XCTAssertTrue(source.contains("\"\(run)\""),
                          "the index claims «\(run)» is asked for and the source does not "
                          + "say so — a live key could pass as an orphan-free one")
        }
        // And the readings a parity walk gets wrong, which is why this is not
        // one: `"two"say "three"` has a run between the closing quote of one
        // literal and the opening quote of the next.
        XCTAssertTrue(runs.contains("one"))
        XCTAssertTrue(runs.contains("three"), "an overlapping pair was missed")
        XCTAssertTrue(runs.contains("sp ace"))
        XCTAssertTrue(runs.contains(""), "two adjacent quotes are an empty run")
    }

    /// And the direction that matters for the saving rather than for the
    /// safety: a key the source really does ask for is found by the index, so
    /// the slow path is reached only by the keys about to be reported.
    func testTheIndexFindsWhatIsThereSoTheSlowPathIsForOrphansOnly() {
        let source = #"L("Off") and L("Very small")"#
        let runs = Self.runsBetweenConsecutiveQuotes(of: source)
        XCTAssertTrue(runs.contains("Off"))
        XCTAssertTrue(runs.contains("Very small"))
        XCTAssertFalse(runs.contains("Medium"))
    }

    func testNoTranslationIsKeptForAKeyNothingAsksFor() throws {
        let sources = try uncommentedSources()
        let swift = sources.map { decodingEscapes($0.text) }.joined(separator: "\n")
        XCTAssertGreaterThan(sources.count, 100,
                             "only \(sources.count) source files were read, so a pass "
                             + "means nothing")

        let path = try XCTUnwrap(Localized.stringsFile(for: .en)?.path)
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertGreaterThan(english.count, 100, "en.lproj carries almost nothing")

        // An interpolated string keeps its table at the call site and never
        // reaches these files, so every key here is one somebody wrote as a
        // literal and one a literal should still be asking for.
        //
        // The index answers «yes» or «ask properly», never «no», so the
        // predicate is still `swift.contains("\"key\"")` and the only keys that
        // pay for it are the ones about to be reported.
        let asked = Self.runsBetweenConsecutiveQuotes(of: swift)
        let orphans = english.keys
            .filter { !asked.contains($0) && !swift.contains("\"\($0)\"") }
            .sorted()

        XCTAssertTrue(orphans.isEmpty,
                      "\(orphans.count) key(s) carry seven translations that nothing asks "
                      + "for. Remove them from all eight files — left in place, the next "
                      + "person to write one of these words about something else inherits "
                      + "a translation of the old meaning:\n"
                      + orphans.map { "  \"\($0)\"" }.joined(separator: "\n"))
    }

    /// And the direction neither this file nor `StringsCoverageTests` covered:
    /// an `L("…")` written in the source with no entry in any table.
    ///
    /// `StringsCoverageTests` compares the eight files **against each other**,
    /// so a key that reached none of them passes there; `L()` falls back to its
    /// own key, so it looks perfect in English and ships English to the other
    /// seven. Found the way these things are always found — five changelog
    /// strings were added, the whole suite stayed green, and the only reason
    /// they were translated at all is that somebody went looking.
    ///
    /// **On the same reading as the scan above, for the reason
    /// `uncommentedSources()` gives**: an `L("…")` inside a comment is prose
    /// about the app, not a call the app makes, and demanding a key for it puts
    /// the two scans in a state neither the source nor the tables can leave.
    func testEveryLiteralInTheSourceHasAKeyInTheTables() throws {
        // `L("…")` on one line, which is how every literal in this codebase is
        // written — a key split across lines by string concatenation is not a
        // key any table could carry either.
        let call = try NSRegularExpression(pattern: #"\bL\(\s*"((?:[^"\\]|\\.)*)"#)
        var used = Set<String>()
        let sources = try uncommentedSources()
        for source in sources.map(\.text) {
            let range = NSRange(source.startIndex..., in: source)
            for match in call.matches(in: source, range: range) {
                guard let r = Range(match.range(at: 1), in: source) else { continue }
                let literal = String(source[r])
                // An interpolated string is not a key and never could be: the
                // interpolation runs before the lookup, so `L("\(n) files")`
                // asks the table for "3 files". CLAUDE.md's rule is that those
                // keep an inline table at the call site, and thirty-seven of
                // the thirty-eight this check first accused were exactly that.
                // The thirty-eighth was real.
                guard !literal.contains("\\(") else { continue }
                used.insert(decodingEscapes(literal))
            }
        }
        XCTAssertGreaterThan(sources.count, 100,
                             "only \(sources.count) source files were read, so a pass "
                             + "means nothing")
        XCTAssertGreaterThan(used.count, 100,
                             "the pattern matched \(used.count) literals, which is not this "
                             + "app — the regex has stopped finding L() calls")

        let path = try XCTUnwrap(Localized.stringsFile(for: .en)?.path)
        let english = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        let missing = used.subtracting(english.keys).sorted()

        XCTAssertTrue(missing.isEmpty,
                      "\(missing.count) literal(s) are asked for by name and are in no table. "
                      + "They read correctly in English and in English only, in all seven "
                      + "other languages, with nothing failing:\n"
                      + missing.map { "  \"\($0.prefix(70))\"" }.joined(separator: "\n"))
    }
}
