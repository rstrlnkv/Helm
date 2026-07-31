import XCTest
@testable import Module_Layout_Engine

/// Which layout the word is converted *into*.
///
/// With two input sources there is only one answer and the question never came
/// up. With three — and a Mac with English, Russian and Ukrainian is ordinary —
/// the engine took `installed().first(where: { $0 != current })`, which is
/// whichever the system happens to list first. So the module converted into a
/// layout the word has nothing to do with, and the person watched it produce
/// nonsense and switch their keyboard to a language they were not typing.
final class OtherSourceTests: XCTestCase {

    private let abc = "com.apple.keylayout.ABC"
    private let ru = "com.apple.keylayout.Russian"
    private let uk = "com.apple.keylayout.Ukrainian"

    func testTwoSourcesLeaveNoChoice() {
        XCTAssertEqual(
            OtherSource.pick(current: abc, installed: [abc, ru], makesSense: { _ in false }),
            ru, "with one other source it must still convert")
    }

    /// The case this exists for: the candidate that produces a real word wins,
    /// whatever order the system lists them in.
    func testTheSourceThatProducesAWordWins() {
        XCTAssertEqual(
            OtherSource.pick(current: abc, installed: [abc, uk, ru],
                             makesSense: { $0 == ru }),
            ru, "the first-listed layout won over the one that actually fits")
    }

    /// Nothing fits — `Fix` is still allowed to act, because forcing a
    /// conversion is exactly what that gesture is for. Falls back to the order
    /// the system gives, which is what it always did.
    func testNoCandidateFitsFallsBackToTheFirst() {
        XCTAssertEqual(
            OtherSource.pick(current: abc, installed: [abc, uk, ru], makesSense: { _ in false }),
            uk)
    }

    func testTheCurrentSourceIsNeverTheTarget() {
        XCTAssertNil(OtherSource.pick(current: abc, installed: [abc], makesSense: { _ in true }))
    }

    func testNothingInstalledIsNoAnswer() {
        XCTAssertNil(OtherSource.pick(current: abc, installed: [], makesSense: { _ in true }))
    }

    /// Asked once per candidate at most: the check spell-checks a translation,
    /// and a person waiting on a keystroke pays for every one of them.
    func testEachCandidateIsAskedAtMostOnce() {
        var asked: [String] = []
        _ = OtherSource.pick(current: abc, installed: [abc, uk, ru]) {
            asked.append($0)
            return $0 == uk
        }
        XCTAssertEqual(asked, [uk], "candidates were checked past the one that fit")
    }
}
