import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// A removal through the door marks the list stale, and a refused one does not.
///
/// The busy guard is held in both directions by `ADoorRemovalMeetsTheRestOfThePageTests`, whose held
/// fake has one gate per caller; a door-beside-door test on one shared gate would hang, not fail.
@MainActor
final class TheDoorTakesOneRemovalAtATimeTests: XCTestCase {

    private let candidate = AppRemovalCandidate(bundleID: "com.acme.player",
                                                path: "/Applications/Player.app", name: "Player")

    func testARemovedAppMarksTheListStaleAndAFailedOneDoesNot() async {
        let work = AnsweringWork(apps: [InstalledApp(name: "Player", bundleID: candidate.bundleID,
                                                     path: candidate.path)])
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        work.appReport = AppRemovalReport(.refused, failed: [.noPermission])
        _ = await model.remove(candidate, quittingIfRunning: false)
        await model.loadAppsIfNeeded()
        XCTAssertEqual(work.calls.filter { $0 == .listApps }.count, 1, "a refused removal re-read the list")

        work.appReport = AppRemovalReport(.moved, freedBytes: 5)
        _ = await model.remove(candidate, quittingIfRunning: false)
        await model.loadAppsIfNeeded()
        XCTAssertEqual(work.calls.filter { $0 == .listApps }.count, 2,
                       "the list still shows an app that is in the Trash")
    }
}
