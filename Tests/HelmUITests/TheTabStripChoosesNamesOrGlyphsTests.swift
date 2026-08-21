import HelmUI
import XCTest

/// **The strip draws what it was asked for, except where what it was asked for
/// draws nothing.**
///
/// «Tab labels» is a setting again, with a fourth answer the three did not have:
/// `automatic` hands the question to the measurement — the panel is 320 pt and
/// has been since it shipped, so «do the names fit» has an answer rather than a
/// taste — while the other three are kept whatever the arithmetic would say.
///
/// **Glyphs only when every tab has one, however the answer arrived.** The
/// setting can be put on `.glyph` with a tab carrying no glyph, and that tab
/// drew an empty padded button: a control with nothing in it and nothing to
/// read. `TabStripFit` is the only place a face is decided, so the fallback is
/// in front of the chosen answer as well as the measured one.
final class TheTabStripChoosesNamesOrGlyphsTests: XCTestCase {

    /// A fixed width per character, so the assertions are about the arithmetic
    /// rather than about this Mac's font.
    private let tenPointsAGlyph: (String) -> CGFloat = { CGFloat($0.count) * 10 }

    private func face(_ titles: [String], glyphs: [String?],
                      choice: TabLabelStyle = .automatic, editing: Bool = false,
                      available: CGFloat = 288) -> TabLabelFace {
        TabStripFit.face(for: choice, tabs: Array(zip(titles, glyphs)), editing: editing,
                         available: available, widthOfName: tenPointsAGlyph)
    }

    // MARK: - Automatic, which is the measurement

    func testNamesThatFitAreDrawn() {
        XCTAssertEqual(face(["Main", "Disk"], glyphs: ["star", "internaldrive"]), .text)
    }

    func testNamesThatDoNotFitBecomeGlyphs() {
        XCTAssertEqual(face(["Everything I keep an eye on", "The other things",
                             "And a third"],
                            glyphs: ["star", "internaldrive", "gear"]), .glyph)
    }

    /// A name and a glyph travel together — `TabStripFit` takes pairs — so the
    /// only shape this can be in is «one of them has no glyph», which is exactly
    /// what a tab whose glyph was removed looks like.
    func testATabWithNoGlyphKeepsEveryName() {
        XCTAssertEqual(face(["Everything I keep an eye on", "The other things",
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
        XCTAssertEqual(face(titles, glyphs: glyphs, editing: false, available: 280), .text)
        XCTAssertEqual(face(titles, glyphs: glyphs, editing: true, available: 280), .glyph,
                       "the «+» was not counted, so the strip it is added to overflows")
    }

    /// One tab is a strip only while editing, and one name that does not fit
    /// still beats a glyph with nothing beside it — but it must not crash or
    /// answer for a strip that is not there.
    func testASingleTabAnswers() {
        XCTAssertEqual(face(["Main"], glyphs: ["star"]), .text)
    }

    func testNoTabsAnswerWithNames() {
        XCTAssertEqual(face([], glyphs: []), .text)
    }

    // MARK: - The three that are a taste

    /// Names that do not fit are still names when somebody asked for names.
    /// This is the difference between the setting and the measurement, and it
    /// is the whole reason the setting is back.
    func testChosenNamesAreKeptEvenWhereTheyDoNotFit() {
        let titles = ["Everything I keep an eye on", "The other things", "And a third"]
        let glyphs: [String?] = ["star", "internaldrive", "gear"]
        XCTAssertEqual(face(titles, glyphs: glyphs), .glyph,
                       "the same strip left to itself gives its names up, so this is a "
                       + "test of the choice rather than of a strip that fits anyway")
        XCTAssertEqual(face(titles, glyphs: glyphs, choice: .text), .text)
    }

    /// And glyphs are glyphs on a strip with room to spare.
    func testChosenGlyphsAreKeptOnAStripThatWouldHaveFitted() {
        XCTAssertEqual(face(["Main", "Disk"], glyphs: ["star", "gear"], choice: .glyph), .glyph)
    }

    func testGlyphAndTextIsKept() {
        XCTAssertEqual(face(["Main", "Disk"], glyphs: ["star", "gear"], choice: .glyphAndText),
                       .glyphAndText)
    }

    /// The hole the pop-up used to open, closed in front of the pop-up rather
    /// than behind it: chosen or measured, one tab without a glyph is a strip
    /// of names.
    func testChosenGlyphsFallBackToNamesWhenATabHasNone() {
        XCTAssertEqual(face(["Main", "Disk"], glyphs: ["star", nil], choice: .glyph), .text,
                       "the tab with no glyph drew an empty padded button")
    }

    /// A tab with no glyph under «glyph and text» has its name, so there is
    /// nothing to fall back from.
    func testGlyphAndTextSurvivesAMissingGlyph() {
        XCTAssertEqual(face(["Main", "Disk"], glyphs: ["star", nil], choice: .glyphAndText),
                       .glyphAndText)
    }

    // MARK: - What a stored answer reads as

    /// The default the setting shipped with, and the one a value written by a
    /// build with a case this one lacks comes back as.
    func testAnUnknownStoredAnswerIsNames() {
        XCTAssertEqual(TabLabelStyle(stored: ""), .text)
        XCTAssertEqual(TabLabelStyle(stored: "semaphore"), .text)
    }

    /// Every answer the pop-up offers survives being stored and read back —
    /// including `automatic`, which is the one this build added.
    func testEveryChoiceSurvivesTheStore() {
        for choice in TabLabelStyle.allCases {
            XCTAssertEqual(TabLabelStyle(stored: choice.rawValue), choice)
        }
    }
}
