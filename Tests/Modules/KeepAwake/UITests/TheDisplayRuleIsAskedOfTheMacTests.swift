import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// «Keep awake with an external display» on a Mac that has no display of its own.
///
/// The rule is about being *docked*, and a mini, a Studio or a Pro has no notion
/// of docked: every display it has is external, so the rule would mean «never
/// sleep». Three places in this module decide something from the stored flag, and
/// they were fixed one at a time:
///
/// - the **engine** refuses it — `externalDisplayCondition` opens with
///   `guard MacHardware.hasBuiltInDisplay`;
/// - the **row** is not drawn — `KeepAwakeSettingsPage` wraps it in the same
///   question;
/// - the **mark column** stopped counting it, which is `MarkableRules` and the
///   reason that type exists: a Studio whose plist was written while it was a
///   laptop indented all five visible rows for a mark nothing could put there.
///
/// Two readers were left behind by that pass, and both are on the same migrated
/// `true` the third one was about — a plist carried over from a laptop, or a
/// hand-edited one:
///
/// 1. `anyRuleOn` (`KeepAwakeSettingsPage`) is `autoExternalDisplay || autoPower
///    || !appTriggers.isEmpty` with no hardware in it, and it decides the hero's
///    reason line. On a desktop with the flag set and nothing else configured the
///    page says «No rule applies right now» — announcing a rule whose row is not
///    on the page, which no screen can switch off, and which the engine will
///    never honour. «No rule is switched on» is the true sentence and is the one
///    it draws for every other unreachable rule.
/// 2. `KeepAwakePanelTile` draws the switch itself, ungated. The panel is the
///    surface people actually use, so on a desktop it *offers* the rule the page
///    hides — and flipping it there is what puts the page into the state above.
///
/// **This is a source check, and it is one because the render cannot be taken
/// here.** `MacHardware.hasBuiltInDisplay` is a fact about the machine the suite
/// is running on, and this Mac has a built-in panel: both defects are invisible
/// in every pixel this repository can photograph. `MarkableRules` is what the fix
/// looked like the first time — the hardware as a parameter, so the rule is a
/// function with a test — and the assertion below is satisfied by anything of
/// that shape. What it cannot be satisfied by is the state of the tree today.
final class TheDisplayRuleIsAskedOfTheMacTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let text = try RepoSource.text(of: "Sources/Modules/KeepAwake/UI/\(name)")
        XCTAssertGreaterThan(text.count, 5000, "\(name) was not read at all")
        return text
    }

    /// The fact the two readers are wrong about, stated where it has a test: on a
    /// Mac with no panel of its own, a stored display rule is not a rule. Anything
    /// that reports «a rule is configured» from that flag is reporting nothing.
    func testADisplayRuleOnADesktopIsNoRuleAtAll() {
        let rules = MarkableRules.of(autoExternalDisplay: true, autoPower: false,
                                     lidHolding: false, hasBuiltInDisplay: false, hasLid: false)
        XCTAssertTrue(rules.rules.isEmpty,
                      "the engine, the row and the mark column all read this flag through the "
                      + "hardware; the two call sites below are the ones that do not")
    }

    /// The row itself is still gated, or the two checks below are about a rule
    /// this module no longer hides and the reasoning has moved.
    func testTheRowIsStillHiddenOnAMacWithNoPanelOfItsOwn() throws {
        let page = try source("KeepAwakeSettingsPage.swift")
        XCTAssertTrue(page.contains("if MacHardware.hasBuiltInDisplay {"),
                      "the display rule's row is no longer hidden on a desktop, so what the "
                      + "hero says about it is a different question from the one asked here")
    }

    /// The hero's reason line is not decided by the raw flag.
    func testTheReasonLineDoesNotCountARuleThisMacCannotDraw() throws {
        let page = try source("KeepAwakeSettingsPage.swift")
        XCTAssertFalse(page.contains("autoExternalDisplay || autoPower"),
                       "`anyRuleOn` counts the display rule without asking whether this Mac "
                       + "draws its row, so a desktop with a migrated `true` is told «No rule "
                       + "applies right now» about a rule it has no control for. The hardware "
                       + "belongs in the answer, the way `MarkableRules` put it there")
    }

    /// And the panel does not offer it where it can do nothing.
    func testThePanelDoesNotOfferTheRuleOnAMacThatCannotUseIt() throws {
        let tile = try source("KeepAwakePanelTile.swift")
        XCTAssertTrue(tile.contains("MacHardware.hasBuiltInDisplay"),
                      "the panel's ⋯ block draws «Keep awake with an external display» on every "
                      + "Mac. On a mini or a Studio the engine refuses the rule outright, so the "
                      + "switch is inert — and it is the writer that puts `autoExternalDisplay` "
                      + "true on a machine whose settings page has no row to turn it back off")
    }
}
