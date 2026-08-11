import HelmTestSupport
import XCTest

/// **Space has one ladder: 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40.**
///
/// A value off it was chosen by eye. The mockup audit measured twenty-four
/// distinct padding values and thirteen distinct gaps against three declared
/// tokens (`v3/audit.js`, check `space-off-the-ladder`), which is the same
/// disease the type scale had: more differences than anybody could see, and
/// none of them decided.
///
/// **A ratchet, not a gate.** The number below is what the tree measured on the
/// day this landed. It is only ever *lowered*, by the same commit that lowers
/// it — a test that fails on the day it is written is a red CI for a week, and
/// the plan (`v2/migration.md` § "Шаг 0") says so in as many words. `HelmSpace`
/// has not landed yet; when it does, this number falls a long way at once.
///
/// **What it is a count of.** Occurrences, not distinct values: a source scan
/// can name a file and a line, so the useful unit is the edit somebody has to
/// make. Where the ladder is measured off the render instead — radius, and the
/// long-string geometry — the unit is different and the test there says why.
///
/// **What it deliberately does not count.** `.padding()` with no argument, which
/// is macOS's own number and not a choice made here; `.frame(width:height:)`,
/// which is a size and not a space; and anything inside a comment, since every
/// rule in this repository is explained by quoting the thing it forbids.
final class SpaceLadderRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547`. Dominated by 10 pt (53)
    /// and 20 pt (37) — the two values `HelmSpace.s?` will absorb — with
    /// `UninstallerSettingsPage` the worst single file at 21.
    private static let recorded = 133

    private static let ladder: Set<Double> = [0, 2, 4, 6, 8, 12, 18, 28, 40]

    /// `.padding(10)`, `.padding(.horizontal, 10)`, `spacing: 10`, and the four
    /// members of an `EdgeInsets`. One capture group each, and it is the number.
    private static let patterns = [
        #"\.padding\(\s*(-?\d+(?:\.\d+)?)\s*\)"#,
        #"\.padding\(\s*\.\w+\s*,\s*(-?\d+(?:\.\d+)?)\s*\)"#,
        #"\bspacing:\s*(-?\d+(?:\.\d+)?)"#,
        #"\b(?:top|leading|bottom|trailing):\s*(-?\d+(?:\.\d+)?)"#,
    ]

    private func hits() throws -> [UISources.Hit] {
        try UISources.hits(matching: Self.patterns, in: UISources.files())
    }

    func testSpaceOffTheLadderDoesNotGrow() throws {
        let off = UISources.offLadder(try hits(), ladder: Self.ladder)
        XCTAssertLessThanOrEqual(off.count, Self.recorded, """
            \(off.count) paddings, gaps and insets are off the space ladder \
            \(Self.ladder.sorted().map { String(Int($0)) }.joined(separator: "·")); \
            the recorded number is \(Self.recorded).
            This number is only ever lowered, by the commit that lowers it.
            \(UISources.summary(off))
            """)
    }

    // MARK: - The scan itself, which is the half that goes quiet

    /// The scan reads the whole UI layer, or the number above is a number about
    /// a subset nobody declared. Nine module UI targets and the design system.
    func testTheScanReadsEveryModuleAndTheDesignSystem() throws {
        let files = try UISources.files()
        let modules = try UISources.moduleNames()
        XCTAssertEqual(modules.count, 9, "the manifest lists \(modules): \(modules.count) modules")
        for module in modules {
            XCTAssertTrue(files.contains { $0.hasPrefix("Sources/Modules/\(module)/UI") },
                          "\(module) is in the manifest and not in the scan")
        }
        XCTAssertTrue(files.contains { $0.hasPrefix("Sources/HelmUI/DesignSystem") },
                      "the design system is not in the scan")
    }

    /// And it is still matching. A regular expression that has stopped matching
    /// anything reports zero offenders and passes for ever — the shape this
    /// suite has been caught by before. So: the patterns find plenty, and most
    /// of what they find is *on* the ladder, which is the only reading under
    /// which the off-ladder count means anything.
    func testTheScanStillFindsSpacingAtAll() throws {
        let all = try hits()
        // 315 the day this was written; the floor is set below that rather than
        // at it, so adding a stack does not fail a test about ladders.
        XCTAssertGreaterThan(all.count, 250, "the space patterns matched \(all.count) values")
        let off = UISources.offLadder(all, ladder: Self.ladder)
        XCTAssertLessThan(off.count, all.count / 2,
                          "more than half of all spacing is off the ladder — "
                          + "either the ladder is wrong or the scan is")
    }

    /// The rule objects to the shape it was written for — the Swift twin of the
    /// `probe` every check in `v3/audit.js` carries. Written against a fixture
    /// rather than the tree, so it keeps saying what it says after the tree is
    /// fixed.
    func testTheRuleRecognisesAValueChosenByEye() throws {
        let sample = """
            VStack(spacing: 15) { Text("на глаз").padding(15) }
                .padding(.horizontal, 15)
            """
        let hits = try Self.matches(in: sample)
        XCTAssertEqual(hits.count, 3, "the three shapes are spacing:, .padding(n) and .padding(edge, n)")
        XCTAssertEqual(UISources.offLadder(hits, ladder: Self.ladder).count, 3,
                       "15 is on no step of the ladder and must be reported by all three")
    }

    /// And it does *not* object to a value on the ladder, or the count above is
    /// a count of every spacing in the tree.
    func testTheRuleLetsALadderValuePass() throws {
        let hits = try Self.matches(in: #"HStack(spacing: 8) { }.padding(12)"#)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(UISources.offLadder(hits, ladder: Self.ladder), [])
    }

    /// A tiny in-memory run of the same regular expressions, so the fixtures
    /// above go through exactly what the tree goes through.
    private static func matches(in source: String) throws -> [UISources.Hit] {
        var out: [UISources.Hit] = []
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            let code = RepoSource.code(line)
            let range = NSRange(code.startIndex..., in: code)
            for pattern in patterns {
                let expression = try NSRegularExpression(pattern: pattern)
                for match in expression.matches(in: code, range: range) {
                    guard let captured = Range(match.range(at: 1), in: code),
                          let value = Double(code[captured]) else { continue }
                    out.append(UISources.Hit(file: "fixture", line: index + 1,
                                             value: value, text: code))
                }
            }
        }
        return out
    }
}
