// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmLaunch
@testable import HelmRuntime

/// **`NSTask` raises, and a Swift `catch` cannot catch a raise.**
///
/// `HelmProcess.runData` guarded its launch with `do { try process.run() }
/// catch { return (-1, Data()) }` — which reads like a guard and is not one for
/// this class of refusal: an Objective-C exception has nothing to land on in a
/// Swift frame, so the runtime reaches `std::terminate` and the process aborts.
/// A shipped build died that way with SIGABRT inside
/// `-[NSConcreteTask launchWithDictionary:error:]`.
///
/// **What these tests cannot show is the abort, and that is worth writing
/// down.** Put the Swift `catch` back and they fail — measured, both NUL cases
/// — but they fail as ordinary failures rather than taking the bundle with
/// them: XCTest installs its own Objective-C exception handler around every
/// test case, so inside this harness the raise is caught by the harness. The
/// app has no such handler. The evidence that the raise really is `abort()`
/// outside a test is a standalone binary — `libc++abi: terminating due to
/// uncaught exception of type NSException` — and the crash report the fix was
/// written from.
///
/// So what is guarded here is the part a test can guard: that a raise arrives
/// as a refusal with a status every caller already reads, and that nothing of
/// what was passed in comes back with it.
final class AStartedToolCannotKillTheAppTests: XCTestCase {

    /// The two inputs measured to raise on macOS 27. Neither is something Helm
    /// means to send; the point is that the third one — whatever it was, the
    /// crash report names an offset and not a cause — is caught the same way.
    func testANulInAnArgumentIsARefusalRatherThanAnAbort() {
        let result = HelmProcess.run("/bin/echo", ["a\u{0000}b"])
        XCTAssertEqual(result.status, -1, """
            a launch that raised did not come back as a failed spawn. If this \
            line was reached at all the app survived, which is the whole point; \
            the status is what every caller reads.
            """)
        XCTAssertTrue(result.output.isEmpty, "a tool that never started produced output")
    }

    func testANulInAnEnvironmentValueIsARefusalRatherThanAnAbort() {
        let result = HelmProcess.run("/bin/echo", ["x"], env: ["HELM_TEST": "v\u{0000}w"])
        XCTAssertEqual(result.status, -1)
    }

    /// And the ordinary refusals still arrive as refusals — a shim that turned
    /// every failure into the same answer would hide the difference between «the
    /// tool is missing» and «the tool was given something impossible», which is
    /// what the log line distinguishes.
    func testAMissingToolIsStillAFailedSpawn() {
        XCTAssertEqual(HelmProcess.run("/definitely/not/here", []).status, -1)
    }

    /// The precondition every assertion above rests on: a tool that *can* start
    /// still does. Without this the three tests hold on a `HelmProcess` that
    /// refuses everything.
    func testAToolThatCanStartStillRuns() {
        let result = HelmProcess.run("/bin/echo", ["helm"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "helm")
    }

    // MARK: - The shim itself

    /// Read at the seam rather than only through `HelmProcess`, because this is
    /// the part that has to be true: the raise becomes an error, and the error
    /// says which exception it was so the log can name it.
    func testTheShimAnswersWithTheExceptionsName() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/echo")
        task.arguments = ["a\u{0000}b"]
        task.standardOutput = FileHandle.nullDevice

        var failure: NSError?
        XCTAssertFalse(HelmLaunchTask(task, &failure), "the task started with a NUL in an argument")
        let error = try? XCTUnwrap(failure)
        XCTAssertEqual(error?.domain, HelmLaunchErrorDomain, """
            a raise was reported in somebody else's domain, so a caller cannot \
            tell «the launch threw» from «the launch failed»
            """)
        XCTAssertNotNil(error?.userInfo[HelmLaunchExceptionNameKey],
                        "the error carries no exception name, so the log has nothing to say")
    }

    /// **And it carries the name only.** A reason string holds whatever `NSTask`
    /// was given — an argument, an environment value, a path — and this app's
    /// log carries no names.
    func testTheShimKeepsNothingOfWhatWasPassedIn() {
        let secret = "zzsecretzz"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/echo")
        task.arguments = ["\(secret)\u{0000}tail"]
        task.standardOutput = FileHandle.nullDevice

        var failure: NSError?
        XCTAssertFalse(HelmLaunchTask(task, &failure))
        let described = "\(failure?.userInfo as Any) \(failure?.localizedDescription ?? "")"
        XCTAssertFalse(described.contains(secret), """
            the error carries the argument it was refused for, so anything that \
            logs it writes down what Helm was asked to run: \(described)
            """)
    }
}
