import Foundation
import XCTest
@testable import Module_Homebrew_Engine

/// **A streamed launch that `NSTask` refuses by raising is a failed spawn, not
/// an abort.**
///
/// `NSTask` *raises* on some launch paths, and an Objective-C exception goes
/// past a Swift `catch` into `std::terminate`. `HelmProcess.launched` starts
/// every child through `HelmLaunchTask`, the package's only Objective-C target,
/// so a raise is caught there. `ShellProcessRunner.stream` carries every
/// operation that changes the machine: `brew install`, `uninstall`, `upgrade`,
/// `upgrade all`, and the `/bin/bash` that runs the Homebrew installer.
///
/// **The NUL is the lever, not the claim.** `HelmLaunch.h` records what raises:
/// a NUL in an argument or an environment value. Other refusals come back as an
/// `NSError`, and the guard is «catch whatever it raises», not «forbid what is
/// known to raise». A NUL is reachable: a package name is parsed out of `brew`'s
/// stdout, and `String(decoding:as: UTF8.self)` keeps a NUL byte intact.
///
/// **This test cannot show the abort.** XCTest wraps each test method in its
/// own Objective-C exception handler, so a raise is reported as an ordinary
/// failure; the app has no such handler, and there the raise is `abort()`.
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

    /// The control in the other direction: refusals that arrive as an `NSError`
    /// reach `onExit(-1)`, so the guard is not "report -1 for everything".
    func testAMissingToolIsStillAFailedSpawnWithAnExit() {
        let box = streamed("/definitely/not/here", [])
        XCTAssertEqual(box.code(within: 5), -1,
                       "a tool that could not start left the operation with no exit at all")
    }

    /// The precondition every assertion above rests on: a tool that *can*
    /// start still starts and reports its own exit.
    func testAToolThatCanStartStillReportsItsOwnExit() {
        let box = streamed("/bin/sh", ["-c", "exit 3"])
        XCTAssertEqual(box.code(within: 15), 3)
    }
}
