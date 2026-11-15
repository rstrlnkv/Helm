import Foundation
import HelmRuntime
import XCTest

/// The log, switched on for one test and put back after it.
///
/// Written by hand in 45 test files as `setEnabled(true)` and `clearTail()` in
/// `setUp` with the reverse in `tearDown`, or the same three lines behind a
/// `defer` inside the test. The teardown block runs before any `tearDown()` of
/// the class, so a test that still has one sees the same order as before.
public extension XCTestCase {

    /// Enables the log, empties its tail, and registers the clearing and the
    /// disabling for the end of the test. Call it where the old code enabled
    /// the log: a line written before it is not in the tail.
    func tailTheLog() {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
        addTeardownBlock {
            HelmLog.shared.clearTail()
            HelmLog.shared.setEnabled(false)
        }
    }

    /// The messages the tail holds for one category, oldest first.
    func loggedLines(_ category: String) -> [String] {
        HelmLog.shared.recentEntries().filter { $0.category == category }.map(\.message)
    }
}
