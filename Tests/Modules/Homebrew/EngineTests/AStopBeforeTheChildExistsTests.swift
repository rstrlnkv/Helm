import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **Stop is a press against a handle that does not exist yet.**
///
///     public func stop() {
///         lock.lock()
///         guard busy, let handle = current else { lock.unlock(); return }
///
/// `current` is set by `adopt`, which runs *after* the child has been launched.
/// Everything before that point is a window in which the page is showing a
/// running operation with a live Stop button — `emitState(.running)` is the
/// first thing `installBrew` does — and the press falls through the `guard`
/// into a bare `return`: no state, no console line, no log, and `stopRequested`
/// left `false`, so nothing later can tell that the person asked.
///
/// For a package operation the window is a spawn and is measured in
/// milliseconds. For `installBrew` it is **the administrator password dialog**,
/// which is as long as a person takes to find their password — and while it is
/// up, `runAdmin` is blocking the engine's thread with `current` still nil.
/// Pressing Stop there does nothing, says nothing, and is then followed by the
/// module downloading and running the Homebrew installer anyway.
///
/// It is the same family as `AVanishedBrewIsNotASilentPressTests` (a press that
/// does nothing, visibly forever) and the same family CLAUDE.md names as «a
/// flag written before the check it guards» — here the flag is not written at
/// all, because the check in front of it fails.
///
/// **The fake privileged runner has to be *in the middle of* asking.** Every
/// existing `PrivilegedRunner` fake in this suite returns its answer inline, so
/// "the dialog is on screen and the person has not answered yet" is a state no
/// test could write down — which is why this window has never been tested.
/// `DialogOnScreen` below stops inside `runAdmin` until the test says the
/// person answered, which is what the real one does.
/// The child's handle: it records the SIGTERM and does **not** end the stream,
/// which is what the real one does — the child dies, then EOF, then `onExit`.
private final class Handle: RunningProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var _terminated = false
    var terminated: Bool { lock.lock(); defer { lock.unlock() }; return _terminated }
    func terminate() { lock.lock(); _terminated = true; lock.unlock() }
}

final class AStopBeforeTheChildExistsTests: XCTestCase {

