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
