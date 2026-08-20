import Foundation
import XCTest
@testable import Module_Homebrew_Engine

/// **The one launch in this app that still goes through the door that aborts.**
///
/// `HelmProcess` exists because `NSTask` *raises* on some launch paths, and an
/// Objective-C exception has nothing to land on in a Swift frame — it goes past
/// `catch` into `std::terminate`. A shipped build died with SIGABRT inside
/// `-[NSConcreteTask launchWithDictionary:error:]`, which is why `HelmLaunch`
/// is the package's only Objective-C target and why `HelmProcess.launched`
/// starts every child through `HelmLaunchTask`.
///
/// `ShellProcessRunner.run` and `.runData` were moved onto `HelmProcess` and are
/// covered by that door. `ShellProcessRunner.stream` was not
/// (`SystemPorts.swift:169`): it builds its own `Process` and starts it with
///
///     do { try p.run() } catch { … }
///
/// — the exact line `HelmProcess.launched`'s own doc comment describes as unable
/// to guard this class of refusal, "however carefully it was written". It is the
/// last bare one left in `Sources/` apart from `HelmApp/Installer.swift`.
///
/// What goes through `stream` is every operation that changes the machine:
/// `brew install`, `uninstall`, `upgrade`, `upgrade all`, and the `/bin/bash`
/// that downloads and runs the Homebrew installer.
///
/// **The NUL below is the lever, not the claim.** `HelmLaunch.h` records what
/// was measured: a NUL in an argument or in an environment value raises, while a
/// missing file, a bad working directory, `EMFILE`, `EAGAIN` and `E2BIG` all
/// come back as an `NSError` a Swift `catch` already handles — and the crash in
/// the field came from a third path nobody has enumerated, which is why the fix
/// there had to be «catch whatever it raises» rather than «forbid what we know
/// raises». A NUL is simply the one input that reaches the raise from a test.
/// It is not an unreachable one either: a package name is a word parsed out of
/// `brew`'s own stdout, and `String(decoding:as: UTF8.self)` keeps a NUL byte
/// intact where it folds genuinely invalid bytes to U+FFFD.
///
/// **This test cannot show the abort, and that is worth writing down** — the
/// same note `AStartedToolCannotKillTheAppTests` carries for the query side.
/// XCTest installs its own Objective-C exception handler around each test
/// method, so inside the harness a raise is reported as an ordinary failure.
/// The app has no such handler; there the same raise is `abort()`.
final class AStreamedLaunchCannotKillTheAppTests: XCTestCase {

    /// The exit code a stream reported, and a way to wait for it: the real
    /// runner delivers `onExit` from the pipe's readability handler, not from
    /// the calling thread.
    private final class ExitBox: @unchecked Sendable {
        private let landed = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _code: Int32?
        func set(_ code: Int32) {
            lock.lock(); _code = code; lock.unlock()
            landed.signal()
        }
        /// nil when no exit ever arrived, which is a page whose spinner runs
        /// for the life of the app.
        func code(within seconds: TimeInterval) -> Int32? {
            guard landed.wait(timeout: .now() + seconds) == .success else { return nil }
            lock.lock(); defer { lock.unlock() }; return _code
        }
    }

    /// Called on the test's own thread on purpose: an Objective-C raise from a
    /// background queue has nothing above it and takes the whole bundle, while
    /// one on this thread reaches XCTest's handler and is reported.
    private func streamed(_ path: String, _ args: [String]) -> ExitBox {
        let box = ExitBox()
        _ = ShellProcessRunner().stream(path, args, env: [:],
                                        onLine: { _ in },
                                        onExit: { box.set($0) })
        return box
    }

    /// A NUL in an argument is one of the two paths measured to raise. Reached
    /// here as `/bin/echo`, but in the app it is `brew install -- <name>` with a
    /// name that came back from `brew search`.
    func testANulInAnArgumentIsARefusalRatherThanAnAbort() {
        let box = streamed("/bin/echo", ["a\u{0000}b"])
        XCTAssertEqual(box.code(within: 5), -1, """
            the streamed launch did not come back as a failed spawn. If this \
            line was reached at all the process survived, which is the whole \
            point — outside XCTest's exception handler this raise is the SIGABRT \
            the 0.10.0-dev.12 crash report shows.
            """)
    }

    /// The other measured one. `stream` merges its caller's environment into
    /// the process environment, so a value arriving from anywhere reaches the
    /// same raise.
    func testANulInAnEnvironmentValueIsARefusalRatherThanAnAbort() {
        let box = ExitBox()
        _ = ShellProcessRunner().stream("/bin/echo", ["helm"],
                                        env: ["HELM_TEST": "v\u{0000}w"],
                                        onLine: { _ in },
                                        onExit: { box.set($0) })
        XCTAssertEqual(box.code(within: 5), -1,
                       "a NUL in an environment value raised out of the streamed launch")
    }

    /// The control that keeps the guard honest in the other direction: the
    /// refusals that arrive as an `NSError` already reach `onExit(-1)` today, so
    /// a fix must not be "report -1 for everything" — and a page waiting on an
    /// exit that never comes is the failure this path already handles.
    func testAMissingToolIsStillAFailedSpawnWithAnExit() {
        let box = streamed("/definitely/not/here", [])
        XCTAssertEqual(box.code(within: 5), -1,
                       "a tool that could not start left the operation with no exit at all")
    }

    /// And the precondition every assertion above rests on: a tool that *can*
    /// start still starts and still reports its own exit. Without this the
    /// three tests hold on a runner that refuses everything.
    func testAToolThatCanStartStillReportsItsOwnExit() {
        let box = streamed("/bin/sh", ["-c", "exit 3"])
        XCTAssertEqual(box.code(within: 15), 3)
    }
}
