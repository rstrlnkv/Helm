import Foundation
import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// «A `pmset` refusal that is not a success», on the IOKit side.
///
/// `IOPMAssertionCreateWithName` returns an `IOReturn` and
/// `IOKitSleepAssertions` used it for one thing — deciding whether to keep the
/// id — while `preventSleep(display:)` returned `Void`. So a refused assertion
/// left the engine setting `isActive`, writing «holding sleep» to the log and
/// lighting the menu bar for a Mac that goes to sleep on schedule. The clamshell
/// half of this module has read its answer since
/// `APmsetThatRefusedIsNotASuccessTests`; this half could not, because **the
/// port could not say it** — no fake could stand in a state the protocol has no
/// word for, so no test of it could exist whatever anybody wrote.
///
/// What is fixed here is that: the port answers, the engine reads the answer,
/// and the trail carries it. The screen still says «holding», and deliberately
/// so for now — saying otherwise is a new field on the payload and a sentence in
/// eight languages, which is `HelmUI`'s tree.
final class AnAssertionTheSystemRefusedSaysSoTests: XCTestCase {

    private var store: NamespacedStore!
    private var assertions: FakeAssertions!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        assertions = FakeAssertions()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        store = nil
        assertions = nil
        super.tearDown()
    }

    private func engine() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: FakeApps(),
                        pointer: FakePointer(), clamshell: FakeClamshell(),
                        clock: FakeClock())
    }

    /// IOKit said no. The one place that can account for a Mac that slept
    /// through a session has to name it.
    func testAnAssertionTheSystemRefusedReachesTheTrail() {
        assertions.succeeds = false

        engine().startSession(minutes: 0)

        XCTAssertEqual(assertions.preventCount, 1,
                       "precondition: the assertion was asked for at all — an absence proves "
                       + "nothing when the subject never happened")
        XCTAssertEqual(lines(containing: "could not").count, 1,
                       "macOS refused to hold the Mac awake and the module wrote «holding "
                       + "sleep» over it; the log is the only account of a Mac that slept "
                       + "through a session it was asked to sit out")
    }

    /// The control, so the line above cannot be satisfied by a module that
    /// complains about every session.
    func testAnOrdinarySessionComplainsAboutNothing() {
        engine().startSession(minutes: 0)

        XCTAssertTrue(assertions.held, "precondition: the assertion really was taken")
        XCTAssertEqual(lines(containing: "could not").count, 0)
        XCTAssertEqual(lines(containing: "holding sleep").count, 1,
                       "…and the ordinary line is still written")
    }

    private func lines(containing text: String) -> [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == KeepAwakeEngine.moduleID && $0.message.contains(text) }
            .map(\.message)
    }
}
