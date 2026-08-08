import XCTest
import HelmTestSupport

/// The card's own edges are `PanelGrid`'s constants, never numbers typed again.
///
/// `PanelGrid.roomForGrid` subtracts `padding * 2` and a count of `gap` from the
/// strip, and every one of those terms is a claim about a line in
/// `HelmPanel.card` — which wrote `spacing: 8` and `.padding(12)` as literals.
/// One declaration split across a target boundary with no compiler between the
/// halves: move the card to `.padding(14)` and nothing is an error, nothing
/// fails, and the grid is silently handed 4 pt it does not have.
///
/// It also made a test in `PanelGridTests` unfalsifiable —
/// `testTheCardsOwnEdgesComeOffToo` asserts `roomForGrid` against
/// `PanelGrid.padding` and `PanelGrid.gap`, so both sides moved together and
/// the card was free to disagree with both. That test is meaningful again
/// because of this one: the constants are now the only place either number is
/// written, so agreeing with them is agreeing with the card.
///
/// Source, not pixels, and that is the honest scope. The card is a menu-bar
/// panel over Liquid Glass, which does not composite offscreen; what a probe can
/// measure is the shape (`PanelCardGapsProbe` does, and pins the gap *count*).
/// What is left is that the shape is spelled from the same declaration as the
/// arithmetic, which is a question about the text.
final class CardEdgesAreTheGridsConstantsTests: XCTestCase {

    /// `card`'s body, by brace count over comment-stripped lines — the card's
    /// own comments quote the spellings this forbids.
    ///
    /// **A card it cannot find is an empty slice, never a skip.** The control
    /// below is what notices, and it has to notice by *failing*: a skip is
    /// green in a failures-only summary, which is how `DocumentsNameTheTreeTests`
    /// once checked nothing in a fresh worktree for weeks.
    private func cardBody() throws -> [(line: Int, text: String)] {
        let lines = try RepoSource.lines(of: "Sources/HelmApp/HelmPanel.swift")
            .map(RepoSource.code)
        guard let start = lines.firstIndex(where: { $0.contains("private func card(") })
        else { return [] }

        var depth = 0
        var body: [(Int, String)] = []
        for index in start..<lines.count {
            let text = lines[index]
            depth += text.filter { $0 == "{" }.count - text.filter { $0 == "}" }.count
            body.append((index + 1, text))
            if depth == 0 && index > start { break }
        }
        return body
    }

    /// The control. Every assertion below passes on an empty slice, and a
    /// renamed function or a brace inside a string would give one.
    func testTheSliceIsActuallyTheCard() throws {
        let body = try cardBody()
        XCTAssertGreaterThan(body.count, 80, "only \(body.count) lines were read as the card")
        XCTAssertTrue(body.contains { $0.text.contains("ScrollView") },
                      "the slice holds no scroll view, so it is not the card")
        XCTAssertTrue(body.contains { $0.text.contains("PanelFooter") },
                      "the slice stops before the footer block")
    }

    func testTheCardsGapsAndPaddingAreTheGridsOwn() throws {
        let offenders = try cardBody().filter { line in
            line.text.range(of: #"spacing: [0-9]"#, options: .regularExpression) != nil
                || line.text.range(of: #"\.padding\([0-9]"#, options: .regularExpression) != nil
        }
        XCTAssertTrue(offenders.isEmpty,
                      "the card spells a number `PanelGrid` already declares. "
                      + "`roomForGrid` subtracts these, and neither half of a "
                      + "declaration split this way can be changed safely:\n"
                      + offenders.map { "HelmPanel.swift:\($0.line) —\($0.text)" }
                          .joined(separator: "\n"))
    }

    /// And it does read them, so a card that lost its spacing altogether does
    /// not pass the test above by having nothing to find.
    func testTheCardNamesTheConstantsItIsMeasuredBy() throws {
        let body = try cardBody().map(\.text).joined(separator: "\n")
        XCTAssertTrue(body.contains("spacing: PanelGrid.gap"),
                      "the card's blocks are spaced by something other than the grid's gap")
        XCTAssertTrue(body.contains(".padding(PanelGrid.padding)"),
                      "the card's own inset is something other than the grid's padding")
    }
}
