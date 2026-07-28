import XCTest
@testable import Module_Autopilot_Engine

/// Two answers to "which numbers may a condition carry".
///
/// `accepts` was added today so the editor's field and the storage bound would
/// stop drifting — its own comment says so, and says why `0` must be refused:
/// "larger than 0 MB" is a condition that matches every file, which is not a
/// rule anybody means. `clamp`, which is what actually decides what reaches the
/// engine, was left alone and still admits `0` — and turns every negative into
/// one.
///
/// `clamp`'s comment claims the two are the same rule and names the way in:
/// "a value arriving from a hand-edited plist ends up where a typed one would".
/// A rule with `"megabytes": -1` in the store is `larger than 0 MB` in the
/// engine, on a timer, with nobody looking — which is the shape of the defect
/// `FileWeight` was written for last week.
final class RuleNumberBoundsTests: XCTestCase {

    /// The sentence, as an assertion, about the thing that reaches the engine.
    ///
    /// `clamp` brings a number into the range `JSONEncoder` will take and does
    /// not claim to match the field — a negative clamps to `0`, which the field
    /// refuses. `storable` is where the field's rule is applied, and it drops a
    /// condition it cannot repair rather than storing one that matches every
    /// file in the folder.
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

    /// And what that costs. A size rule that reached storage as `0` is true of
    /// every file in the watched folder, whatever the action beside it is.
    func testASizeConditionCannotBeStoredInAFormThatMatchesEverything() {
        let condition = RuleCondition.size(.largerThan, megabytes: -1).storable
        let file = FileFacts(name: "notes.txt", path: "/Users/x/Downloads/notes.txt",
                             kind: .document, bytes: 1,
                             added: Date(timeIntervalSince1970: 0),
                             modified: Date(timeIntervalSince1970: 0),
                             now: Date(timeIntervalSince1970: 0))
        // `storable` now drops such a condition rather than repairing it, so
        // the rule is left with none — and `RuleMatcher` refuses those.
        let rule = Rule(id: "r", name: "Big files", enabled: true,
                        conditions: [condition].compactMap { $0 }, action: .trash)

        XCTAssertFalse(RuleMatcher.matches(file, rule),
                       "a one-byte file matched \"larger than \(condition)\": the stored "
                       + "condition is one the editor would not let anybody write")
        XCTAssertNil(condition, "an unusable number is dropped, not brought up to zero")
    }

    /// The guard on the other side, so a fix cannot be bought by refusing
    /// everything: an ordinary number survives storage unchanged.
    func testAnOrdinaryNumberIsStoredAsItself() {
        XCTAssertEqual(RuleCondition.clamp(30), 30)
        XCTAssertTrue(RuleCondition.accepts(30))
    }
}
