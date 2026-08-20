import XCTest
import HelmTestSupport
@testable import HelmUI

/// Five places in this app draw one glyph or another and, until the token
/// existed, changed between them with nothing on the wire: `pencil` →
/// `checkmark`, `plus.circle` → `checkmark.circle.fill`, `circle` →
/// `circle.fill`, and the two permission marks. A symbol that swaps without a
/// transition is not a still image — it is a cut, and a cut on a 14 pt glyph
/// in the corner of a card is a change most people never see happen.
///
/// `helmSymbolSwap` is the one way it is done now, and it carries two things a
/// call site kept getting wrong on its own:
///
/// 1. **The transaction.** `.contentTransition` without an animation beside it
///    is a decoration that cannot fire — measured on a rolling digit in
///    `RuleEditor.swift`, the bare modifier drew one value where the same view
///    with the animation drew twelve. Two of the five sites change state from a
///    hover or an async model update, neither of which is inside a
///    `withAnimation`, so a hand-written `.contentTransition` at those two would
///    have been exactly that decoration.
/// 2. **Reduce Motion.** SwiftUI does not honour it for symbol effects; this is
///    the same finding `SteadySpinTests` pins for the spinning glyphs.
final class AGlyphBecomesAnotherGlyphTests: XCTestCase {

    // MARK: - The decision

    func testAGlyphMorphsIntoTheNextOne() {
        XCTAssertTrue(HelmMotion.swaps(reduceMotion: false))
    }

    /// The whole point of the predicate being a predicate.
    func testReduceMotionCutsInsteadOfMorphing() {
        XCTAssertFalse(HelmMotion.swaps(reduceMotion: true))
    }

    // MARK: - The one way

    /// Assert the subject exists before asserting anything is absent from it.
    ///
    /// A scan for "nobody writes this by hand" passes cleanly in a tree where
    /// nobody writes it at all — including a tree where the modifier was
    /// deleted and every swap went back to being a cut. So count the call
    /// sites first: five is what landed, and a number below that is the check
    /// reporting that it has nothing left to guard.
    func testTheSwapIsActuallyUsed() throws {
        var sites: [String] = []
        for file in try RepoSource.swiftFiles(under: "Sources") {
            for (index, line) in try RepoSource.lines(of: file).enumerated()
            where RepoSource.code(line).contains(".helmSymbolSwap(") {
                sites.append("\(file):\(index + 1)")
            }
        }
        XCTAssertGreaterThanOrEqual(sites.count, 5,
                                    "only \(sites.count) glyph swaps left: \(sites)")
    }

    /// And no site spells the effect itself.
    ///
    /// The failure this catches reads perfectly in a diff:
    /// `.contentTransition(.symbolEffect(.replace))` is a correct line of
    /// SwiftUI and it is what everybody's fingers type. What it is missing is
    /// invisible — the animation that lets it fire, and the flag that stops it
    /// for somebody who asked for stillness.
    func testNoSiteWritesTheSymbolTransitionByHand() throws {
        var offenders: [String] = []
        var scanned = 0
        for file in try RepoSource.swiftFiles(under: "Sources") {
            guard !file.hasSuffix("HelmMotion.swift") else { continue }
            scanned += 1
            for (index, line) in try RepoSource.lines(of: file).enumerated() {
                let text = RepoSource.code(line)
                guard text.contains("symbolEffect(.replace") else { continue }
                offenders.append("\(file):\(index + 1) — "
                                 + text.trimmingCharacters(in: .whitespaces))
            }
        }
        XCTAssertGreaterThan(scanned, 100,
                             "the scan found \(scanned) files, so a pass means nothing")
        XCTAssertTrue(offenders.isEmpty,
                      "a symbol replacement was written by hand. Without a transaction "
                      + "beside it, it never plays; without the flag, it plays for "
                      + "somebody who asked for no motion. Use helmSymbolSwap:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The fallback is not a nicety.
    ///
    /// `magic(fallback:)` takes it in the signature because two symbols may
    /// share no layers at all — `pencil` and `checkmark` share none — and Magic
    /// Replace has nothing to morph. One of the five sites is that pair, so the
    /// fallback is on the screen, not in theory.
    func testTheMorphNamesAFallback() throws {
        let source = try RepoSource.text(of: "Sources/HelmUI/DesignSystem/HelmMotion.swift")
        XCTAssertTrue(source.contains(".replace.magic(fallback:"),
                      "the swap is a plain replacement now — the symbols that share "
                      + "a shape will cut instead of morphing")
    }
}
