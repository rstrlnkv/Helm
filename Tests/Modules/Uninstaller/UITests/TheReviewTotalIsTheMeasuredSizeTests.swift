import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The review's footer total takes each bundle's size from `measuredSizes`, by
/// path. The group's own `InstalledApp.sizeBytes` is the list's zero and must
/// never be what is summed.
@MainActor
final class TheReviewTotalIsTheMeasuredSizeTests: XCTestCase {

    private let tool = InstalledApp(name: "Vendor Player", bundleID: "com.vendor.player",
                                    path: "/Applications/Vendor Player.app", sizeBytes: 0)
    private let leftover = Leftover(path: "/L/prefs", kind: .preferences, sizeBytes: 700,
                                    matchedByName: false)

    private func review(_ work: AnsweringWork) async -> UninstallerViewModel {
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        model.setChecked(tool, true)
        await model.prepareReview()
        return model
    }

    func testTheTotalIsTheMeasuredBundlePlusTheSelectedLeftover() async {
        let work = AnsweringWork(apps: [tool],
                                 scans: [tool.bundleID: ScanResult(leftovers: [leftover], runningNow: false)],
                                 sizes: [tool.path: 5_000])
        let model = await review(work)
        model.setSelected(leftover: leftover.path, true)
        XCTAssertEqual(model.groups.first?.app.sizeBytes, 0, "precondition: the group carries the list's zero")
        XCTAssertEqual(model.reviewBytes, 5_700)
        model.setSelected(leftover: leftover.path, false)
        XCTAssertEqual(model.reviewBytes, 5_000)
    }

    func testNoTotalWhileTheBundleIsUnmeasured() async {
        let work = AnsweringWork(apps: [tool],
                                 scans: [tool.bundleID: ScanResult(leftovers: [leftover], runningNow: false)],
                                 sizes: ["/Applications/Other.app": 9])
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        model.setChecked(tool, true)
        await model.prepareReview()
        XCTAssertNil(model.reviewBytes, "a sum with the bundle missing is a number nobody measured")
    }
}
