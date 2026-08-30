import XCTest
@testable import Module_Layout_UI

/// **The hero said it was watching while the module was deliberately deaf.**
///
/// Its two lines decided separately. The caption asked `watching`, then whether
/// there was a count, then the pause — so `suspended` was unreachable whenever
/// the chosen period held nothing. The figure never asked about the pause at
/// all. The period defaults to «today», so a zero count is the whole of every
/// morning before the first correction, and that is when a password sheet is
/// most likely to be in front: buffer dropped, remembered word dropped, undo
/// record dropped, and the page reading «Watching your words».
///
/// The window header said «Paused» at that same instant, because
/// `LayoutDescriptor.activity` reads both flags — so the two halves of one
/// sentence contradicted each other 56 pt apart.
final class ThePauseOutranksTheCountTests: XCTestCase {

    /// The state the defect lived in, and the reason this file exists.
    func testAPauseWithNothingCountedIsStillAPause() {
        XCTAssertEqual(HeroSentence(watching: true, suspended: true, hasFigure: false),
                       .paused(hasFigure: false))
    }

    /// And the pause takes the caption without taking the number: a sheet is up
    /// for as long as it takes to type a password, and what the module put
    /// right today does not stop being true while it is.
    func testAPauseKeepsTheFigureItHas() {
        let state = HeroSentence(watching: true, suspended: true, hasFigure: true)
        XCTAssertEqual(state, .paused(hasFigure: true))
        XCTAssertTrue(state.showsFigure)
    }

    /// Not delivering keystrokes outranks everything, including a pause: with
    /// no grant there is nothing to be paused from.
    func testNoKeystrokesOutranksThePause() {
        for suspended in [true, false] {
            for hasFigure in [true, false] {
                XCTAssertEqual(
                    HeroSentence(watching: false, suspended: suspended, hasFigure: hasFigure),
                    .deaf,
                    "watching: false, suspended: \(suspended), hasFigure: \(hasFigure)")
            }
        }
    }

    func testWatchingWithNothingToShowIsNotAFault() {
        XCTAssertEqual(HeroSentence(watching: true, suspended: false, hasFigure: false),
                       .nothingYet)
        XCTAssertFalse(HeroSentence(watching: true, suspended: false, hasFigure: false).showsFigure)
    }

    func testWatchingWithSomethingToShowCounts() {
        let state = HeroSentence(watching: true, suspended: false, hasFigure: true)
        XCTAssertEqual(state, .counting)
        XCTAssertTrue(state.showsFigure)
    }

    /// Every combination lands somewhere, and the eight are the eight — a table
    /// rather than five assertions, so a fifth case added tomorrow has to be
    /// filed here rather than joining silently.
    func testTheEightInputsAreTheFiveStates() {
        var seen: [HeroSentence] = []
        for watching in [true, false] {
            for suspended in [true, false] {
                for hasFigure in [true, false] {
                    seen.append(HeroSentence(watching: watching, suspended: suspended,
                                             hasFigure: hasFigure))
                }
            }
        }
        XCTAssertEqual(seen.count, 8)
        XCTAssertEqual(seen.filter { $0 == .deaf }.count, 4)
        XCTAssertEqual(seen.filter { $0 == .paused(hasFigure: true) }.count, 1)
        XCTAssertEqual(seen.filter { $0 == .paused(hasFigure: false) }.count, 1)
        XCTAssertEqual(seen.filter { $0 == .nothingYet }.count, 1)
        XCTAssertEqual(seen.filter { $0 == .counting }.count, 1)
    }
}
