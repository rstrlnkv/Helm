import XCTest
@testable import Module_KeepAwake_Engine

/// The wording of the one line that says why the Mac is being held awake.
///
/// It exists because `activeConditions` is a `Set`, and a `Set` has no order: a
/// log line built by iterating it prints its reasons in whatever order the hash
/// seed gave that launch. Two runs of the same session then read as two different
/// events, `grep -c` counts nothing reliable, and a diff between two triage logs
/// is noise. Ordering is the whole job.
final class ConditionLabelTests: XCTestCase {

    func testTheOrderIsTheSameEveryTime() {
        let all: Set<ActiveCondition> = [.app, .power, .timer, .externalDisplay, .manual]
        // Built from a differently-ordered literal, and across enough repetitions
        // that a hash-seeded iteration would have shown itself.
        let again: Set<ActiveCondition> = [.manual, .externalDisplay, .timer, .power, .app]
        let expected = "manual+timer+display+power+app"

        XCTAssertEqual(ConditionLabel.of(all), expected)
        XCTAssertEqual(ConditionLabel.of(again), expected)
        for _ in 0..<50 { XCTAssertEqual(ConditionLabel.of(all), expected) }
    }

    /// The order is the order the conditions are explained in, not alphabetical:
    /// what the person did comes before what their hardware is doing.
    func testWhatThePersonAskedForComesFirst() {
        XCTAssertEqual(ConditionLabel.of([.power, .manual]), "manual+power")
        XCTAssertEqual(ConditionLabel.of([.app, .timer]), "timer+app")
    }

    func testOneConditionIsJustItself() {
        XCTAssertEqual(ConditionLabel.of([.timer]), "timer")
    }

    /// Held by nothing is a real state — it is what the line says when the session
    /// has just ended — and it must not print as an empty string, which reads in
    /// the log as a missing value rather than as "no reason any more".
    func testNoConditionsSaysSo() {
        XCTAssertEqual(ConditionLabel.of([]), "none")
    }

    /// Every case has a word. A new condition added to the enum without one would
    /// otherwise vanish from the log silently — the reason the module was holding
    /// sleep would be the one thing missing from the line explaining it.
    func testEveryConditionHasAWord() {
        for condition in ActiveCondition.allCases {
            let word = ConditionLabel.of([condition])
            XCTAssertFalse(word.isEmpty, "\(condition) has no word")
            XCTAssertNotEqual(word, "none", "\(condition) prints as the empty state")
        }
    }
}
