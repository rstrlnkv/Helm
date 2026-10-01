import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// What the engine remembers and what it reads from Spotlight: the order
/// survives an engine, a value nobody should trust reads as the standard one,
/// and the last-opened read is bounded, drops a date from the future, and says
/// which apps it did not reach instead of calling them unrecorded.
final class TheSortOrderAndTheDatesTests: XCTestCase {

    private let list = (0..<5).map {
        InstalledApp(name: "App\($0)", bundleID: "com.x.\($0)", path: "/Applications/App\($0).app", sizeBytes: 0)
    }

    private func engine(_ apps: FakeApps = FakeApps(),
                        backing: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> UninstallerEngine {
        UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"), apps: apps, fs: FakeFS(existing: [:]),
                          trash: FakeTrash(), running: FakeRunning(running: []),
                          store: NamespacedStore(namespace: UninstallerEngine.moduleID, backing: backing))
    }

    func testTheDefaultIsName() {
        XCTAssertEqual(engine().sortOrder, .name)
    }

    /// Written under the engine's own id, and read back by a new engine over the
    /// same store — which is what "remembered" has to mean.
    func testAChoiceSurvivesAnEngine() {
        let backing = InMemoryKeyValueStore()
        engine(backing: backing).setSortOrder(.size)
        XCTAssertEqual(backing.object(forKey: "module.\(UninstallerEngine.moduleID).sortOrder") as? String, "size")
        XCTAssertEqual(engine(backing: backing).sortOrder, .size)
    }

    func testAValueOutOfRangeReadsAsNameWhateverItsType() {
        let key = "module.\(UninstallerEngine.moduleID).sortOrder"
        for planted: Any in ["bogus", "", 7, 1.5, true, ["size"], Data([1, 2])] {
            let backing = InMemoryKeyValueStore()
            backing.set(planted, forKey: key)
            XCTAssertEqual(engine(backing: backing).sortOrder, .name, "\(planted)")
        }
    }

    func testTheDatesComeBackPerPathAndNoRecordIsAbsent() async {
        let t = Date(timeIntervalSinceNow: -86_400)
        let reading = await engine(FakeApps(opened: [list[1].path: t])).lastOpened(list)
        XCTAssertEqual(reading.opened, [list[1].path: t])
        XCTAssertTrue(reading.unread.isEmpty)
    }

    /// A date later than now is not evidence of an opening.
    func testADateFromTheFutureIsDropped() async {
        let now = Date()
        let apps = FakeApps(opened: [list[0].path: now.addingTimeInterval(3_600),
                                     list[1].path: now.addingTimeInterval(-3_600)])
        let reading = await engine(apps).lastOpened(list, now: now)
        XCTAssertEqual(Set(reading.opened.keys), [list[1].path])
    }

    /// The ceiling: what it did not look up is reported as unread, not as "no
    /// record". Asserts the subject happened first (something was read).
    func testTheCeilingLeavesTheRestUnreadNotUnrecorded() async {
        let apps = FakeApps(opened: Dictionary(uniqueKeysWithValues: list.map { ($0.path, Date(timeIntervalSince1970: 5)) }))
        let reading = await engine(apps).lastOpened(list, ceiling: 2)
        XCTAssertEqual(reading.opened.count, 2)
        XCTAssertEqual(reading.unread, list.dropFirst(2).map(\.path))
    }

    /// A Spotlight that is slow: the deadline stops the read between lookups.
    func testTheDeadlineStopsASlowRead() async {
        var apps = FakeApps(opened: Dictionary(uniqueKeysWithValues: list.map { ($0.path, Date(timeIntervalSince1970: 5)) }))
        apps.lookupDelay = 0.2
        let reading = await engine(apps).lastOpened(list, deadline: 0.3)
        XCTAssertFalse(reading.opened.isEmpty, "the read never started")
        XCTAssertFalse(reading.unread.isEmpty, "the deadline did not stop the read")
        XCTAssertEqual(reading.opened.count + reading.unread.count, list.count)
    }
}
