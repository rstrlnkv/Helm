import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The folder a person picks is stored with its seal, because the background
/// scan refuses a folder whose MAC is missing or does not match.
///
/// `chooseFolder` is a modal panel and cannot be pressed in a test; `use(folder:)`
/// is everything after the panel. A dropped seal, or one under another key,
/// leaves every background scan «not Helm's own».
@MainActor
final class AFolderTheOpenPanelGivesIsSealedTests: XCTestCase {

    func testTheChosenFolderIsStoredUnderItsKeyWithTheSealTheEngineAccepts() {
        let store = duplicatesStore(folder: "/some/folder")
        let dvm = duplicatesModel(over: HeldWork(), store: store)
        let chosen = URL(fileURLWithPath: home).appendingPathComponent("Pictures")

        dvm.use(folder: chosen)

        XCTAssertEqual(store.string("folder", default: ""), chosen.path)
        let guardOfTheEngine = SettingGuard(keys: SealKeyProbe(firstUse: false))
        let expected = guardOfTheEngine.seal(Data(chosen.path.utf8)) ?? ""
        XCTAssertFalse(expected.isEmpty, "precondition: the planted key seals")
        XCTAssertEqual(store.string("folderMAC", default: ""), expected,
                       "the seal of the chosen path, under the key the scan reads")
        guard case .mine(let path) = DuplicatesSettings.stored(
            DuplicatesSettings.folderKey, in: store, guardedBy: guardOfTheEngine) else {
            return XCTFail("the scan would not take the folder the person just chose")
        }
        XCTAssertEqual(path, chosen.path)
    }
}
