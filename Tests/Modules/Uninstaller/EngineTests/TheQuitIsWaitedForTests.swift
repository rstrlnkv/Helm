import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// Asking an app to quit and moving its bundle are two steps, and the second
/// must not start until the first has happened.
///
/// `quit` only asks. macOS moves a running app's bundle, and the process
/// writes its preferences back on exit, so the removed leftovers return.
/// `FakeRunning` empties on a quit, and some of its apps ignore the request so
/// the deadline has a subject.
final class TheQuitIsWaitedForTests: XCTestCase {

    private func engine(running: [String], stubborn: [String] = [],
                        quitAfter: TimeInterval = 0) -> (UninstallerEngine, FakeRunning) {
        let apps = FakeRunning(running: running, stubborn: stubborn, quitAfter: quitAfter)
        let engine = UninstallerEngine(
            home: scratchDirectory("quit"),
            apps: FakeApps(), fs: FakeFS(existing: [:]),
            trash: FakeTrash(), running: apps)
        return (engine, apps)
    }

    func testItReturnsOnlyOnceTheAppHasGone() async {
        // The app takes a moment to go, or this would pass with the wait deleted.
        let (engine, apps) = engine(running: ["com.acme.editor"], quitAfter: 0.15)

        engine.quit(bundleID: "com.acme.editor", force: true)
        await engine.waitUntilGone(bundleID: "com.acme.editor")

        XCTAssertFalse(apps.isRunning(bundleID: "com.acme.editor"),
                       "the wait came back while the app was still running, and the next "
                       + "thing the caller does is move its bundle")
        XCTAssertEqual(apps.quits.count, 1, "precondition: the quit was asked for once")
    }

    /// An app that ignores the request must not hold the removal for ever: the
    /// person asked for this, so the deadline ends the wait, and a batch still
    /// holding the live app moves nothing and names it in `stillRunning`.
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
