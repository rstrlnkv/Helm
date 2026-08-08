import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one thing this module refuses to do is offer every copy of a file. A
/// button that acts on every group at once is the likeliest place for that
/// refusal to be lost, so it is asserted rather than assumed.
@MainActor
final class BasketAllExtrasTests: XCTestCase {

    private func group(_ names: [String], bytes: Int = 2_000_000) -> DuplicateGroup {
        DuplicateGroup(bytes: bytes, paths: names.map { "\(home)/Downloads/\($0)" })
    }

    func testTheCopyThatStaysIsNeverBasketed() async {
        let dvm = await searchedModel([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/a1"),
                       "the first copy of a group stays")
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/b1"))
    }

    func testEveryExtraInEveryGroupIsBasketed() async {
        let dvm = await searchedModel([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertEqual(Set(dvm.basket), [
            "\(home)/Downloads/a2", "\(home)/Downloads/a3", "\(home)/Downloads/b2",
        ])
    }

    /// The same scope gate the per-group button applies. A button that baskets
    /// something the engine will refuse is a button that lies.
    func testAPathOutOfScopeIsNotBasketed() async {
        let outside = DuplicateGroup(bytes: 2_000_000, paths: [
            "\(home)/Downloads/a1", "/System/Library/CoreServices/a2",
        ])
        let dvm = await searchedModel([outside])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("/System/Library/CoreServices/a2"))
    }

    func testRunningItTwiceDoesNotDoubleTheBasket() async {
        let dvm = await searchedModel([group(["a1", "a2"])])
        dvm.basketAllExtras()
        dvm.basketAllExtras()
        XCTAssertEqual(dvm.basket, ["\(home)/Downloads/a2"])
    }

    func testClearEmptiesTheBasketAndTrashesNothing() async {
        let dvm = await searchedModel([group(["a1", "a2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.isEmpty)
        dvm.clearBasket()
        XCTAssertTrue(dvm.basket.isEmpty)
        XCTAssertEqual(dvm.removedCount, 0, "clearing is not deleting")
    }
}
