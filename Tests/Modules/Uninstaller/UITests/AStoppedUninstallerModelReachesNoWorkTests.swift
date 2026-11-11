import Foundation
import HelmRuntime
import HelmUI
import HelmContract
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// After `stop()` a press on the page reaches no work, no list still in flight
/// is shown, and a Trash arrival reaches nobody.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`.
/// A page still on screen (or a task already queued) may press a control after
/// that; a scan, a removal or a background walk sent to a deactivated engine is
/// work nobody asked the module to do any more. Each press below is counted at
/// the fake, and the count before `stop()` is the control that proves the fake
/// would have counted it.
@MainActor
final class AStoppedUninstallerModelReachesNoWorkTests: XCTestCase {

    private let app = InstalledApp(name: "Sample", bundleID: "com.example.sample",
                                   path: "/Applications/Sample.app", sizeBytes: 0)

    private func settle() async { for _ in 0..<100 { await Task.yield() } }

    private func model(_ work: StoppedWork,
                       arrivals: AsyncStream<Void> = AsyncStream { _ in }) -> UninstallerViewModel {
        UninstallerViewModel(work: work, trashArrivals: arrivals)
    }

    /// Every entry point of the model that can reach the work.
    private func pressEverything(_ model: UninstallerViewModel) async -> (orphans: [OrphanGroup]?,
                                                                         trash: UninstallResult?,
                                                                         leftovers: [TrashedAppLeftovers]?,
                                                                         report: ScanReport?) {
        await model.loadAppsIfNeeded()
        await model.reloadApps()
        let orphans = await model.scanOrphans()
        let trash = await model.trashPaths(["/Applications/Sample.app"], quittingRunningApps: false)
        await model.setWatchingTrash(true)
        let leftovers = await model.trashedAppLeftovers()
        await model.dismissTrashedApp(bundleID: app.bundleID)
        let report = await model.backgroundScan()
        return (orphans, trash, leftovers, report)
    }

    /// The descriptor's pass-on, which the model's own `backgroundScan` does not
    /// prove: a descriptor without the override falls to the protocol default,
    /// which answers nil, and the coordinator then logs «no answer» every tick.
    func testTheDescriptorPassesTheScanOn() async {
        let work = StoppedWork(apps: [app])
        let parts = ModuleParts(engine: NoEngine(), model: model(work))
        let report = await UninstallerDescriptor().backgroundScan(parts)
        XCTAssertNotNil(report, "the descriptor fell to the default: «no answer» every tick")
        XCTAssertEqual(work.count("backgroundScan"), 1)
    }

    private final class NoEngine: ModuleEngine { func activate() {}; func deactivate() {} }

    func testAPressAfterStopReachesNoWork() async {
        let work = StoppedWork(apps: [app])
        let live = model(work)
        let first = await pressEverything(live)
        for call in ["listApps", "scanOrphans", "trashPaths", "setWatchingTrash",
                     "trashedAppLeftovers", "dismissTrashedApp", "backgroundScan"] {
            XCTAssertGreaterThan(work.count(call), 0, "control: \(call) reaches the work before stop()")
        }
        XCTAssertNotNil(first.orphans, "control: a live model answers scanOrphans")
        XCTAssertNotNil(first.trash, "control: a live model answers trashPaths")
        XCTAssertNotNil(first.leftovers, "control: a live model answers trashedAppLeftovers")
        XCTAssertNotNil(first.report, "control: a live model answers backgroundScan")
        XCTAssertFalse(live.closed)

        live.stop()
        XCTAssertTrue(live.closed)
        let before = work.calls
        let after = await pressEverything(live)
        await settle()

        XCTAssertNil(after.trash, "a removal was answered by a stopped model")
        XCTAssertNil(after.orphans)
        XCTAssertNil(after.leftovers)
        XCTAssertNil(after.report)
        XCTAssertEqual(work.calls, before, "a call reached the work after stop()")
    }

