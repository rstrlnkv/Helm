import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **The last-opened read's one worker, at the orders the first tests did not
/// try**: many reads arriving at once, a read made straight after one the
/// deadline cut while its lookup was merely slow, back-to-back reads while the
/// machine is busy, and a read that finished on time answered by the deadline
/// before the worker was given back.
final class TheLastOpenedReadBackToBackTests: XCTestCase {

    private func engine(_ apps: some AppLister) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: apps, fs: FakeFS(existing: [:]),
                          trash: FakeTrash(), running: FakeRunning(running: []),
                          extensions: NoSystemExtensions(),
                          store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                 backing: InMemoryKeyValueStore()))
    }

    private func list(_ n: Int) -> [InstalledApp] {
        (0..<n).map { InstalledApp(name: "App\($0)", bundleID: "com.x.\($0)",
                                   path: "/Applications/App\($0).app", sizeBytes: 0) }
    }

    private func dated(_ apps: [InstalledApp]) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0.path, Date(timeIntervalSince1970: 1_000)) })
    }

    /// Sixteen reads at once — the page appearing while Refresh is pressed, twice
    /// — and a Spotlight slow enough that they overlap: one worker, never two,
    /// and every reading accounts for every app.
    func testReadsArrivingTogetherShareOneWorker() async {
        let apps = list(3)
        let spotlight = CountingSpotlight(opened: dated(apps), delay: 0.02)
        let engine = engine(spotlight)
        let readings = await withTaskGroup(of: AppOpenedReading.self) { group in
            for _ in 0..<16 { group.addTask { await engine.lastOpened(apps, deadline: 2) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(readings.count, 16)
        XCTAssertTrue(readings.contains { $0.opened.count == 3 }, "precondition: one read really read")
        for reading in readings {
            XCTAssertEqual(reading.opened.count + reading.unread.count, 3)
        }
        XCTAssertEqual(spotlight.mostAtOnce, 1, "two lookups ran at once — a second worker was started")
    }

    /// **The deadline cuts a read whose lookups are slow, not hung**, and a read
    /// made straight after it is answered without a second worker; once the one
    /// lookup in flight returns, the worker is back and the next read reads.
    func testAReadStraightAfterADeadlineStartsNoSecondWorkerAndTheWorkerComesBack() async {
        let apps = list(5)
        let spotlight = CountingSpotlight(opened: dated(apps), delay: 0.08)
        let engine = engine(spotlight)
        let first = await engine.lastOpened(apps, deadline: 0.1)
        XCTAssertFalse(first.unread.isEmpty, "precondition: the deadline cut the first read")
        let straight = await engine.lastOpened(apps, deadline: 0.1)
        XCTAssertEqual(straight.opened.count + straight.unread.count, 5)
        XCTAssertEqual(spotlight.mostAtOnce, 1, "a read made straight after a cut one started a second worker")

        let limit = Date().addingTimeInterval(3)
        var again = await engine.lastOpened(apps, deadline: 2)
        while again.opened.count < 5, Date() < limit {
            try? await Task.sleep(nanoseconds: 50_000_000)
            again = await engine.lastOpened(apps, deadline: 2)
        }
        XCTAssertEqual(again.opened.count, 5, "the worker cut by the deadline was never given back")
        XCTAssertEqual(spotlight.mostAtOnce, 1)
    }

    /// Two reads one straight after the other while every core is busy: the
    /// scheduler is what decides whether the answer overtakes the release, so the
    /// order is tried where it is least polite. The burners outrank the worker
    /// (`.userInteractive` over its `.userInitiated`), which is what preempts it
    /// between the two calls; at default priority and a thousand rounds the
    /// answer-then-release order passed, while this shape read 55 blank of 20 000
    /// against it and 0 of 20 000 twice against release-then-answer, in under a
    /// second.
    func testASecondReadStraightAfterTheFirstReadsEveryAppUnderLoad() async {
        let apps = list(1)
        var fake = FakeApps()
        fake.opened = dated(apps)
        let engine = engine(fake)
        let stop = LoadSwitch()
        let burners = ProcessInfo.processInfo.activeProcessorCount * 3
        for _ in 0..<burners {
            let burner = Thread { var x = 0; while stop.isOn { x &+= 1 } }
            burner.qualityOfService = .userInteractive
            burner.start()
        }
        defer { stop.turnOff() }
        var blank = 0
        let rounds = 20_000
        for _ in 0..<rounds {
            let first = await engine.lastOpened(apps)
            XCTAssertEqual(first.opened.count, apps.count)
            let next = await engine.lastOpened(apps)
            if next.opened.count != apps.count { blank += 1 }
        }
        XCTAssertEqual(blank, 0, "\(blank) of \(rounds) reads made straight after another answered without reading")
    }

    /// **A read that finished in time, answered by the deadline.** When the last
    /// lookup returns just as the deadline fires, `cutShort` can answer the
    /// caller with every date while the worker has not yet been given back, and
    /// the caller's next read is answered «unread» for everything without asking.
    func testACompleteReadIsNeverFollowedByABlankOne() async {
        let apps = list(1)
        let engine = engine(CountingSpotlight(opened: dated(apps), delay: 0.03))
        var complete = 0, blankAfterComplete = 0
        for _ in 0..<150 {
            let first = await engine.lastOpened(apps, deadline: 0.03)
            guard first.opened.count == 1 else {
                // Cut while the lookup was in flight: wait it out so the next
                // round starts with the worker free.
                try? await Task.sleep(nanoseconds: 60_000_000)
                continue
            }
            complete += 1
            let next = await engine.lastOpened(apps, deadline: 1)
            if next.opened.count != 1 {
                blankAfterComplete += 1
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
        XCTAssertGreaterThan(complete, 0, "precondition: some reads finished before the deadline")
        XCTAssertEqual(blankAfterComplete, 0,
                       "\(blankAfterComplete) of \(complete) complete reads were followed by a read answered without reading")
    }
}

private final class LoadSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on = true
    var isOn: Bool { lock.withLock { on } }
    func turnOff() { lock.withLock { on = false } }
}

/// Spotlight that takes `delay` per call, counting the most calls in flight.
private final class CountingSpotlight: AppLister, @unchecked Sendable {
    private let lock = NSLock()
    private let opened: [String: Date]
    private let delay: TimeInterval
    private var inFlight = 0
    private var peak = 0
    init(opened: [String: Date], delay: TimeInterval) { self.opened = opened; self.delay = delay }
    var mostAtOnce: Int { lock.withLock { peak } }
    func installedBundleIDs() -> Set<String> { [] }
    func isKnownToSystem(bundleID: String) -> Bool { false }
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func lastOpened(path: String) -> Date? {
        lock.withLock { inFlight += 1; peak = max(peak, inFlight) }
        Thread.sleep(forTimeInterval: delay)
        lock.withLock { inFlight -= 1 }
        return opened[path]
    }
}
