import Foundation
import XCTest

/// Waiting for something a task will do, without a fixed number of yields.
///
/// Hand-written a third time before it moved here — `AFailedOperationRefreshesTheListsTests`
/// and `TheStopButtonReachesTheChildTests` each carry the same six lines, and
/// the third copy is the line this house draws.
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
