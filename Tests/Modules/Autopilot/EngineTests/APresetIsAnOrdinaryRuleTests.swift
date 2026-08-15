import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// **A preset is a rule, not a second kind of thing.**
///
/// Everything the module already does — the stamp that stops a rule acting
/// twice, the thirty-day history, the return, the dry run — is keyed to a
/// `Rule` and its id. A preset that were its own entity would need every one of
/// those again, and the second copy is where they drift. So a preset is a set of
/// values that builds an ordinary `Rule` with a fixed id, and these are the
/// promises that keeps: it can be switched on, and it reaches storage as the
/// rule that was shown.
final class APresetIsAnOrdinaryRuleTests: XCTestCase {

    /// Somewhere every preset's folder is allowed, so `storable` is asked about
    /// the rule rather than about the path.
    private let folder = "/Users/x/Downloads"

    private func rule(_ preset: RulePreset) -> Rule {
        preset.rule(named: "n", in: folder)
    }

    // MARK: - The table

    /// A sixth preset added to the enum and not to the table would be a name in
    /// the UI's switch with nothing behind it.
    func testEveryKindHasExactlyOnePreset() {
        XCTAssertEqual(RulePreset.all.count, PresetKind.allCases.count)
        XCTAssertEqual(Set(RulePreset.all.map(\.id)).count, RulePreset.all.count,
                       "two presets share an id, so one would read as the other already added")
    }

    /// The id is the rule's id and it is fixed: it is what «already added»,
    /// every stamp and every history row are keyed by.
    func testEveryIDIsNamespacedAndFixed() {
        for preset in RulePreset.all {
            XCTAssertTrue(preset.id.hasPrefix("preset."), "\(preset.id) is not a preset id")
            XCTAssertEqual(rule(preset).id, preset.id)
            XCTAssertEqual(rule(preset).id, preset.rule(named: "other", in: folder).id,
                           "the id must not depend on anything a screen supplies")
        }
    }

    // MARK: - What the switch is allowed to do

    /// Every preset arrives switched on, and every preset *may* be: a rule with
    /// no conditions matches nothing and a rule whose action names nothing
    /// refuses everything, and either would ship as a preset that does nothing
    /// while saying it works.
    func testEveryPresetCanBeSwitchedOn() {
        for preset in RulePreset.all {
            XCTAssertTrue(rule(preset).canBeEnabled, "\(preset.id) cannot be switched on")
            XCTAssertTrue(rule(preset).enabled, "\(preset.id) arrives switched off")
        }
    }

    // MARK: - What reaches the engine

    /// **The rule that was shown is the rule that is stored.**
    ///
    /// `storable` drops a condition carrying a number nobody could have typed,
    /// and `0` is one of them — "larger than 0 MB" and "older than 0 days" are
    /// true of every file in the folder, so the repair for a corrupt number is
    /// to drop the condition. A preset written with a `0` would therefore reach
    /// storage as a *wider* rule than the one whose dry run somebody read: «old
    /// installers to the Trash» would keep the `dmg`/`pkg` half and lose the
    /// thirty days.
    ///
    /// Asserted over the conditions rather than over `enabled`, because two of
    /// the five would still be switched on after losing one.
    func testEveryPresetReachesStorageAsTheRuleThatWasShown() {
        for preset in RulePreset.all {
            let stored = WatchedFolder(id: "f", path: folder, rules: [rule(preset)])
                .storable.rules.first
            XCTAssertEqual(stored?.conditions, preset.conditions,
                           "\(preset.id) lost a condition on the way into storage")
            XCTAssertEqual(stored?.action, rule(preset).action)
            XCTAssertEqual(stored?.enabled, true, "\(preset.id) arrived switched off")
        }
    }

    // MARK: - The folders they make

    /// The subfolder a preset moves into is inside the folder it watches, and
    /// its name is English and fixed — the law `SortBucket` already keeps for
    /// the buckets a sorting rule makes. A translated `Screenshots` would make
    /// a second folder the day somebody changes language.
    func testAPresetMovesInsideTheFolderItWatches() {
        for preset in RulePreset.all {
            guard case let .move(to: destination) = rule(preset).action else { continue }
            XCTAssertTrue(destination.hasPrefix(folder + "/"),
                          "\(preset.id) moves out of the folder it watches")
            XCTAssertEqual(destination, preset.rule(named: "другое", in: folder).action.destination,
                           "\(preset.id) names its folder in the reader's language")
        }
    }
}

private extension RuleAction {
    var destination: String? {
        if case let .move(to: path) = self { return path }
        return nil
    }
}
