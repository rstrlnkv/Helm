import XCTest
import HelmUI
@testable import Module_Layout_Engine
@testable import Module_Layout_UI

/// **What a reader who cannot see the tile is told.**
///
/// Four of this module's newest surfaces exposed shape without words: a chart
/// labelled with its span and no figures, a menu whose label replaced its own
/// value, a two-word row read as three unrelated stops, and a coloured dot with
/// no text at all. None of them is visible at runtime to anybody not using a
/// screen reader, which is why they are asserted here rather than noticed.
final class ThePictureSaysItsNumbersTests: XCTestCase {

    /// The fourteen bars are the tall tile's whole reason for being — «why is it
    /// that many» — and the label said «Last fourteen days» and stopped.
    func testTheSparklineNamesItsTotalAndToday() {
        for language in AppLanguage.allCases {
            let said = LyStr.fortnightSummary(total: 37, today: 4, language: language)
            XCTAssertTrue(said.contains("37"),
                          "\(language.rawValue): the fortnight is read without its total")
            XCTAssertTrue(said.contains("4"),
                          "\(language.rawValue): the fortnight is read without today's count")
            // The number is grouped the way the language groups it, and the
            // Japanese and Chinese counters take no space before them — the
            // rule `exceptionsRow` and `Plural.apps` already hold.
            if language == .ja { XCTAssertTrue(said.contains("37語"), said) }
            if language == .zh { XCTAssertTrue(said.contains("37个"), said) }
        }
    }

    /// Zero is a number too: a tile drawn on a quiet fortnight must still say
    /// what it is showing rather than fall back to the span.
    func testAQuietFortnightIsStillRead() {
        for language in AppLanguage.allCases {
            let said = LyStr.fortnightSummary(total: 0, today: 0, language: language)
            XCTAssertFalse(said.isEmpty, language.rawValue)
            XCTAssertTrue(said.contains("0"), "\(language.rawValue): \(said)")
        }
    }

    /// `accessibilityLabel` replaces a control's label rather than adding to it,
    /// so naming the period menu dropped the one fact it exists to show. The
    /// value carries it; this holds that the two are different strings, because
    /// a value equal to the label is the same defect with more code.
    func testThePeriodMenuHasBothANameAndAValue() {
        for language in AppLanguage.allCases {
            for period in ConversionPeriod.allCases {
                XCTAssertNotEqual(LyStr.period,
                                  LyStr.periodName(period, language: language),
                                  "\(language.rawValue)/\(period.rawValue)")
            }
        }
    }

    /// The last change, read after the fact. `LayoutAnnouncer` says it correctly
    /// when the change happens; this is the row in the tile and on the page.
    func testTheLastChangeReadsAsOneSentence() {
        for language in AppLanguage.allCases {
            let said = LyStr.pairRead(before: "vjq", after: "мой", language: language)
            XCTAssertTrue(said.contains("vjq") && said.contains("мой"), language.rawValue)
            XCTAssertGreaterThan(said.count, "vjq → мой".count,
                                 "\(language.rawValue): the label is the arrow row again, which "
                                 + "is what a reader was already getting in three pieces")
            // **The assertion this file was missing.** `ConversionPair` hides
            // the arrow glyph from VoiceOver on the grounds that the label says
            // it in words — and the label put the same `→` straight back, so a
            // reader heard it from the one place it had been removed.
            XCTAssertFalse(said.contains("→"),
                           "\(language.rawValue) reads the arrow aloud: \(said)")
        }
    }

    /// And it is not the announcement: that one ends by telling the person to
    /// press the key again, which is untrue of a row read minutes later.
    func testTheRowDoesNotRepeatTheUndoInvitation() {
        for language in AppLanguage.allCases {
            let row = LyStr.pairRead(before: "vjq", after: "мой", language: language)
            let announced = LyStr.fixedAnnouncement(before: "vjq", after: "мой",
                                                    undoable: true, language: language)
            XCTAssertLessThan(row.count, announced.count, language.rawValue)
        }
    }
}
