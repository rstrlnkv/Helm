import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The states the action picker can put a rule into.
///
/// `Kind.blank` is what picking a different action produces, and one of them
/// deliberately names nothing: a move's destination only ever arrives through
/// the panel, so the module must not guess where somebody's files go. That
/// makes an unrunnable rule a state the editor hands out on purpose, and the
/// only thing standing between it and a refusal logged every hour is the
/// switch beside it.
final class ActionRowTests: XCTestCase {

    private func rule(_ action: RuleAction) -> Rule {
        Rule(id: "r", name: "r", enabled: true,
             conditions: [.fileExtension(["pdf"])], action: action)
    }

    /// Every kind the picker offers, against the one predicate the switch uses.
    /// Written as the whole list rather than as the move alone, so a new action
    /// with a blank of its own is a decision somebody has to make here.
    func testTheOnlyBlankTheSwitchRefusesIsTheOneThePanelFills() {
        var refused: [ActionRow.Kind] = []
        for kind in ActionRow.Kind.allCases where !rule(kind.blank).canBeEnabled {
            refused.append(kind)
        }
        XCTAssertEqual(refused, [.move, .tag],
                       "a blank action the switch would accept refuses every file it matches")
    }

    /// And the move becomes usable the moment the panel has been used, which is
    /// the only way a destination gets in.
    func testAMoveIsEnableableOnceItHasSomewhereToGo() {
        XCTAssertFalse(rule(ActionRow.Kind.move.blank).canBeEnabled)
        XCTAssertTrue(rule(.move(to: "/Users/x/Invoices")).canBeEnabled)
    }
}
