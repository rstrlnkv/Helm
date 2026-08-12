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
/// the plan (`v2/migration.md` § "Шаг 0") says so in as many words.
///
/// This paragraph used to end «`HelmSpace` has not landed yet; when it does,
/// this number falls a long way at once». It landed in `a49c09d` and the number
/// did not move for a day, because landing a vocabulary is not adopting one:
/// for one commit `HelmSpace` had five tests and no speakers in `Sources/`. The
/// fall is in the number below.
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
///
/// **And what it cannot see, which is not the same thing.** A number reached
/// through a name is invisible to a scan that reads call sites: a default
/// argument (`helmCard(padding: CGFloat = 14)`) and a computed constant
/// (`private static var spacing: CGFloat { 14 }`) are each one decision applied
/// at every call site, and neither is in this count. The first of those is the
/// most-drawn padding in the app and is off the ladder — recorded here so the
/// number below is not read as «twelve left», which it is not.
final class SpaceLadderRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547` at **133**; lowered to 126
    /// the same day by the Keep Awake v3 move, which took seven values off the
    /// ladder in two files, and to **12** by the tree-wide sweep the day after.
    ///
    /// **12**, measured 2026-08-12 against `main` = `83af00f`. Eight are on the
    /// menu-bar panel and its two tiles, which keep their own numbers; three are
    /// `HelmBadge`'s, where the padding is half of a capsule's silhouette rather
    /// than a gap between two things; one is `HelmPageHeader`'s 9, which is the
    /// mockup's 46 pt strip minus its 28 pt plate, halved.
    ///
    /// **Read the fall from 126 with this in hand: 40 of it is one rename.**
    /// `.padding(.horizontal, 20)` is `HelmLayout.formInset` — what a grouped
    /// `Form` insets its cards by — and a literal spelling of macOS's own number
    /// leaves this scan for the same reason `.padding()` with no argument never
    /// entered it. Nothing moved on screen at those forty sites. The rest did
    /// move, by 1 or 2 pt each, onto `HelmSpace`.
    private static let recorded = 12

    private static let ladder: Set<Double> = [0, 2, 4, 6, 8, 12, 18, 28, 40]

    /// `.padding(10)`, `.padding(.horizontal, 10)`, `spacing: 10`, and the four
    /// members of an `EdgeInsets`. One capture group each, and it is the number.
    private static let patterns = [
        #"\.padding\(\s*(-?\d+(?:\.\d+)?)\s*\)"#,
        #"\.padding\(\s*\.\w+\s*,\s*(-?\d+(?:\.\d+)?)\s*\)"#,
        #"\bspacing:\s*(-?\d+(?:\.\d+)?)"#,
        #"\b(?:top|leading|bottom|trailing):\s*(-?\d+(?:\.\d+)?)"#,
    ]

    /// The ladder said in words rather than in digits — `spacing: HelmSpace.s5`.
    ///
    /// **Counted, and this is the half adoption would otherwise have deleted.**
    /// The floor below exists so a pattern that has stopped matching cannot
    /// report zero offenders for ever; measured against literals alone that
    /// floor *falls* every time somebody does the right thing, and the first
    /// real sweep took it from 313 to 215 and failed a test about ladders. A
    /// token is a spacing decision spelled correctly, so it belongs in the
    /// denominator: with these counted the total tracks how much spacing the
    /// tree has, and adoption moves the *ratio* rather than the floor.
    ///
    /// `HelmLayout.formInset` is deliberately not here, for the reason
    /// `.padding()` with no argument is not: 20 is what a grouped `Form` insets
    /// its cards by, so it is macOS's number and not a choice made here.
    private static let tokens: [String: Double] = [
        #"\bHelmSpace\.s1\b"#: 2, #"\bHelmSpace\.s2\b"#: 4,
        #"\bHelmSpace\.s3\b"#: 6, #"\bHelmSpace\.s4\b"#: 8,
        #"\bHelmSpace\.s5\b"#: 12, #"\bHelmSpace\.s6\b"#: 18,
        #"\bHelmSpace\.s7\b"#: 28, #"\bHelmSpace\.s8\b"#: 40,
    ]

    private func hits() throws -> [UISources.Hit] {
        try UISources.hits(matching: Self.patterns, in: UISources.files())
    }

    /// Every spacing decision in the UI layer: the numbers and the words.
    private func everySpacing() throws -> [UISources.Hit] {
        try hits() + UISources.sites(matching: Self.tokens, in: UISources.files())
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
        let all = try everySpacing()
        // 315 the day this was written and 313 the day of the sweep, of which
        // 98 became tokens; the floor is set below that rather than at it, so
        // adding a stack does not fail a test about ladders.
        XCTAssertGreaterThan(all.count, 250, "the space patterns matched \(all.count) values")
        let off = UISources.offLadder(all, ladder: Self.ladder)
        XCTAssertLessThan(off.count, all.count / 2,
                          "more than half of all spacing is off the ladder — "
                          + "either the ladder is wrong or the scan is")
    }

    /// And the ladder has speakers, which for one commit it did not.
    ///
    /// `HelmSpace` landed in `a49c09d` with five tests around it and **zero**
    /// call sites in `Sources/` — a vocabulary nobody spoke, which no ratchet
    /// then measured could tell apart from a vocabulary that was working. The
    /// floor above would have been satisfied by literals alone.
    func testTheLadderIsSpokenAndNotOnlyDeclared() throws {
        let spoken = try UISources.sites(matching: Self.tokens, in: UISources.files())
        XCTAssertGreaterThan(spoken.count, 40,
                             "`HelmSpace` is named at \(spoken.count) sites in the UI layer")
        XCTAssertGreaterThan(Set(spoken.map(\.file)).count, 10,
                             "the ladder is spoken in \(Set(spoken.map(\.file)).count) files — "
                             + "a vocabulary one file uses is that file's private number")
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
        let hits = try UISources.hits(matching: Self.patterns, in: sample)
        XCTAssertEqual(hits.count, 3, "the three shapes are spacing:, .padding(n) and .padding(edge, n)")
        XCTAssertEqual(UISources.offLadder(hits, ladder: Self.ladder).count, 3,
                       "15 is on no step of the ladder and must be reported by all three")
    }

    /// And it does *not* object to a value on the ladder, or the count above is
    /// a count of every spacing in the tree.
    func testTheRuleLetsALadderValuePass() throws {
        let hits = try UISources.hits(matching: Self.patterns,
                                      in: #"HStack(spacing: 8) { }.padding(12)"#)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(UISources.offLadder(hits, ladder: Self.ladder), [])
    }

}