    // MARK: - Fakes

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }

    /// The admin dialog as it really behaves: it appears, and then it waits for
    /// a human. `waitUntilOnScreen()` returns once the engine is inside it;
    /// `answer()` is the person pressing a button.
    private final class DialogOnScreen: PrivilegedRunner, @unchecked Sendable {
        private let appeared = DispatchSemaphore(value: 0)
        private let answered = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _scripts: [String] = []
        private let reply: Bool

        /// `holds: false` is the dialog somebody answers instantly — the shape
        /// every other fake in this suite has, kept for the control below. The
        /// permit is granted by a `signal` rather than by an initial value:
        /// libdispatch traps when a semaphore is deallocated below the value it
        /// was born with.
        init(reply: Bool, holds: Bool = true) {
            self.reply = reply
            if !holds { answered.signal() }
        }

        var scripts: [String] { lock.lock(); defer { lock.unlock() }; return _scripts }

        func runAdmin(_ script: String) -> Bool {
            lock.lock(); _scripts.append(script); lock.unlock()
            appeared.signal()
            answered.wait()
            return reply
        }

        func waitUntilOnScreen(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(appeared.wait(timeout: .now() + 5), .success,
                           "the administrator dialog was never asked for",
                           file: file, line: line)
        }
        func answer() { answered.signal() }
    }

    /// A child that keeps running, and a handle that records the SIGTERM
    /// without ending the stream — the real one does not finish on `terminate`
    /// either: the child dies, *then* EOF, *then* `onExit`.
    ///
    /// `InstallBrewTests`' runner returns `NoProcess()` for every stream, which
    /// makes "the installer was terminated" unrepresentable; a fake simpler
    /// than the port cannot fail the way the port can.
    private final class HangingRunner: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _launched: [(launch: String, args: [String])] = []
        private var _handles: [Handle] = []
        private var _exits: [@Sendable (Int32) -> Void] = []

        var launched: [(launch: String, args: [String])] {
            lock.lock(); defer { lock.unlock() }; return _launched
        }
        var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            let handle = Handle()
            lock.lock()
            _launched.append((launchPath, args))
            _handles.append(handle)
            _exits.append(onExit)
            lock.unlock()
            return handle
        }

        func exitAll(code: Int32) {
            lock.lock(); let exits = _exits; _exits = []; lock.unlock()
            for exit in exits { exit(code) }
        }
    }

    // MARK: - Plumbing

    /// The last `opState` the transport holds, read through its replay — a
    /// sentinel emitted before subscribing marks where the replay ends, so the
    /// read is deterministic.
    private func lastOpState(_ transport: LocalTransport) async -> OpState? {
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var last: OpState?
        for await event in transport.events {
            if event.name == "test.sentinel" { break }
            if event.name == HomebrewEvent.opState.rawValue {
                last = try? JSONDecoder().decode(OpState.self, from: event.payload)
            }
        }
        return last
    }

    /// Starts `installBrew` on a thread of its own — it blocks inside the
    /// dialog, exactly as the engine's own queue does — and hands back a way to
    /// wait for it to return.
    private func startInstallBrew(_ engine: HomebrewEngine) -> DispatchSemaphore {
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            engine.installBrew()
            returned.signal()
        }
        return returned
    }

    // MARK: - The window

    func testAStopPressedAtTheDialogDoesNotThenRunTheInstaller() {
        let privileged = DialogOnScreen(reply: true)
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: LocalTransport(),
                                    marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        XCTAssertEqual(privileged.scripts.count, 1,
                       "precondition: the operation is running and the dialog is up")

        engine.stop()          // the person presses Stop while the dialog is up
        privileged.answer()    // …and then types their password

        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")
        XCTAssertTrue(runner.launched.isEmpty, """
            Stop was pressed and the module then downloaded and ran the Homebrew \
            installer anyway: \(runner.launched.map(\.launch))
            """)
    }

    func testAStopPressedAtTheDialogEndsTheOperation() async {
        let privileged = DialogOnScreen(reply: true)
        let runner = HangingRunner()
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: transport, marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        engine.stop()
        privileged.answer()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")

        let state = await lastOpState(transport)
        XCTAssertNotEqual(state?.phase, .running, """
            the page is still showing a running operation with a Stop button \
            that has already been pressed and did nothing
            """)
        XCTAssertEqual(state?.reason, .stopped,
                       "the end the person asked for is not named as one")
    }

    // MARK: - Controls

    /// Once the child exists the press does reach it — so the failures above
    /// are about the window before `adopt`, not about `stop` in general. This
    /// also exercises the capability `InstallBrewTests`' `NoProcess()` runner
    /// cannot: the Homebrew installer itself being terminated.
    func testOnceTheInstallerIsRunningStopReachesIt() {
        let privileged = DialogOnScreen(reply: true, holds: false)
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: LocalTransport(),
                                    marker: InMemoryOpMarker())

        engine.installBrew()
        XCTAssertEqual(runner.handles.count, 1, "precondition: the installer is streaming")

        engine.stop()
        XCTAssertTrue(runner.handles[0].terminated,
                      "Stop did not reach the running Homebrew installer")
    }

    /// And a dialog nobody stopped still installs: the guard being asked for
    /// must not become "installBrew never runs the installer".
    func testAnUnstoppedDialogStillRunsTheInstaller() {
        let privileged = DialogOnScreen(reply: true)
        let runner = HangingRunner()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: privileged, user: "tester",
                                    transport: LocalTransport(),
                                    marker: InMemoryOpMarker())

        let returned = startInstallBrew(engine)
        privileged.waitUntilOnScreen()
        privileged.answer()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success,
                       "installBrew never returned")

        XCTAssertEqual(runner.launched.count, 1,
                       "nobody pressed Stop and the installer did not run")
        XCTAssertEqual(runner.launched.first?.launch, "/bin/bash")
    }
}
