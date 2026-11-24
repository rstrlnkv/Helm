import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// The slot the running search sits in, so Stop can reach it.
///
/// A new search supersedes the one before it: the engine cancels the old finder
/// and puts the new one in the box. The old one then returns, cancelled; were it
/// to clear the box on its way out, Stop would reach nothing and switching the
/// module off would leave the new search running. A token is spent once, on the
/// slot it was given.
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
