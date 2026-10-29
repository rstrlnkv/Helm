import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Disk_UI

/// Disk's row button and its removal sentence are the kit's `HelmBasket` words:
/// the pair `basketAction` chooses between must be the kit's, not a copy that can
/// drift, and a basketed row must get the unmark half.
final class DiskSaysTheKitsWordsForARowTests: XCTestCase {

    func testDiskChoosesTheRightHalfInEveryLanguage() {
        AppLanguage.each { language in
            XCTAssertEqual(DkStr.basketAction(name: "a.bin", basketed: false, language: language),
                           HelmBasket.mark(name: "a.bin", language: language), "\(language)")
            XCTAssertEqual(DkStr.basketAction(name: "a.bin", basketed: true, language: language),
                           HelmBasket.unmark(name: "a.bin", language: language), "\(language)")
            XCTAssertEqual(DkStr.movedToTrash("3 MB"),
                           HelmBasket.movedToTrash("3 MB", language: language), "\(language)")
        }
    }
}
