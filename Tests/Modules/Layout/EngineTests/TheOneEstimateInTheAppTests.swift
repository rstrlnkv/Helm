import XCTest
@testable import Module_Layout_Engine

/// Time saved is the only estimated figure Helm draws. Everything else — bytes,
/// words, how long a tunnel has been up — is measured. So the arithmetic is
/// held here, where the assumption behind it can be argued with, rather than
/// inline in a multiplication somewhere in a view.
final class TheOneEstimateInTheAppTests: XCTestCase {

    /// Nothing happened, so there is nothing to estimate — not «about zero».
    func testNoWordsIsNoTime() {
        XCTAssertEqual(TimeSaved.seconds(words: 0, characters: 0), 0)
        XCTAssertEqual(TimeSaved.seconds(words: 0, characters: 40), 0,
                       "characters with no word behind them are not an estimate")
    }

    /// An ordinary six-letter word comes to about three seconds: notice, clear,
    /// switch, type it again. If this number moves, the sentence on the page
    /// that names it has to move with it.
    func testAnOrdinaryWordIsAboutThreeSeconds() {
        XCTAssertEqual(TimeSaved.seconds(words: 1, characters: 6), 2.6, accuracy: 0.001)
    }

    /// **A long word is worth more than a short one**, which is why the ledger
    /// keeps characters at all. Two words of three letters and one word of six
    /// hold the same letters and are not the same work: two switches, not one.
    func testTheSameLettersInMoreWordsCostMore() {
        let oneLongWord = TimeSaved.seconds(words: 1, characters: 6)
        let twoShortOnes = TimeSaved.seconds(words: 2, characters: 6)
        XCTAssertGreaterThan(twoShortOnes, oneLongWord)
        XCTAssertEqual(twoShortOnes - oneLongWord, TimeSaved.secondsPerWord, accuracy: 0.001)
    }

    /// A month of ordinary use lands in minutes, not hours — the figure has to
    /// stay believable at the scale people will actually see it.
    func testAMonthOfUseIsMinutesNotHours() {
        let seconds = TimeSaved.seconds(words: 1284, characters: 1284 * 6)
        XCTAssertEqual(seconds / 60, 55.6, accuracy: 0.5)
    }

    /// The constants are a stated position, not a measurement, and they are
    /// named so the page can quote them. This test exists so a change to either
    /// one is deliberate.
    func testTheAssumptionIsWhatThePageSays() {
        XCTAssertEqual(TimeSaved.secondsPerWord, 1.4)
        XCTAssertEqual(TimeSaved.secondsPerCharacter, 0.2)
    }
}
