import XCTest
@testable import Module_Uninstaller_Engine

/// A fresh account has no Trash until something is deleted: that is an empty one,
/// and the log must not carry a warning for it. Any other failed read is a refusal
/// the log names and the caller sees as `nil`.
final class TheMissingTrashIsNotAWarningTests: XCTestCase {
    func testNoTrashIsEmptyAndSilent() {
        let outcome = WorkspaceAppLister.trashReadFailure(code: NSFileReadNoSuchFileError)
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.apps?.count, 0)
    }

    func testARefusedReadIsLoggedAndNil() {
        let outcome = WorkspaceAppLister.trashReadFailure(code: NSFileReadNoPermissionError)
        XCTAssertEqual(outcome.warning, "the Trash could not be read: \(NSFileReadNoPermissionError)")
        XCTAssertNil(outcome.apps)
    }
}