    /// A list that was in flight when the module was switched off does not land
    /// on the page afterwards.
    func testAnAnswerAfterStopIsNotShown() async {
        let work = StoppedWork(apps: [app], parkingTheList: true)
        let live = model(work)
        let load = Task { await live.reloadApps() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        XCTAssertEqual(work.parkedCount, 1, "precondition: the list is really in flight")

        live.stop()
        work.releaseParked()
        await load.value
        await settle()

        XCTAssertTrue(live.apps.isEmpty, "an answer landed on a stopped model")
        XCTAssertFalse(live.listAnswered)
    }

    /// One consumer of the arrival stream: before `stop()` an arrival reaches the
    /// host's handler, after it nobody.
    func testAnArrivalAfterStopReachesNobody() async {
        let (arrivals, feed) = AsyncStream.makeStream(of: Void.self)
        let live = model(StoppedWork(apps: []), arrivals: arrivals)
        let heard = Counter()
        live.listenForTrash { heard.n += 1 }

        feed.yield()
        for _ in 0..<1000 where heard.n < 1 { await Task.yield() }
        XCTAssertEqual(heard.n, 1, "control: an arrival reaches the handler before stop()")

        live.stop()
        feed.yield()
        feed.yield()
        await settle()
        XCTAssertEqual(heard.n, 1, "an arrival reached the handler after stop()")
    }

    /// With the offer window open the arrival is the offer's: it takes the new
    /// Trash and the host's handler (which would open a second window) is not
    /// called. The offer is built over the model, whose work is the fake, so there
    /// is no real I/O; its refresh is `refresh()` (internal).
    func testAnArrivalWithTheOfferOpenGoesToTheOffer() async {
        let (arrivals, feed) = AsyncStream.makeStream(of: Void.self)
        let work = StoppedWork(apps: [])
        let live = model(work, arrivals: arrivals)
        let heard = Counter()
        live.listenForTrash { heard.n += 1 }

        let offer = TrashedLeftoversModel(uvm: live)
        await offer.load()
        XCTAssertTrue(offer.groups.isEmpty, "precondition: the offer starts empty")
        live.openOffer = offer

        work.trashed = [TrashedAppLeftovers(bundleID: app.bundleID, name: app.name,
                                            appPath: "/Users/x/.Trash/Sample.app", leftovers: [])]
        let asked = work.count("trashedAppLeftovers")
        feed.yield()
        for _ in 0..<1000 where offer.groups.isEmpty { await Task.yield() }

        XCTAssertEqual(offer.groups.map(\.bundleID), [app.bundleID], "the offer did not take the arrival")
        XCTAssertGreaterThan(work.count("trashedAppLeftovers"), asked, "the offer did not ask the work again")
        XCTAssertEqual(heard.n, 0, "the host handler was called with the offer open")

        // Control: with no offer the same arrival goes to the handler.
        live.openOffer = nil
        feed.yield()
        for _ in 0..<1000 where heard.n < 1 { await Task.yield() }
        XCTAssertEqual(heard.n, 1, "control: without an offer the arrival reaches the handler")
    }

    /// Dropping the module's parts drops the model: the arrival consumer and the
    /// work hold nothing that holds it once `stop()` has run.
    func testAStoppedModelIsReleasedWithItsParts() async {
        weak var released: UninstallerViewModel?
        let (arrivals, _) = AsyncStream.makeStream(of: Void.self)
        do {
            let live = model(StoppedWork(apps: [app]), arrivals: arrivals)
            live.listenForTrash { }
            await live.reloadApps()
            XCTAssertEqual(live.apps.count, 1, "precondition: the model holds a list")
            released = live
            live.stop()
        }
        await settle()
        XCTAssertNil(released, "a stopped model is still held after its owner let go")
    }
}

@MainActor private final class Counter { var n = 0 }

/// The work, counting every call; answers are real values, never empty, so a
/// model that shows or returns them is told apart from one that does not.
private final class StoppedWork: UninstallerWork, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var order: AppSortOrder = .standard
    private let apps: [InstalledApp]
    private let parking: Bool
    private var trashedAnswer: [TrashedAppLeftovers] = []

    init(apps: [InstalledApp], parkingTheList: Bool = false) {
        self.apps = apps
        self.parking = parkingTheList
    }

    var calls: [String] { lock.withLock { log } }
    func count(_ name: String) -> Int { calls.filter { $0 == name }.count }
    var parkedCount: Int { lock.withLock { parked.count } }
    var trashed: [TrashedAppLeftovers] {
        get { lock.withLock { trashedAnswer } }
        set { lock.withLock { trashedAnswer = newValue } }
    }
    func releaseParked() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { parked = [] }
            return parked
        }
        all.forEach { $0.resume() }
    }
    private func note(_ name: String) { lock.withLock { log.append(name) } }

    func listApps() async -> [InstalledApp] {
        note("listApps")
        if parking { await withCheckedContinuation { c in lock.withLock { parked.append(c) } } }
        return apps
    }
    func appSizes(_ list: [InstalledApp]) async -> [String: Int] {
        note("appSizes"); return Dictionary(uniqueKeysWithValues: list.map { ($0.path, 1_000) })
    }
    func lastOpened(_ list: [InstalledApp], deadline: TimeInterval, ceiling: Int,
                    now: Date) async -> AppOpenedReading {
        note("lastOpened"); return AppOpenedReading(opened: [:])
    }
    var sortOrder: AppSortOrder { lock.withLock { order } }
    func setSortOrder(_ order: AppSortOrder) { note("setSortOrder"); lock.withLock { self.order = order } }
    func scan(bundleID: String, appPath: String, appName: String) async -> ScanResult {
        note("scan")
        return ScanResult(bundleID: bundleID, appPath: appPath, appSizeBytes: 1, leftovers: [], runningNow: false)
    }
    func scanOrphans() async -> [OrphanGroup] {
        note("scanOrphans"); return [OrphanGroup(bundleID: "com.example.gone", leftovers: [])]
    }
    func trashPaths(_ paths: [String], quittingRunningApps: Bool) async -> UninstallResult {
        note("trashPaths")
        return UninstallResult(trashed: paths, freedBytes: 7, failures: [])
    }
    var trashWatch: TrashWatch { .off }
    func setWatchingTrash(_ on: Bool) { note("setWatchingTrash") }
    func trashedAppLeftovers() async -> [TrashedAppLeftovers] {
        note("trashedAppLeftovers"); return trashed
    }
    func dismissTrashedApp(bundleID: String) { note("dismissTrashedApp") }
    func backgroundScan() async -> ScanReport? {
        note("backgroundScan"); return ScanReport(bytes: 1, count: 1, items: [])
    }
}
