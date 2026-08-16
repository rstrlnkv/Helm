import HelmContract
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The id has one spelling, and the engine owns it.
///
/// `AutopilotDescriptor` carried `ModuleID("autopilot")` while the engine
/// spelled the same word at every log line — two spellings nothing compared,
/// which is the drift `StoreNamespacesAreModuleIdsTests` documents for the
/// other modules. The descriptor forwards `AutopilotEngine.moduleID` now, the
/// direction it already carries the command enums.
///
/// Two assertions on purpose. The second alone reads one shared constant on
/// both sides once the descriptor forwards it, which is a check that cannot
/// fail (CLAUDE.md names that family) — it only catches the descriptor being
/// rewritten as a diverging literal. The first pins the constant's *value*
/// against a literal written here: the id is the `module.autopilot.*` prefix
/// of every setting this module has saved, so a rename loses people their
/// rules with nothing anywhere reporting an error.
final class TheDescriptorForwardsTheEnginesIdTests: XCTestCase {

    func testTheEnginesIdIsTheOneThatShipped() {
        XCTAssertEqual(AutopilotEngine.moduleID, "autopilot",
                       "the engine's id is stored-settings data; renaming it strands "
                       + "every `module.autopilot.*` key already on people's machines")
    }

    @MainActor func testTheDescriptorReadsTheEnginesConstant() {
        XCTAssertEqual(AutopilotDescriptor.id, ModuleID(AutopilotEngine.moduleID),
                       "the descriptor's id diverged from the engine's — the store "
                       + "namespace and the log would then name two different modules")
    }
}
