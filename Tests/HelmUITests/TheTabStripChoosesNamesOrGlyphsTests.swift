import HelmUI
import XCTest

/// **The strip answers the question the setting used to ask.**
///
/// «Tab labels» was a pop-up of three, and `TabLabelStyle`'s own documentation
/// argued against it: the right answer «depends on things the app cannot see:
/// how many tabs there are, how long their names came out, and whether the
/// person named them at all» — and all three are in `PanelLayout`. The panel is
/// 320 pt wide and has been since it shipped, so «does it fit» is a question
/// with an answer rather than a taste.
///
/// **Glyphs only when every tab has one.** The setting could be put on `.glyph`
/// with a tab carrying no glyph, and that tab drew an empty padded button — a
/// control with nothing in it and nothing to read. Chosen rather than set, that
/// state cannot be reached: a strip falls back to names whenever one tab has no
/// glyph to stand in for its name.
final class TheTabStripChoosesNamesOrGlyphsTests: XCTestCase {

    /// A fixed width per character, so the assertions are about the arithmetic
    /// rather than about this Mac's font.
    private let tenPointsAGlyph: (String) -> CGFloat = { CGFloat($0.count) * 10 }

    private func style(_ titles: [String], glyphs: [String?],
                       editing: Bool = false, available: CGFloat = 288) -> TabLabelStyle {
        TabStripFit.style(tabs: Array(zip(titles, glyphs)), editing: editing,
                          available: available, widthOfName: tenPointsAGlyph)
    }

    func testNamesThatFitAreDrawn() {
        XCTAssertEqual(style(["Main", "Disk"], glyphs: ["star", "internaldrive"]), .text)
    }

    func testNamesThatDoNotFitBecomeGlyphs() {
        XCTAssertEqual(style(["Everything I keep an eye on", "The other things",
                              "And a third"],
                             glyphs: ["star", "internaldrive", "gear"]), .glyph)
    }

    /// The state the deleted pop-up could reach and this cannot.
    ///
    /// A name and a glyph travel together — `TabStripFit` takes pairs — so the
    /// only shape this can be in is «one of them has no glyph», which is exactly
    /// what a tab whose glyph was removed looks like.
    func testATabWithNoGlyphKeepsEveryName() {
        XCTAssertEqual(style(["Everything I keep an eye on", "The other things",
                              "And a third"],
                             glyphs: ["star", nil, "gear"]), .text,
                       "a strip with one glyph missing drew that tab as an empty button")
    }

    /// The «+» is a tab's worth of strip, and it is only there in edit mode —
    /// so a strip that fits while reading can stop fitting while editing.
    func testTheAddButtonIsPartOfTheWidth() {
        // 266 pt of tabs while reading — two tabs of 13 and 10 characters, 16 pt
        // of padding each and one 4 pt gap — and 298 with the «+» and the second
        // gap it brings. 280 is between them, which is what makes this about the
        // button rather than about the names.
        let titles = ["Main tab here", "Second tab"]
        let glyphs: [String?] = ["star", "gear"]
        XCTAssertEqual(style(titles, glyphs: glyphs, editing: false, available: 280), .text)
        XCTAssertEqual(style(titles, glyphs: glyphs, editing: true, available: 280), .glyph,
                       "the «+» was not counted, so the strip it is added to overflows")
    }

    /// One tab is a strip only while editing, and one name that does not fit
    /// still beats a glyph with nothing beside it — but it must not crash or
    /// answer for a strip that is not there.
    func testASingleTabAnswers() {
        XCTAssertEqual(style(["Main"], glyphs: ["star"]), .text)
    }

    func testNoTabsAnswerWithNames() {
        XCTAssertEqual(style([], glyphs: []), .text)
    }
}
