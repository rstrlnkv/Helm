import XCTest
import HelmRuntime
@testable import Module_Layout_Engine

/// The real `AppActivation`: starting twice leaves one registration, `stopObserving()`
/// removes it, and dropping the object removes it too.
///
/// Defect class kept (ARCHITECTURE.md § State and lifetime): an observer token orphaned
/// by a second start. `FrontmostApp.shared` is process-wide; a first token the
/// port forgot is still registered, and every app change reaches the engine
/// twice, or reaches a module that is switched off. Driven by
/// `FrontmostApp.shared.setForTesting`, which tells watchers synchronously; the
/// `didBecomeActive` half is never posted here (it would reach any engine another
/// test left running) and no input source is touched.
@MainActor
final class TheActivationPortKeepsOneWatchTests: XCTestCase {

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        private var helm = 0
        var apps: [String] { lock.withLock { seen } }
        var helmActive: Int { lock.withLock { helm } }
        func app(_ id: String) { lock.withLock { seen.append(id) } }
        func becameActive() { lock.withLock { helm += 1 } }
    }

    override func setUp() {
        super.setUp()
        FrontmostApp.shared.setForTesting("")
    }
    override func tearDown() {
        FrontmostApp.shared.setForTesting("")
        super.tearDown()
    }

    private func start(_ port: AppActivation, _ calls: Calls) {
        port.startObserving(helmBecameActive: { calls.becameActive() },
                            frontmostChanged: { calls.app($0) })
    }

    func testStartingTwiceLeavesOneWatch() {
        let port = AppActivation()
        let calls = Calls()
        start(port, calls)
        start(port, calls)
        FrontmostApp.shared.setForTesting("com.example.One")
        XCTAssertEqual(calls.apps, ["com.example.One"],
                       "one change reached the handler \(calls.apps.count) times: the first start was orphaned")
        FrontmostApp.shared.setForTesting("com.example.Two")
        XCTAssertEqual(calls.apps, ["com.example.One", "com.example.Two"])
        XCTAssertEqual(calls.helmActive, 0, "Helm became active though nothing posted it")
        port.stopObserving()
    }

    func testStoppingRemovesTheWatchAndStoppingTwiceIsHarmless() {
        let port = AppActivation()
        let calls = Calls()
        start(port, calls)
        FrontmostApp.shared.setForTesting("com.example.One")
        XCTAssertEqual(calls.apps.count, 1, "control: the watch delivers while observing")
        port.stopObserving()
        port.stopObserving()
        FrontmostApp.shared.setForTesting("com.example.Two")
        XCTAssertEqual(calls.apps, ["com.example.One"], "a stopped port still delivered")
        // And it can be started again after a stop.
        start(port, calls)
        FrontmostApp.shared.setForTesting("com.example.Three")
        XCTAssertEqual(calls.apps, ["com.example.One", "com.example.Three"])
        port.stopObserving()
    }

    func testDroppingThePortRemovesTheWatch() {
        let calls = Calls()
        var port: AppActivation? = AppActivation()
        start(port!, calls)
        FrontmostApp.shared.setForTesting("com.example.One")
        XCTAssertEqual(calls.apps.count, 1, "control: the watch delivers while the port lives")
        port = nil
        FrontmostApp.shared.setForTesting("com.example.Two")
        XCTAssertEqual(calls.apps, ["com.example.One"], "a port that was let go still delivered")
    }
}
