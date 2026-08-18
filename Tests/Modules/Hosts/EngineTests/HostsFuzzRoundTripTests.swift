import XCTest
@testable import Module_Hosts_Engine

/// A search for the file the corpus did not think of.
///
/// Twenty thousand files assembled from the pieces `/etc/hosts` is made of —
/// and the pieces that break parsers: both line endings and each half of CRLF
/// on its own, tabs, runs of spaces, `#` in every position, a decomposed `é`,
/// a NUL, U+0085, an emoji, a stray `%`.
///
/// **Deterministic by construction.** The generator is a fixed-seed LCG
/// written out here rather than `SystemRandomNumberGenerator`, so a failure
/// reproduces on the next machine and in the next run: a fuzz test that finds
/// a defect once and cannot find it again is a report, not a gate.
///
/// **And the files have to be hosts files.** Written first as a plain
/// concatenation of those pieces, the generator produced an entry in 686 files
/// out of 20000 — a search that proved verbatim text is copied, which is the
/// vacuous corpus this module already found once. Lines are shaped now, and
/// each test counts what it read before it claims anything.
final class HostsFuzzRoundTripTests: XCTestCase {

    /// Knuth's constants. Anything reproducible would do; what matters is that
    /// it is not the system generator.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private static let addresses = ["127.0.0.1", "::1", "0.0.0.0", "fe80::1%lo0",
                                    "010.0.0.1", "1.1", "255.255.255.255", "not.an.address"]
    private static let names = ["localhost", "box.local", "cafe\u{301}.local", "🙂.example",
                                "a\u{85}b", "x\u{0}y", "-", "..", "a#b"]
    private static let gaps = [" ", "  ", "\t", "\t\t", "   \t"]
    private static let endings = ["\n", "\r\n", "\r", ""]
    private static let noise = ["", "#", "##", "# Host Database", "   ", "\t",
                                "127.0.0.1", "% ", "::"]

    /// One file: mostly lines shaped like entries, with comments, blanks and
    /// junk between them, and a one-in-four chance of no final line ending.
    private static func generate(with random: inout Seeded) -> String {
        var text = ""
        for _ in 0..<Int.random(in: 1...6, using: &random) {
            if Int.random(in: 0..<4, using: &random) == 0 {
                text += (noise.randomElement(using: &random) ?? "")
                    + (endings.randomElement(using: &random) ?? "\n")
                continue
            }
            if Int.random(in: 0..<3, using: &random) == 0 {
                text += "#" + (Bool.random(using: &random) ? " " : "")
            }
            text += (addresses.randomElement(using: &random) ?? "")
                + (gaps.randomElement(using: &random) ?? " ")
                + (names.randomElement(using: &random) ?? "")
            for _ in 0..<Int.random(in: 0...2, using: &random) {
                text += (gaps.randomElement(using: &random) ?? " ")
                    + (names.randomElement(using: &random) ?? "")
            }
            if Int.random(in: 0..<3, using: &random) == 0 {
                text += (gaps.randomElement(using: &random) ?? " ") + "# a note"
            }
            text += endings.randomElement(using: &random) ?? "\n"
        }
        return text
    }

    /// A file that produced no entry proves only that verbatim text is copied.
    /// The floor is a long way under what this generator measures — 16 937
    /// and 16 841 of 20 000 for the two seeds, on 2026-08-18 — and a long way
    /// over nothing, so it fails when the generator stops generating hosts
    /// files rather than when it drifts.
    private func assertThePagesWereReallyRead(_ withEntries: Int,
                                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(withEntries, 10_000,
                             "only \(withEntries) of 20000 generated files held an entry",
                             file: file, line: line)
    }

    /// Two seeds rather than one, and both assert the bytes. There was a
    /// second test here asking whether `parse` is a fixed point of its own
    /// output; it was removed because it *cannot fail on its own* — `render` is
    /// a concatenation of the pieces `parse` cut, so once the bytes come back
    /// unchanged the second reading is the first document by construction. It
    /// looked like a second property and was the same one, weakened.
    func testFortyThousandGeneratedFilesComeBackByteForByte() {
        for seed in [0x5F37_1CAF_E101, 0xD15E_A5E0_0042] as [UInt64] {
            searchForAFileThatDoesNotSurvive(from: seed)
        }
    }

    private func searchForAFileThatDoesNotSurvive(from seed: UInt64) {
        var random = Seeded(state: seed)
        var withEntries = 0
        for _ in 0..<20_000 {
            let text = Self.generate(with: &random)
            let document = HostsFile.parse(text)
            if !document.entries.isEmpty { withEntries += 1 }
            let rendered = HostsFile.render(document)
            if Array(rendered.utf8) != Array(text.utf8) {
                XCTFail("""
                    a generated file did not survive:
                      in:  \(text.debugDescription)
                      out: \(rendered.debugDescription)
                    """)
                return          // one counterexample is the finding; do not bury it
            }
        }
        assertThePagesWereReallyRead(withEntries)
    }
}
