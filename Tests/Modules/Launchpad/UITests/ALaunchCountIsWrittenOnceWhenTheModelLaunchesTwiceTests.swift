import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Stands for the system's opening of an app, held until a test lets it go, so a second press arrives while the first is out.
private final class HeldLauncher: AppLauncherPort, @unchecked Sendable {
    private let log = Locked(0)
    private let gate = Locked<CheckedContinuation<Void, Never>?>(nil)
    var calls: Int { log.value }
    let entered = Locked<(@Sendable () -> Void)?>(nil)
    func open(_ url: URL) async -> Bool {
        // Only the first call is held: a second one, which should never come, answers at once so a failure is red, not a hang.
        guard log.withLock({ $0 += 1; return $0 }) == 1 else { return true }
        await withCheckedContinuation { c in
            gate.withLock { $0 = c }
            let hook = entered.withLock { h -> (@Sendable () -> Void)? in defer { h = nil }; return h }
            hook?()
        }
        return true
    }
    func release() { gate.withLock { $0?.resume(); $0 = nil } }
}

/// The model counts nothing itself: a launch it lets through is counted by the engine once, and a second press while one is out
/// reaches neither the system nor the counts.
@MainActor final class ALaunchCountIsWrittenOnceWhenTheModelLaunchesTwiceTests: XCTestCase {
    func testTwoPressesWhileOneIsOutWriteOne() async throws {
        let dir = scratchDirectory("counts-model")
        let launcher = HeldLauncher()
        let engine = LaunchpadEngine(catalog: RigCatalog(["a"]), launcher: launcher, store: LayoutStore(directory: dir))
        let model = LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()))
        let reached = expectation(description: "the system was asked")
        launcher.entered.withLock { $0 = { reached.fulfill() } }
        let first = Task { await model.launch("a", name: "A") }
        await fulfillment(of: [reached], timeout: 10)
        let second = await model.launch("a", name: "A")
        XCTAssertFalse(second, "the second press is refused while the first is out")
        launcher.release()
        let opened = await first.value
        XCTAssertTrue(opened)
        XCTAssertEqual(launcher.calls, 1)
        XCTAssertEqual(LaunchCountStore(directory: dir).load().counts, ["a": 1])
    }
}
