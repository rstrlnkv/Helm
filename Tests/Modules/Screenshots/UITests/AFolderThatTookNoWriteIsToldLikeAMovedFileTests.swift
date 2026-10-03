import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The edit that could not be written beside its original is told with the one sentence `.missing` and `.changed` have, in
/// every language** (`ReplaceRefusal.folderRefused`, `ScStr.refusal`): the person is told that the edit is a separate file,
/// not why. The engine tells the three apart (`TheEditReplacesOnlyTheFileItWroteTests`); the screen does not, and this holds
/// the screen to it, so that a case added to the switch with a sentence of its own is a choice made here and not by a gap.
///
/// Total failure of the subject prints: a sentence that is empty or that is another refusal's, so that a folder that took no
/// write says «The save folder is missing».
@MainActor
final class AFolderThatTookNoWriteIsToldLikeAMovedFileTests: XCTestCase {

    func testTheFolderThatTookNoWriteIsToldAsAMovedOrChangedShotIsInEveryLanguage() {
        var told = 0
        AppLanguage.each { language in
            let moved = ScStr.refusal(.notReplaced(.missing))
            XCTAssertFalse(moved.isEmpty, "\(language): the control: the sentence is not empty")
            XCTAssertEqual(ScStr.refusal(.notReplaced(.folderRefused)), moved, "\(language)")
            XCTAssertEqual(ScStr.refusal(.notReplaced(.changed)), moved, "\(language)")
            // Not another refusal's: the folder's own, and the Trash's.
            for other in [CaptureRefusal.write(.noFolder), .write(.noPermission), .notEditable, .write(.diskFull)] {
                XCTAssertNotEqual(ScStr.refusal(.notReplaced(.folderRefused)), ScStr.refusal(other), "\(language): \(other)")
            }
            told += 1
        }
        XCTAssertEqual(told, AppLanguage.allCases.count, "the control: every language was asked")
    }
}
