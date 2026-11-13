import Foundation
import XCTest

/// Waiting for something a task will do, without a fixed number of yields.
///
/// **Bounded, and it asserts.** A wait with no ceiling hangs the suite on a red
/// run instead of reporting; a wait that returns quietly when the condition
/// never held turns every assertion after it into a claim about a system that
/// never got there.
public extension XCTestCase {

    /// Yields until `condition` holds, then fails naming what never happened.
    ///
    /// `@MainActor` because every caller is a `@MainActor` test reading state a
    /// view model owns: the yields have to come back to the same actor, or the
    /// condition is read from somewhere the value does not live.
    @MainActor
    func waitUntil(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) async {
        for _ in 0..<20_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "never reached: \(what)", file: file, line: line)
    }

    /// Reads `condition` every few milliseconds until it holds or `within` of
    /// wall-clock time has passed, then fails naming what never happened.
    ///
    /// **A deadline and not a count of yields**: the yield loop above ends when
    /// the loop does, which is however long twenty thousand turns of the
    /// scheduler take, and a task on another thread reaching a lock is not
    /// scheduled by yielding on this one. A sleep between reads lets it run, and
    /// the clock decides when to stop. Same isolation as above, for the same
    /// reason.
    @MainActor
    func waitUntil(_ what: String, within limit: Duration, file: StaticString = #filePath,
                   line: UInt = #line, _ condition: () -> Bool) async {
        await waitUntilWithin(what, limit, file: file, line: line, condition)
    }
}

/// `waitUntil(_:within:)` for the helpers that are free functions and have no
/// test case to call it on. The method above is this, so there is one wait.
@MainActor
public func waitUntilWithin(_ what: String, _ limit: Duration, file: StaticString = #filePath,
                            line: UInt = #line, _ condition: () -> Bool) async {
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
/// The other half of `waitUntil`, and the harder half to get right: a test
/// asserting an absence passes when the subject never happened at all, so every
/// caller pairs this with a control that proves the same path still speaks.
/// Written a third time — Keep Awake's battery veto, Autopilot's sweep and the
/// scan coordinator each carry the same two lines — before it moved here.
///
/// A sleep and not a yield: what is waited for is a task on another thread
/// reaching a lock, which yielding on this one does not schedule.
///
/// A free function rather than a method on `XCTestCase`, and that is not
/// tidiness: a method would take the test case's isolation with it, so a
/// `@MainActor` case could not call the same helper as one that is not — which
/// is exactly the pair that needs it.
public func grace(_ seconds: TimeInterval = 0.15) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
