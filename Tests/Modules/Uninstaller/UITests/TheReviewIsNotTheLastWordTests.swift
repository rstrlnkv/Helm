import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The review's «Running» flag is a reading, and the page treated it as the
/// last word twice.**
///
/// It came from `ScanResult.runningNow`, read once when the review was built.
/// The person who quit the app themselves while reading found «Move to Trash»
/// dead for good — the only way out was Back → Review, which pays for a fresh
/// scan of every ticked app — and the person whose app came back up had it never
/// asked to quit at all, its bundle moved out from under a live process that
/// then writes its preferences back on exit.
///
/// So the question left the view model: the batch carries the person's answer to
/// «Force quit and remove anyway», and the engine asks who is up at the moment
/// it moves anything.
@MainActor
final class TheReviewIsNotTheLastWordTests: XCTestCase {

    private let tool = InstalledApp(name: "Vendor Player", bundleID: "com.vendor.player",
                                    path: "/Applications/Vendor Player.app", sizeBytes: 1_240_000)

    /// A review of one app that the scan saw running.
    private func reviewed(_ wire: UninstallerWire) async -> UninstallerViewModel {
        let model = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await model.loadAppsIfNeeded()
        model.setChecked(tool.bundleID, true)
        await model.prepareReview()
        return model
    }

    private func wire(runningAtScan: Bool,
                      removal: UninstallResult = UninstallResult(trashed: [], freedBytes: 0))
        -> UninstallerWire {
        UninstallerWire(
            apps: [tool],
            scans: [tool.bundleID: ScanResult(bundleID: tool.bundleID, appPath: tool.path,
                                              appSizeBytes: 0, leftovers: [],
                                              runningNow: runningAtScan)],
            removal: removal)
    }

    private func batch(_ wire: UninstallerWire) -> TrashBatchRequest? {
        guard let payload = wire.payload(of: .trashPaths) else { return nil }
        return try? JSONDecoder().decode(TrashBatchRequest.self, from: payload)
    }

    // MARK: - The question travels with the batch

    /// The permission the person gave, in the request that acts on it — rather
    /// than a `quit` sent from here, decided from the flag the scan left behind.
    func testThePersonsAnswerAboutQuittingTravelsWithTheBatch() async {
        for allowed in [true, false] {
            let wire = wire(runningAtScan: true,
                            removal: UninstallResult(trashed: [tool.path], freedBytes: 10))
            let model = await reviewed(wire)
            model.forceQuit = allowed

            await model.removeSelection()

            XCTAssertEqual(batch(wire)?.quitRunningApps, allowed,
                           "the engine was not told whether it may quit a running app, so it "
                           + "has to guess at the moment it moves the bundle (\(allowed))")
            XCTAssertFalse(wire.commands.contains(.quit), """
                the view model quit the app itself, from `group.running` — the reading the \
                scan took, which is stale in both directions by the time anybody presses \
                anything (\(allowed))
                """)
        }
    }

    /// Direction one, at the model: the person quit the app themselves, so the
    /// press must reach the engine rather than being refused here against a
    /// reading taken minutes ago.
    func testAPressReachesTheEngineEvenWhileTheReviewSaysSomethingIsRunning() async {
        let wire = wire(runningAtScan: true,
                        removal: UninstallResult(trashed: [tool.path], freedBytes: 10))
        let model = await reviewed(wire)
        XCTAssertTrue(model.groups.allSatisfy(\.running), "precondition: the review says running")
        XCTAssertFalse(model.forceQuit, "precondition: nobody allowed a force quit")

        await model.removeSelection()

        XCTAssertTrue(wire.commands.contains(.trashPaths), """
            the press did nothing at all: the app the person had already quit still reads as \
            running here, and the only way out is Back → Review and a fresh scan of every \
            ticked app
            """)
    }

    // MARK: - What a held batch says

    /// Direction two: the app came back up, the engine moved nothing and said
    /// which app it was. Nothing may claim a removal, and the review — with the
    /// fresh reading in it — is what the person needs to act.
    func testABatchHeldForARunningAppKeepsTheReviewAndSaysWhatToDo() async {
        let wire = wire(runningAtScan: false,
                        removal: UninstallResult(trashed: [], freedBytes: 0,
                                                 stillRunning: [tool.path]))
        let model = await reviewed(wire)
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
        XCTAssertFalse(model.replyLost, "the engine answered; it just answered no")
    }

    /// Leaving the review ends the round: the sentence about a batch held for a
    /// running app has nothing to say over the picker.
    func testGoingBackTakesTheReportWithIt() async {
        let wire = wire(runningAtScan: false,
                        removal: UninstallResult(trashed: [], freedBytes: 0,
                                                 stillRunning: [tool.path]))
        let model = await reviewed(wire)
        await model.removeSelection()
        XCTAssertNotNil(model.resultBanner, "precondition: the report is up")

        model.backToPick()

        XCTAssertNil(model.resultBanner,
                     "the picker's footer draws this, where it is about nothing")
    }

    // MARK: - And the button is not gated on the stale reading

    /// The behavioural test above passes with the button dimmed, because a
    /// disabled button never calls the model at all — which is the defect it is
    /// about. This reads the page's own source, the way
    /// `PageKeepsNoDurableStateTests` does.
    func testTheRemoveButtonIsNotDisabledByTheScansOwnReading() throws {
        let page = try String(
            contentsOf: RepoSource.root
                .appendingPathComponent("Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift"),
            encoding: .utf8)

        let gates = page.components(separatedBy: "\n")
            .filter { $0.contains(".disabled(") && $0.contains("ready") }

        XCTAssertEqual(gates, [], """
            «Move to Trash» is dimmed by `UninstallPlan.readiness`, which reads the \
            `running` flag the scan left behind — so an app the person quit while reading \
            the review leaves the button dead with no way out but a second scan
            """)
    }
}
