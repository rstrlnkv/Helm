import HelmTestSupport
import XCTest

/// **Type has one scale: 10 · 11 · 13 · 16 · 22 · 40 pt.**
///
/// The mockups carried seventeen sizes before this scale was chosen, and the
/// finding recorded in `v3/audit.js` is the one that generalises: *there were
/// more differences than were visible*. A 15 pt heading beside a 16 pt heading
/// is not a decision anybody took; it is two people, or one person twice.
///
/// A ratchet like the space ladder beside it: the number is what the tree
/// measured on the day it landed, and only the commit that lowers it lowers it.
///
/// **Explicit sizes only, and that is a decision.** `.font(.callout)` resolves
/// to 12 pt on macOS and is off this scale — as are `.title2` at 17 and
/// `.title3` at 15 — but a semantic style is a name for a *role*, and it is the
/// vocabulary v3 replaces rather than a number somebody picked. Counting the 29
/// of them here would put a number in this test that nothing can lower until
/// the tokens land, and would tie the count to what macOS resolves a style to,
/// which is a fact about the OS and not about this tree. What is counted is a
/// number typed by hand: `.system(size: 15)` and the `NSFont` builders.
final class TypeScaleRatchetTests: XCTestCase {

    /// Measured 2026-08-11 against `main` = `8b8c547`. No single value
    /// dominates — 9, 12, 15, 17, 19, 34 and 44, one or two each, which is what
    /// «more differences than are visible» looks like when it is written down.
    private static let recorded = 11

    private static let ladder: Set<Double> = [10, 11, 13, 16, 22, 40]

    private static let patterns = [
        #"\.system\(\s*size:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bsystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bmonospacedSystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
        #"\bmonospacedDigitSystemFont\(ofSize:\s*(-?\d+(?:\.\d+)?)"#,
    ]

    private func hits() throws -> [UISources.Hit] {
        try UISources.hits(matching: Self.patterns, in: UISources.files())
    }

    func testTypeOffTheScaleDoesNotGrow() throws {
        let off = UISources.offLadder(try hits(), ladder: Self.ladder)
        XCTAssertLessThanOrEqual(off.count, Self.recorded, """
            \(off.count) hand-typed font sizes are off the scale \
            \(Self.ladder.sorted().map { String(Int($0)) }.joined(separator: "·")); \
            the recorded number is \(Self.recorded).
            This number is only ever lowered, by the commit that lowers it.
            \(UISources.summary(off))
            """)
    }

    // MARK: - The scan itself

    /// The same floor the space ladder asserts, for the same reason: a pattern
    /// that has stopped matching reports no offenders and passes for ever.
    /// Most hand-typed sizes are already on the scale, and that is what makes
    /// the small number above readable as a small number.
    func testTheScanStillFindsFontSizesAtAll() throws {
        let all = try hits()
        XCTAssertGreaterThan(all.count, 30, "the type patterns matched \(all.count) sizes")
        XCTAssertLessThan(UISources.offLadder(all, ladder: Self.ladder).count, all.count / 2,
                          "more than half of every hand-typed size is off the scale — "
                          + "either the scale is wrong or the scan is")
    }

    /// The rule objects to the shape it was written for, and lets the scale
    /// through. Against a fixture, so it goes on saying this after the tree is
    /// fixed.
    func testTheRuleRecognisesASizeOffTheScale() throws {
        let off = try Self.matches(in: #"Text("x").font(.system(size: 15, weight: .semibold))"#)
        XCTAssertEqual(off.map(\.value), [15])
        XCTAssertEqual(UISources.offLadder(off, ladder: Self.ladder).count, 1)

        let on = try Self.matches(in: #"Text("x").font(.system(size: 13))"#)
        XCTAssertEqual(on.map(\.value), [13])
        XCTAssertEqual(UISources.offLadder(on, ladder: Self.ladder), [])
    }

    /// `NSFont` is the other half. `MenuBarLook` and the icon drawing reach for
    /// it directly, and a size typed there is as much a size as one typed in
    /// SwiftUI.
    func testTheRuleReadsTheAppKitBuildersToo() throws {
        let hits = try Self.matches(in: "NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)")
        XCTAssertEqual(hits.map(\.value), [9])
    }

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
