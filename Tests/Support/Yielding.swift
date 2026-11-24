import Foundation
import XCTest

/// Waiting for something a task will do, without a fixed number of yields.
///
/// **Bounded, and it asserts.** A wait with no ceiling hangs the suite on a red
/// run instead of reporting; a wait that returns quietly when the condition
/// never held turns every assertion after it into a claim about a system that
/// never got there.
///
/// **One wait.** `waitUntilWithin` below is the loop; `waitUntil` and
/// `waitUntilReached` are the same call for a `@MainActor` case and for one
/// that is not.
public extension XCTestCase {

    /// Reads `condition` every few milliseconds until it holds or `within` of
    /// wall-clock time has passed, then fails naming what never happened.
    ///
    /// **A deadline and not a count of yields**: a yield loop ends when the loop
    /// does, which is however long a number of turns of the scheduler take, and
    /// a task on another thread reaching a lock is not scheduled by yielding on
    /// this one. A sleep between reads lets it run, and the clock decides when to
    /// stop.
    ///
    /// `@MainActor` because every caller is a `@MainActor` test reading state a
    /// view model owns: the reads have to come back to the same actor, or the
    /// condition is read from somewhere the value does not live.
    @MainActor
    func waitUntil(_ what: String, within limit: Duration = .seconds(5), file: StaticString = #filePath,
                   line: UInt = #line, _ condition: () -> Bool) async {
        await waitUntilWithin(what, limit, file: file, line: line, condition)
    }
}

/// `waitUntil(_:within:)` for a test case that is **not** `@MainActor`: the
/// method above takes the case's isolation with it, and calling it from a case
/// without one sends `self` across an isolation boundary. A free function with
/// no isolation of its own is called from either, so this is the wait for the
/// engine tests whose fakes are read from the test's own thread.
///
/// Same loop, same assertion naming what never happened.
public nonisolated(nonsending) func waitUntilReached(_ what: String, within limit: Duration = .seconds(2),
                             file: StaticString = #filePath, line: UInt = #line,
                             _ condition: () -> Bool) async {
    await waitUntilWithin(what, limit, file: file, line: line, condition)
}

/// The one loop. It takes the isolation of its caller, so the `@MainActor` method
/// and the free function above both read `condition` where they were called.
public nonisolated(nonsending) func waitUntilWithin(_ what: String, _ limit: Duration,
                                                    file: StaticString = #filePath, line: UInt = #line,
                                                    _ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now + limit
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertTrue(condition(), "never reached: \(what)", file: file, line: line)
}

/// A fair chance for a detached task to do the thing, before asserting that it
/// did **not**.
///
/// The other half of `waitUntil`, and the harder one: a test asserting an
/// absence passes when the subject never happened at all, so every caller pairs
/// this with a control that proves the same path still speaks.
///
/// A sleep and not a yield: what is waited for is a task on another thread
/// reaching a lock, which yielding on this one does not schedule.
///
/// A free function, because a method on `XCTestCase` would take the case's
/// isolation with it, and both `@MainActor` cases and others call this.
public func grace(_ seconds: TimeInterval = 0.15) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
