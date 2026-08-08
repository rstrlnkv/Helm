import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// Asking an app to quit and moving its bundle are two steps, and the second
/// must not start until the first has happened.
///
/// `quit` only asks. The view model then trashed the bundle after a flat
/// `Task.sleep(800ms)` — a number standing where an answer was available, since
/// the engine holds the port that can be asked. Too short is the expensive
/// direction: macOS lets a running app's bundle be moved, the process carries
/// on from where it went, and it writes its preferences when it finally exits —
/// so the leftovers the uninstall had just taken come back, which is the whole
/// of what this module promises.
///
/// **The fake could not have shown it.** `FakeRunning.running` was a `let`, so
/// quitting changed nothing the port reported and "the app is gone now" was
/// unrepresentable — no test could have driven a wait for it, whatever anybody
/// wrote. It is a `var` that a quit empties now, with a set of apps that ignore
/// the request so the deadline has a subject.
final class TheQuitIsWaitedForTests: XCTestCase {

    private func engine(running: [String], stubborn: [String] = [],
                        quitAfter: TimeInterval = 0) -> (UninstallerEngine, FakeRunning) {
        let apps = FakeRunning(running: running, stubborn: stubborn, quitAfter: quitAfter)
        let engine = UninstallerEngine(
            home: URL(fileURLWithPath: NSTemporaryDirectory()),
            apps: FakeApps(), fs: FakeFS(existing: [:]),
            trash: FakeTrash(), running: apps)
        return (engine, apps)
    }

    func testItReturnsOnlyOnceTheAppHasGone() async {
        // The app takes a moment to go, or the wait would have nothing to wait
        // for and this would pass with `waitUntilGone` deleted.
        let (engine, apps) = engine(running: ["com.acme.editor"], quitAfter: 0.15)

        engine.quit(bundleID: "com.acme.editor", force: true)
        await engine.waitUntilGone(bundleID: "com.acme.editor")

        XCTAssertFalse(apps.isRunning(bundleID: "com.acme.editor"),
                       "the wait came back while the app was still running, and the next "
                       + "thing the caller does is move its bundle")
        XCTAssertEqual(apps.quits.count, 1, "precondition: the quit was asked for once")
    }

    /// An app that ignores the request must not hold the removal for ever: the
    /// person asked for this, and `trashSync` reports what would not move.
    func testAnAppThatWillNotQuitStopsAtTheDeadline() async {
        let (engine, apps) = engine(running: ["com.acme.stubborn"],
                                    stubborn: ["com.acme.stubborn"])

        engine.quit(bundleID: "com.acme.stubborn", force: true)
        let started = Date()
        await engine.waitUntilGone(bundleID: "com.acme.stubborn", deadline: 0.2, poll: 0.02)
        let waited = Date().timeIntervalSince(started)

        XCTAssertTrue(apps.isRunning(bundleID: "com.acme.stubborn"),
                      "precondition: this app ignores the request, so the deadline is "
                      + "what ended the wait")
        XCTAssertGreaterThanOrEqual(waited, 0.2, "it gave up before the deadline")
        XCTAssertLessThan(waited, 3, "it waited far past the deadline")
    }

    /// An app that was never running is not something to wait for at all.
    func testItDoesNotWaitForAnAppThatIsAlreadyGone() async {
        let (engine, _) = engine(running: [])

        let started = Date()
        await engine.waitUntilGone(bundleID: "com.acme.never", deadline: 5, poll: 0.05)

        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5,
                          "it waited out a deadline for an app that was not there")
    }
}
