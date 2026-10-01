import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// The engine's last-opened read at the inputs its first tests did not feed in:
/// more apps than its ceiling, one lookup that hangs past the whole deadline,
/// an empty list, and the edges of "later than now".
final class TheLastOpenedReadUnderOddInputsTests: XCTestCase {

    private func engine(_ apps: some AppLister) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: apps, fs: FakeFS(existing: [:]),
                          trash: FakeTrash(), running: FakeRunning(running: []),
                          store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                 backing: InMemoryKeyValueStore()))
    }

    private func list(_ n: Int) -> [InstalledApp] {
        (0..<n).map { InstalledApp(name: "App\($0)", bundleID: "com.x.\($0)",
                                   path: "/Applications/App\($0).app", sizeBytes: 0) }
    }

    /// More apps than the ceiling, at the real ceiling: everything past it is
    /// `unread` and not "no record", and nothing is in both.
    func testOneAppPastTheRealCeilingIsUnreadAndNotUnrecorded() async {
        let apps = list(UninstallerEngine.lastOpenedCeiling + 1)
        var fake = FakeApps()
        fake.opened = Dictionary(uniqueKeysWithValues: apps.map { ($0.path, Date(timeIntervalSince1970: 1_000)) })
        let reading = await engine(fake).lastOpened(apps)
        XCTAssertEqual(reading.opened.count, UninstallerEngine.lastOpenedCeiling)
        XCTAssertEqual(reading.unread, [apps.last!.path])
        XCTAssertTrue(Set(reading.opened.keys).isDisjoint(with: reading.unread))
    }

    /// **The deadline is a promise about the read, not about when the next
    /// lookup may start.** One Spotlight call that hangs — the doc on the
    /// ceiling names exactly that Mac, «Spotlight is busy reindexing and one
    /// call takes far longer» — holds the whole read, and the dates behind it,
    /// for as long as that call takes.
    func testOneLookupThatHangsDoesNotHoldTheReadPastItsDeadline() async {
        var fake = FakeApps()
        fake.opened = Dictionary(uniqueKeysWithValues: list(5).map { ($0.path, Date(timeIntervalSince1970: 1_000)) })
        fake.lookupDelay = 2
        let deadline: TimeInterval = 0.2
        let started = Date()
        let reading = await engine(fake).lastOpened(list(5), deadline: deadline)
        let took = Date().timeIntervalSince(started)
        XCTAssertEqual(reading.opened.count + reading.unread.count, 5, "precondition: every app is accounted for")
        XCTAssertFalse(reading.unread.isEmpty, "precondition: the deadline cut the read")
        XCTAssertLessThan(took, deadline + 0.5,
                          "a read with a \(deadline) s deadline took \(String(format: "%.2f", took)) s — one lookup outlived the deadline")
    }

    /// **Refresh pressed while one lookup hangs starts no second worker, and the
    /// worker is given back once the hung call returns.** The first read is cut
    /// at its deadline with the worker still stuck in Spotlight; two more reads
    /// come while it is stuck and must not start lookups of their own (a thread
    /// per press, each parked on the same busy index); once the call returns,
    /// the next read reads again — a worker never given back would answer
    /// «unread» for every app for the rest of the session.
    func testARepeatedReadWhileOneLookupHangsStartsNoSecondWorkerAndTheWorkerComesBack() async {
        let apps = list(3)
        let spotlight = HangingSpotlight(opened: Dictionary(uniqueKeysWithValues: apps.map {
            ($0.path, Date(timeIntervalSince1970: 1_000)) }), firstCallHangs: 1.0)
        let engine = engine(spotlight)
        let first = await engine.lastOpened(apps, deadline: 0.1)
        XCTAssertEqual(first.unread, apps.map(\.path), "precondition: the first lookup hung past the deadline")
        let second = await engine.lastOpened(apps, deadline: 0.1)
        let third = await engine.lastOpened(apps, deadline: 0.1)
        XCTAssertEqual(second.unread.count + second.opened.count, 3)
        XCTAssertEqual(third.unread.count + third.opened.count, 3)
        XCTAssertEqual(spotlight.mostAtOnce, 1, "two lookups ran at once — a read started a second worker behind a stuck one")
        XCTAssertEqual(spotlight.calls, 1, "a read made while the worker was stuck asked Spotlight itself")

        // The hung call returns; the worker stops at the flag and is released.
        let limit = Date().addingTimeInterval(3)
        var again = await engine.lastOpened(apps, deadline: 1)
        while again.opened.count < 3, Date() < limit {
            try? await Task.sleep(nanoseconds: 50_000_000)
            again = await engine.lastOpened(apps, deadline: 1)
        }
        XCTAssertEqual(again.opened.count, 3, "after the hung call returned, a read still read nothing — the worker was never given back")
        XCTAssertEqual(spotlight.mostAtOnce, 1)
    }

    /// Two reads one straight after the other, nothing hanging: the second
    /// reads every app. The first answers its caller from inside the worker and
    /// gives the worker back only after that, so a caller quick enough to ask
    /// again lands between the two and is answered «unread» for everything.
    func testASecondReadStraightAfterTheFirstReadsEveryApp() async {
        let apps = list(2)
        var fake = FakeApps()
        fake.opened = Dictionary(uniqueKeysWithValues: apps.map { ($0.path, Date(timeIntervalSince1970: 1_000)) })
        let engine = engine(fake)
        var blank = 0
        let rounds = 2_000
        for _ in 0..<rounds {
            _ = await engine.lastOpened(apps)
            let next = await engine.lastOpened(apps)
            if next.opened.count != apps.count { blank += 1 }
        }
        XCTAssertEqual(blank, 0, "\(blank) of \(rounds) reads made straight after another answered without reading")
    }

    /// Nothing listed: nothing asked, nothing unread — and the menu reads that
    /// as "no dates", so the date order is dim rather than a name order in
    /// disguise.
    func testAnEmptyListIsAnEmptyReading() async {
        let reading = await engine(FakeApps()).lastOpened([])
        XCTAssertEqual(reading, AppOpenedReading(opened: [:], unread: []))
        XCTAssertFalse(AppSort.dateOrderAvailable(reading.opened))
    }

    /// The edge of "later than now": a date equal to now is kept, one a second
    /// after it is dropped, and a very old one is kept as the date it is.
    func testTheFutureEdgeIsNowItself() async {
        let now = Date()
        let apps = list(3)
        var fake = FakeApps()
        fake.opened = [apps[0].path: now, apps[1].path: now.addingTimeInterval(1),
                       apps[2].path: Date(timeIntervalSince1970: 0)]
        let reading = await engine(fake).lastOpened(apps, now: now)
        XCTAssertEqual(Set(reading.opened.keys), [apps[0].path, apps[2].path])
    }
}

/// Spotlight with one call that hangs: the first lookup takes `firstCallHangs`
/// seconds and every later one answers at once. Counts the calls and the most
/// that were ever in flight together.
private final class HangingSpotlight: AppLister, @unchecked Sendable {
    private let lock = NSLock()
    private let opened: [String: Date]
    private let hang: TimeInterval
    private var started = 0
    private var inFlight = 0
    private var peak = 0
    init(opened: [String: Date], firstCallHangs hang: TimeInterval) { self.opened = opened; self.hang = hang }
    var calls: Int { lock.withLock { started } }
    var mostAtOnce: Int { lock.withLock { peak } }
    func installedBundleIDs() -> Set<String> { [] }
    func isKnownToSystem(bundleID: String) -> Bool { false }
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func lastOpened(path: String) -> Date? {
        let first: Bool = lock.withLock {
            started += 1
            inFlight += 1
            peak = max(peak, inFlight)
            return started == 1
        }
        if first { Thread.sleep(forTimeInterval: hang) }
        lock.withLock { inFlight -= 1 }
        return opened[path]
    }
}
