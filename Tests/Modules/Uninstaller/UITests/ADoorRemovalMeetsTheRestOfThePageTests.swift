import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **A removal through the door meets the page's own work: a list read in flight, and a batch from the review.**
///
/// The door marks the apps list stale (`loadedApps = false`) so the page reads it again when it next
/// appears. A read that was already out when the removal ended answers afterwards, with the list as it
/// was before, and `reloadApps` takes that for the current one and says «loaded»: the removed app stays
/// on the page and nothing reads again. The review's batch (`removeSelection`) and the door share one
/// `busy` in both directions.
@MainActor
final class ADoorRemovalMeetsTheRestOfThePageTests: XCTestCase {

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 0)
    private var candidate: AppRemovalCandidate {
        AppRemovalCandidate(bundleID: tool.bundleID, path: tool.path, name: tool.name)
    }

    func testAListReadStartedBeforeTheRemovalDoesNotMarkTheListCurrentAfterIt() async {
        let work = ParkedWork(apps: [tool], parksTheFirstRead: true)
        let model = modelOver(work)

        let reading = Task { await model.reloadApps() }
        await waitUntil("the first list read is out") { work.listReads == 1 }

        let door = Task { await model.remove(candidate, quittingIfRunning: false) }
        await waitUntil("the door reached the work") { work.doorRequests == 1 }
        work.releaseDoor()
        let report = await door.value
        XCTAssertEqual(report.outcome, .moved, "precondition: the app went while the read was out")
        work.installed = []
        work.releaseListRead()
        await reading.value

        await model.loadAppsIfNeeded()
        XCTAssertEqual(model.apps, [], "the page still lists an app that is in the Trash")
    }

    private func reviewed(_ work: ParkedWork) async -> UninstallerViewModel {
        let model = modelOver(work)
        await model.loadAppsIfNeeded()
        model.setChecked(tool, true)
        await model.prepareReview()
        XCTAssertEqual(model.groups.count, 1, "precondition: a review of the app is open")
        return model
    }

    func testTheDoorIsBusyWhileTheReviewsBatchRuns() async {
        let work = ParkedWork(apps: [tool])
        let model = await reviewed(work)

        let batch = Task { await model.removeSelection() }
        await waitUntil("the batch reached the work") { work.trashRequests == 1 }
        // A task, so that with the guard gone the door hangs in the held fake and the test says so.
        let answered = Locked<AppRemovalReport?>(nil)
        let door = Task { answered.value = await model.remove(candidate, quittingIfRunning: true) }
        await waitUntil("the door answers or reaches the work") {
            answered.value != nil || work.doorRequests > 0
        }

        XCTAssertEqual(answered.value?.outcome, .busy, "the door ran beside the page's batch")
        XCTAssertEqual(work.doorRequests, 0, "and reached the work")
        work.releaseBatch(); work.releaseDoor()
        await batch.value; await door.value
    }

    func testTheReviewsBatchIsRefusedWhileTheDoorRuns() async {
        let work = ParkedWork(apps: [tool])
        let model = await reviewed(work)

        let door = Task { await model.remove(candidate, quittingIfRunning: false) }
        await waitUntil("the door reached the work") { work.doorRequests == 1 }
        let answered = Locked(false)
        let batch = Task { await model.removeSelection(); answered.value = true }
        await waitUntil("the batch answers or reaches the work") { answered.value || work.trashRequests > 0 }

        XCTAssertEqual(work.trashRequests, 0, "the page's batch ran beside the door")
        work.releaseBatch(); work.releaseDoor()
        await batch.value; _ = await door.value
    }

    func testAStopWhileTheDoorRunsStillGivesTheFlagBackAndTheReportBack() async {
        let work = ParkedWork(apps: [tool])
        let model = modelOver(work)
        let door = Task { await model.remove(candidate, quittingIfRunning: false) }
        await waitUntil("the door reached the work") { work.doorRequests == 1 }

        model.stop()
        work.releaseDoor()
        let report = await door.value

        XCTAssertEqual(report.outcome, .moved, "a removal already handed to the engine is reported as it ended")
        XCTAssertFalse(model.busy, "the flag was not given back")
        let after = await model.remove(candidate, quittingIfRunning: false)
        XCTAssertEqual(after.outcome, .stopped)
    }
}

/// A work whose first list read, the page's removal batch and the door's removal each wait until released.
private final class ParkedWork: UninstallerWork, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0, trashes = 0, doors = 0
    private var listing: [InstalledApp]
    private let listGate = AsyncStream<Void>.makeStream()
    private let batchGate = AsyncStream<Void>.makeStream()
    private let doorGate = AsyncStream<Void>.makeStream()

    private let parksFirst: Bool

    init(apps: [InstalledApp], parksTheFirstRead: Bool = false) { listing = apps; parksFirst = parksTheFirstRead }

    var installed: [InstalledApp] {
        get { lock.withLock { listing } }
        set { lock.withLock { listing = newValue } }
    }
    var listReads: Int { lock.withLock { reads } }
    var trashRequests: Int { lock.withLock { trashes } }
    var doorRequests: Int { lock.withLock { doors } }
    func releaseListRead() { listGate.continuation.finish() }
    func releaseBatch() { batchGate.continuation.finish() }
    func releaseDoor() { doorGate.continuation.finish() }

    func listApps() async -> [InstalledApp] {
        let (first, snapshot) = lock.withLock { () -> (Bool, [InstalledApp]) in
            reads += 1; return (reads == 1 && parksFirst, listing)
        }
        // The first read is answered with the list as it was when it started.
        if first { for await _ in listGate.stream {} }
        return first ? snapshot : installed
    }
    func appSizes(_ list: [InstalledApp]) async -> [String: Int] { [:] }
    func lastOpened(_ list: [InstalledApp], deadline: TimeInterval, ceiling: Int,
                    now: Date) async -> AppOpenedReading { AppOpenedReading(opened: [:]) }
    var sortOrder: AppSortOrder { .standard }
    func setSortOrder(_ order: AppSortOrder) {}
    func scan(bundleID: String, appName: String) async -> ScanResult {
        ScanResult(leftovers: [], runningNow: false)
    }
    func scanOrphans() async -> [OrphanGroup] { [] }
    func trashPaths(_ paths: [String], quittingRunningApps: Bool) async -> UninstallResult {
        lock.withLock { trashes += 1 }
        for await _ in batchGate.stream {}
        return UninstallResult(trashed: paths, freedBytes: 1)
    }
    func removalVerdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict] {
        candidates.map { _ in .removable }
    }
    func removalPreview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk { .refused(.notOffered) }
    func removeApp(_ candidate: AppRemovalCandidate, quittingIfRunning: Bool) async -> AppRemovalReport {
        lock.withLock { doors += 1 }
        for await _ in doorGate.stream {}
        return AppRemovalReport(.moved, freedBytes: 1)
    }
    var trashWatch: TrashWatch { .off }
    func setWatchingTrash(_ on: Bool) {}
    func trashedAppLeftovers() async -> [TrashedAppLeftovers] { [] }
    func dismissTrashedApp(bundleID: String) {}
    func backgroundScan() async -> ScanReport? { nil }
}
