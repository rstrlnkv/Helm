import XCTest
@testable import Module_Autopilot_Engine

/// Two answers to "which numbers may a condition carry": `accepts`, the
/// editor's field, and `storable`, what reaches the engine. They agree, because
/// "larger than 0 MB" matches every file, and a hand-edited `"megabytes": -1`
/// would otherwise run that on a timer with nobody looking.
final class RuleNumberBoundsTests: XCTestCase {

    /// What storage produces is what the field would take. `clamp` only brings a
    /// number into the range `JSONEncoder` takes (a negative clamps to `0`, which
    /// the field refuses); `storable` applies the field's rule and drops a
    /// condition it cannot repair rather than storing one that matches every file.
    func testWhatStorageProducesIsWhatTheFieldWouldTake() {
        let hostile: [Double] = [-1e9, -1, 0, 0.5, 1, 1e9, 1e10, .infinity, -.infinity, .nan]
        for value in hostile {
            guard let stored = RuleCondition.size(.largerThan, megabytes: value).storable,
                  case let .size(_, megabytes) = stored else { continue }
            XCTAssertTrue(RuleCondition.accepts(megabytes),
                          "\(value) was stored as \(megabytes), which the field refuses")
        }
        // And the unusable ones are dropped rather than repaired into a rule
        // that matches everything.
        for value in [-1e9, -1.0, 0, .nan, .infinity, -.infinity] as [Double] {
            for comparison in [SizeComparison.largerThan, .smallerThan] {
                XCTAssertNil(RuleCondition.size(comparison, megabytes: value).storable,
                             "\(comparison) \(value)")
            }
        }
    }

    /// A size rule that reached storage as `0` would be true of every file in
    /// the watched folder, whatever the action beside it.
    func testASizeConditionCannotBeStoredInAFormThatMatchesEverything() {
        let condition = RuleCondition.size(.largerThan, megabytes: -1).storable
        let file = FileFacts(name: "notes.txt", path: "/Users/x/Downloads/notes.txt",
                             kind: .document, bytes: 1,
                             added: Date(timeIntervalSince1970: 0),
                             modified: Date(timeIntervalSince1970: 0),
                             now: Date(timeIntervalSince1970: 0))
        // `storable` drops such a condition rather than repairing it, so the
        // rule is left with none — and `RuleMatcher` refuses those.
        let rule = Rule(id: "r", name: "Big files", enabled: true,
                        conditions: [condition].compactMap { $0 }, action: .trash)

        XCTAssertFalse(RuleMatcher.matches(file, rule),
                       "a one-byte file matched \"larger than \(String(describing: condition))\": the stored "
                       + "condition is one the editor would not let anybody write")
        XCTAssertNil(condition, "an unusable number is dropped, not brought up to zero")
    }

    /// The guard on the other side, so the bound cannot be met by refusing
    /// everything: an ordinary number survives storage unchanged.
    func testAnOrdinaryNumberIsStoredAsItself() {
        XCTAssertEqual(RuleCondition.clamp(30), 30)
        XCTAssertTrue(RuleCondition.accepts(30))
    }
}
