import XCTest
import IOKit.pwr_mgt
@testable import Module_KeepAwake_Engine

/// An IOKit power assertion outlives the object that took it unless something
/// gives it back, and nothing here did.
///
/// `deactivate()` releases them, and that covered the module being switched off
/// in Settings. It did not cover the engine being dropped any other way — and
/// an assertion nobody released is held until the process exits, which for this
/// module means a Mac that will not sleep and a settings page that says Keep
/// Awake is off. The same shape as `CGKeyTap` having no `deinit`, one framework
/// over.
///
/// Asserted against the power manager's own books, not against a flag on the
/// object: the object is gone by the time the question is worth asking, and a
/// flag would only report what the code believes.
final class AssertionsDieWithTheirOwnerTests: XCTestCase {

    /// How many assertions this process is holding, as `pmset -g assertions`
    /// would show them.
    private func heldByThisProcess() -> Int {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let table = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return -1 }
        return table[NSNumber(value: getpid())]?.count ?? 0
    }

    func testAssertionsAreGivenBackWhenTheirOwnerIsDropped() {
        let before = heldByThisProcess()
        XCTAssertGreaterThanOrEqual(before, 0, "the power manager would not answer")

        var taken = 0
        do {
            let assertions = IOKitSleepAssertions()
            assertions.preventSleep(display: true)
            taken = heldByThisProcess()
            // Asserted first, so a test of the release cannot pass by nothing
            // ever having been taken — the absence-passes-vacuously trap.
            XCTAssertGreaterThan(taken, before,
                                 "no assertion was taken, so there is nothing to release")
            // Dropped without `release()`, which is every path that is not
            // `deactivate()`.
        }

        XCTAssertEqual(heldByThisProcess(), before,
                       "\(taken - before) power assertion(s) survived their owner — "
                       + "the Mac will not sleep again until Helm quits")
    }
}
