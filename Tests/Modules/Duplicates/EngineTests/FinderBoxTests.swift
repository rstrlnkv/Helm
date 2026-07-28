import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// The slot the running search sits in, so Stop can reach it.
///
/// A new search supersedes the one before it: the engine cancels the old finder
/// and puts the new one in the box. But the old one then returns — cancelled —
/// and used to clear the box on its way out, whoever was in it by then. From
/// that moment "cancel" reached nothing: Stop did nothing to a search that was
/// still hashing, and switching the module off left it running.
///
/// The same defect the disk engine had, and the same fix: a token is spent
/// once, on the slot it was given.
final class FinderBoxTests: XCTestCase {

    func testTheSearchInTheBoxIsTheOneCancelReaches() {
        let box = FinderBox()
        let finder = DuplicateScanner()
        _ = box.start(finder)
        XCTAssertTrue(box.current === finder)
    }

    func testASupersededSearchCannotClearTheOneThatReplacedIt() {
        let box = FinderBox()
        let first = DuplicateScanner()
        let older = box.start(first)
        let second = DuplicateScanner()
        _ = box.start(second)

        older.finish()          // the cancelled search returning, late

        XCTAssertTrue(box.current === second,
                      "the superseded search emptied the box and Stop stopped working")
    }

    func testASearchClearsItsOwnSlotWhenItFinishes() {
        let box = FinderBox()
        let token = box.start(DuplicateScanner())
        token.finish()
        XCTAssertNil(box.current)
    }
}
