import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The «Show the rules to start with» menu is for a page with no rules on it.**
///
/// The owner's sentence: the block is needed only while there is no rule at all,
/// and after that it goes. The condition lives in the one place that fills the
/// published `presets` list, which the page draws both of its copies from — so
/// there is no second account of «are there rules» in a view.
@MainActor
final class StartingRulesAreOfferedOnlyWhileThereAreNoneTests: XCTestCase {

    private let home = "/Users/x"

    private func model(folders: [WatchedFolder]) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: AutopilotWire(folders: folders)),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func rule(enabled: Bool = true) -> Rule {
        Rule(id: "mine", name: "Mine", enabled: enabled,
             conditions: [.kind(.image)], action: .trash)
    }

    func testNoRulesAtAllOffersTheBlock() async {
        let model = model(folders: [])
        await model.load()
        XCTAssertFalse(model.presets.isEmpty)
    }

    /// A watched folder with no rule in it is still a page with no rules.
    func testAFolderWithoutRulesStillOffersTheBlock() async {
        let model = model(folders: [WatchedFolder(path: home + "/Music")])
        await model.load()
        XCTAssertEqual(model.screen, .folders, "precondition: the folder list is what is drawn")
        XCTAssertFalse(model.presets.isEmpty)
    }

    func testOneRuleRemovesTheBlock() async {
        let model = model(folders: [WatchedFolder(path: home + "/Music", rules: [rule()])])
        await model.load()
        XCTAssertEqual(model.screen, .folders, "precondition: the rule is on the page")
        XCTAssertEqual(model.presets, [])
    }

    /// A rule that is switched off is still somebody's rule.
    func testASwitchedOffRuleAlsoRemovesTheBlock() async {
        let model = model(folders: [WatchedFolder(path: home + "/Music",
                                                  rules: [rule(enabled: false)])])
        await model.load()
        XCTAssertEqual(model.presets, [])
    }
}
