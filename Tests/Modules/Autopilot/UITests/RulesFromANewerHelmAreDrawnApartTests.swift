import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **Rules a newer Helm wrote are drawn apart, each under the folder it belongs to.**
///
/// The model keeps `status.unapplied` in the turn it reads the folders; a live
/// folder's rules are its own, a removed folder's are one group after the list,
/// and a Mac whose only unapplied rules sit in a removed folder still draws the
/// folder page, or those rules are hidden by the empty state.
@MainActor
final class RulesFromANewerHelmAreDrawnApartTests: XCTestCase {

    private func rule(_ folder: String, _ index: Int, _ name: String?, path: String? = nil) -> UnappliedRule {
        UnappliedRule(folderID: folder, index: index, name: name, raw: Data("{}".utf8), removedFolderPath: path)
    }

    private func loaded(folders: [WatchedFolder], unapplied: [UnappliedRule]) async -> AutopilotViewModel {
        let work = FakeAutopilotWork(folders: folders,
                                     status: AutopilotStatus(refusal: nil, unapplied: unapplied))
        let model = AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in })
        await model.load()
        return model
    }

    func testALiveFoldersRulesAreItsOwnAndNotTheRemovedGroups() async {
        let a = WatchedFolder(id: "a", path: "/tmp/a"), b = WatchedFolder(id: "b", path: "/tmp/b")
        let model = await loaded(folders: [a, b], unapplied: [rule("a", 1, "Old"), rule("b", 0, nil)])
        XCTAssertEqual(model.unapplied(in: a).map(\.index), [1])
        XCTAssertEqual(model.unapplied(in: b).map(\.name), [nil])
        XCTAssertTrue(model.removedFolderRules.isEmpty, "a live folder's rules were drawn as a removed folder's")
    }

    func testARemovedFoldersRulesAreOneGroupWithItsPath() async {
        let a = WatchedFolder(id: "a", path: "/tmp/a")
        let model = await loaded(folders: [a], unapplied: [
            rule("gone", 0, "X", path: "/tmp/gone"), rule("a", 0, "Y"),
            rule("gone", 2, "Z", path: "/tmp/gone"), rule("other", 0, "W", path: nil)])
        let groups = model.removedFolderRules
        XCTAssertEqual(groups.map(\.id), ["gone", "other"])
        XCTAssertEqual(groups[0].rules.map(\.index), [0, 2])
        XCTAssertEqual(groups[0].path, "/tmp/gone")
        XCTAssertNil(groups[1].path)
        XCTAssertEqual(model.unapplied(in: a).map(\.name), ["Y"])
    }

    func testOnlyARemovedFoldersRulesStillDrawTheFolderPage() async {
        let model = await loaded(folders: [], unapplied: [rule("gone", 0, "X", path: "/tmp/gone")])
        XCTAssertEqual(model.screen, .folders)
    }

    func testNoUnappliedRulesAndNoFoldersIsStillTheEmptyState() async {
        let model = await loaded(folders: [], unapplied: [])
        XCTAssertEqual(model.screen, .noFolders)
    }
}
