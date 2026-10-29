import XCTest
import HelmContract
import HelmTestSupport
@testable import Module_Layout_Engine
@testable import Module_Layout_UI

/// After `stop()` a press on the page, the hotkey, or a state the engine still
/// yields reaches nothing.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`,
/// on the person's switch and on quit. A page still on screen (or a task already
/// queued) may press a control after that: a stopped model reaches no work at all,
/// and a stream task left running keeps a subscriber on an engine stream nobody
/// reads. Defect class kept: a stopped model still talks to the engine, or still
/// listens to it.
///
/// Every absence below is paired with a control that proves the fake counts the
/// same call while the model lives, and `CountingWork` counts live stream
/// subscribers (the continuation's `onTermination` takes one off), so «the task
/// was cancelled» is read from the work and not assumed from the model.
@MainActor
final class AStoppedLayoutModelReachesNoWorkTests: XCTestCase {

    private final class CountingWork: LayoutWork, @unchecked Sendable {
        private let lock = NSLock()
        private var counts = (fix: 0, settingsChanged: 0, subscribers: 0)
        private var continuations: [UUID: AsyncStream<LayoutState>.Continuation] = [:]
        var fixes: Int { lock.withLock { counts.fix } }
        var rereads: Int { lock.withLock { counts.settingsChanged } }
        var subscribers: Int { lock.withLock { counts.subscribers } }

        func stream() -> AsyncStream<LayoutState> {
            AsyncStream { continuation in
                let id = UUID()
                lock.withLock { counts.subscribers += 1; continuations[id] = continuation }
                continuation.onTermination = { [weak self] _ in
                    self?.lock.withLock { self?.counts.subscribers -= 1; self?.continuations[id] = nil }
                }
            }
        }
        func fix() { lock.withLock { counts.fix += 1 } }
        func settingsChanged() { lock.withLock { counts.settingsChanged += 1 } }

        func yield(_ state: LayoutState) {
            let all = lock.withLock { Array(continuations.values) }
            for continuation in all { continuation.yield(state) }
        }
    }

    private static func state(enabled: Bool) -> LayoutState {
        LayoutState(enabled: enabled, automatic: true, suspended: false,
                    lastConversion: nil, lastConversionUndone: false)
    }

    func testAPressAfterStopReachesNoWork() async {
        let work = CountingWork()
        let lvm = LayoutViewModel(work: work)
        let descriptor = LayoutDescriptor()

        // Control: all three doors reach the work while the model lives.
        lvm.fix()
        lvm.settingsChanged()
        descriptor.hotkeyPressed(LayoutDescriptor.hotkeys[0], lvm)
        XCTAssertEqual(work.fixes, 2, "control: the page's fix and the hotkey reach the work before stop()")
        XCTAssertEqual(work.rereads, 1, "control: the re-read reaches the work before stop()")

        let (fixes, rereads) = (work.fixes, work.rereads)
        lvm.stop()
        lvm.fix()
        lvm.settingsChanged()
        descriptor.hotkeyPressed(LayoutDescriptor.hotkeys[0], lvm)
        await grace()
        XCTAssertEqual(work.fixes, fixes, "a fix was sent to the engine after stop()")
        XCTAssertEqual(work.rereads, rereads, "a re-read was sent to the engine after stop()")
    }

    func testAStoppedModelLetsGoOfTheStreamAndDrawsNothingNew() async {
        let work = CountingWork()
        let lvm = LayoutViewModel(work: work)
        XCTAssertEqual(work.subscribers, 1, "the model did not take the stream when it was built")

        // Control: a yielded state reaches the page while the model lives.
        XCTAssertFalse(lvm.state.enabled, "precondition: the model starts as not watching")
        work.yield(Self.state(enabled: true))
        await waitUntil("a yielded state reaches the model") { lvm.state.enabled }

        lvm.stop()
        await waitUntil("the stream is given back") { work.subscribers == 0 }
        let before = lvm.state
        work.yield(Self.state(enabled: false))
        await grace()
        XCTAssertEqual(lvm.state, before, "a stopped model went on drawing what the engine said")
        XCTAssertEqual(work.subscribers, 0, "a stopped model still holds its subscription")
    }
}
