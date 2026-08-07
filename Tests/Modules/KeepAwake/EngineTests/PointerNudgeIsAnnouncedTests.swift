import Foundation
import HelmRuntime
import XCTest
@testable import Module_KeepAwake_Engine

/// The nudge tells the rest of the app it was Helm, and nothing held it.
///
/// Moving the pointer resets the system idle counter — measured in the engine's
/// own comment at 284,97 s to 0,30 s — and this module's default interval is
/// five minutes, which is exactly `ScanSchedule.idleThreshold`. So anything
/// deciding "has the person left" from that counter alone finds the Mac
/// permanently busy, and **no background scan ever runs** for anybody with this
/// switch on. `ScanCoordinator` subtracts what it hears on
/// `.helmPointerNudged`; `KeepAwakeEngine.doJiggle` is the only thing that
/// posts it.
///
/// Three parts in three targets — the name in `HelmRuntime`, the post here, the
/// listener in `HelmApp` — and no test touched any of them. The failure is
/// silent in the worst way: Keep Awake goes on working perfectly, and a
/// different module quietly stops.
final class PointerNudgeIsAnnouncedTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var pointer: FakePointer!
    private var clock: FakeClock!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        pointer = FakePointer()
        // A pointer somewhere on a screen, so `JiggleTarget` has a move to make.
        pointer.loc = CGPoint(x: 100, y: 100)
        pointer.bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        clock = FakeClock()
        store.set(true, for: "jiggleEnabled")
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(),
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: FakePower(), apps: FakeApps(),
                                 pointer: pointer, clamshell: FakeClamshell(), clock: clock)
    }

    /// Fires the jiggle timer once, at the interval the settings ask for.
    private func jiggleOnce() {
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: a session is holding sleep")
        clock.fire(after: TimeInterval(settings.jiggleIntervalMinutes * 60))
    }

    func testAJiggleAnnouncesItself() {
        var heard = 0
        let token = NotificationCenter.default.addObserver(
            forName: .helmPointerNudged, object: nil, queue: nil) { _ in heard += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        jiggleOnce()

        XCTAssertEqual(pointer.moved.count, 1, "precondition: the pointer was actually moved")
        XCTAssertEqual(heard, 1,
                       "the pointer moved and nothing was told — every background scan in "
                       + "the app now sees a Mac that is never idle")
    }

    /// The other direction, and the reason the first assertion is not enough on
    /// its own: a post that fired whether or not the pointer moved would make
    /// `ScanCoordinator` discount idleness that Helm never disturbed.
    func testNothingIsAnnouncedWhenThereIsNoMoveToMake() {
        pointer.bounds = nil          // no screen contains the pointer
        var heard = 0
        let token = NotificationCenter.default.addObserver(
            forName: .helmPointerNudged, object: nil, queue: nil) { _ in heard += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        jiggleOnce()

        XCTAssertTrue(pointer.moved.isEmpty, "precondition: there was no move to make")
        XCTAssertEqual(heard, 0, "a nudge was announced that never happened")
    }

    /// And it is not announced when the feature is off, which is its default.
    func testAJiggleThatIsSwitchedOffAnnouncesNothing() {
        store.set(false, for: "jiggleEnabled")
        var heard = 0
        let token = NotificationCenter.default.addObserver(
            forName: .helmPointerNudged, object: nil, queue: nil) { _ in heard += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        jiggleOnce()

        XCTAssertTrue(pointer.moved.isEmpty)
        XCTAssertEqual(heard, 0)
    }
}
