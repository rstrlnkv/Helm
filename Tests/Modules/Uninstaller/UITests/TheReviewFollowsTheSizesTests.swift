import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The review opened before the sizes arrived says nothing about them until
/// they do, and what it removes does not move.**
///
/// `groups` is a snapshot of the ticked apps taken at the press and carries the
/// list's zero; the size on screen comes from `measuredSizes`, which goes on
/// arriving, through `reviewBytes`.
@MainActor
final class TheReviewFollowsTheSizesTests: XCTestCase {

    private let app = InstalledApp(name: "Gamma", bundleID: "com.x.gamma",
                                   path: "/Applications/Gamma.app", sizeBytes: 9_000)

    func testTheTotalIsUnknownUntilTheSizeLandsAndThenIsTheSize() async {
        let wire = UninstallerWire(apps: [app], scans: [
            app.bundleID: ScanResult(bundleID: app.bundleID, appPath: app.path, appSizeBytes: 0,
                                     leftovers: [], runningNow: false)])
        wire.answers(.nothing, to: .appSizes)
        let uvm = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await uvm.loadAppsIfNeeded()
        uvm.toggleChecked(app.bundleID)
        await uvm.prepareReview()
        XCTAssertEqual(uvm.step, .review, "the review never opened")
        XCTAssertNil(uvm.reviewBytes, "a total was claimed for an app nobody measured")
        let before = (uvm.groups.map(\.app.path), uvm.selectedLeftovers, uvm.checked)

        wire.answers(.reply, to: .appSizes)
        await uvm.reloadApps()
        XCTAssertEqual(uvm.measuredSizes[app.path], 9_000, "precondition: the size landed")
        XCTAssertEqual(uvm.reviewBytes, 9_000, "the review did not pick the size up")
        let after = (uvm.groups.map(\.app.path), uvm.selectedLeftovers, uvm.checked)
        XCTAssertEqual(before.0, after.0, "the sizes moved what the review names")
        XCTAssertEqual(before.1, after.1)
        XCTAssertEqual(before.2, after.2)
    }
}
