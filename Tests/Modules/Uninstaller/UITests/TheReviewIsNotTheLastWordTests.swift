import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The review's «Running» flag (`ScanResult.runningNow`) is a reading, not
/// the last word, in both directions: an app quit while the person reads must
/// not leave «Move to Trash» dead, and one that came back up must be asked.
/// The batch carries the person's answer to «Force quit and remove anyway»,
/// and the engine asks who is up at the move.
@MainActor
final class TheReviewIsNotTheLastWordTests: XCTestCase {

    private let tool = InstalledApp(name: "Vendor Player", bundleID: "com.vendor.player",
                                    path: "/Applications/Vendor Player.app")

    /// A review of one app that the scan saw running.
    private func reviewed(_ work: AnsweringWork) async -> UninstallerViewModel {
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        model.setChecked(tool, true)
        await model.prepareReview()
        return model
    }

    private func work(runningAtScan: Bool,
                      removal: UninstallResult = UninstallResult(trashed: [], freedBytes: 0))
        -> AnsweringWork {
        AnsweringWork(
            apps: [tool],
            scans: [tool.bundleID: ScanResult(leftovers: [], runningNow: runningAtScan)],
            removal: removal)
    }

    // MARK: - The question travels with the batch

    /// The permission the person gave travels in the request that acts on it,
    /// not as a `quit` decided here from the scan's flag.
    func testThePersonsAnswerAboutQuittingTravelsWithTheBatch() async {
        for allowed in [true, false] {
            let work = work(runningAtScan: true,
                            removal: UninstallResult(trashed: [tool.path], freedBytes: 10))
            let model = await reviewed(work)
            model.forceQuit = allowed

            await model.removeSelection()

            XCTAssertEqual(work.batches.last?.quitting, allowed,
                           "the engine was not told whether it may quit a running app, so it "
                           + "has to guess at the moment it moves the bundle (\(allowed))")
        }
    }

    /// Direction one: the person quit the app themselves, so the press reaches
    /// the engine rather than being refused against an old reading.
    func testAPressReachesTheEngineEvenWhileTheReviewSaysSomethingIsRunning() async {
        let work = work(runningAtScan: true,
                        removal: UninstallResult(trashed: [tool.path], freedBytes: 10))
        let model = await reviewed(work)
        XCTAssertTrue(model.groups.allSatisfy(\.running), "precondition: the review says running")
        XCTAssertFalse(model.forceQuit, "precondition: nobody allowed a force quit")

        await model.removeSelection()

        XCTAssertEqual(work.batches.count, 1, """
            the press did nothing at all: the app the person had already quit still reads as \
            running here, and the only way out is Back → Review and a fresh scan of every \
            ticked app
            """)
    }

    // MARK: - What a held batch says

    /// Direction two: the app came back up and the engine moved nothing. Nothing
    /// claims a removal, and the review stays with the fresh reading.
    func testABatchHeldForARunningAppKeepsTheReviewAndSaysWhatToDo() async {
        let work = work(runningAtScan: false,
                        removal: UninstallResult(trashed: [], freedBytes: 0,
                                                 stillRunning: [tool.path]))
        let model = await reviewed(work)
        XCTAssertFalse(model.groups.contains(where: \.running),
                       "precondition: the review was built while the app was down")

        await model.removeSelection()

        XCTAssertEqual(model.step, .review, "the review the person still needs was cleared")
        XCTAssertEqual(model.resultBanner, UnStr.blockedByRunning, """
            a press that moved nothing said nothing: banner nil, step still .review, and the \
            person is looking at a button that appears not to work
            """)
        XCTAssertTrue(model.groups.allSatisfy(\.running), """
            the review still says the app is down, so the warning row and the force-quit \
            toggle — the offer the person needs — are not drawn
            """)
        XCTAssertTrue(model.failures.isEmpty,
                      "nothing was attempted, so nothing may be reported as a failure")
    }

    /// Leaving the review ends the round: the sentence about a batch held for a
    /// running app has nothing to say over the picker.
    func testGoingBackTakesTheReportWithIt() async {
        let work = work(runningAtScan: false,
                        removal: UninstallResult(trashed: [], freedBytes: 0,
                                                 stillRunning: [tool.path]))
        let model = await reviewed(work)
        await model.removeSelection()
        XCTAssertNotNil(model.resultBanner, "precondition: the report is up")

        model.backToPick()

        XCTAssertNil(model.resultBanner,
                     "the picker's footer draws this, where it is about nothing")
    }
}
