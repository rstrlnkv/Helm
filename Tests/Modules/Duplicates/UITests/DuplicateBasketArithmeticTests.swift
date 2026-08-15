import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// What the basket says it will free.
///
/// The bar under the list reads "N · X", and X was the group's single size
/// counted once per ticked path — so a group holding an HFS-compressed copy
/// beside its original promised the small figure for the original, or the
/// original's for the small one. Copies of one thing need not occupy the same
/// amount; each one carries its own.
///
/// **The fixture is a compressed copy, not a clone at zero.** It used to plant
/// `bytes: 0` on a copy called `clone` — a state APFS cannot produce: measured,
/// a 20 MB clone reports its full allocated size, and what makes its removal
/// free nothing is `cloneFamily`, not a zero. An HFS-compressed copy really
/// does occupy less than its logical length, which is the state these two
/// tests were written about.
@MainActor
final class DuplicateBasketArithmeticTests: XCTestCase {

    /// The compressed copy stays, the plain one goes: what leaves is four
    /// megabytes, not the little the compressed copy occupies.
    func testTheBasketCountsEachCopysOwnSize() async {
        let compressed = "\(home)/Downloads/compressed.bin"
        let real = "\(home)/Downloads/real.bin"
        let dvm = await searchedModel([DuplicateGroup(copies: [
            .init(path: compressed, bytes: 65_536),
            .init(path: real, bytes: 4_000_000),
        ])])
        XCTAssertEqual(dvm.groups.count, 1, "the fixture never reached the view model")

        dvm.toggleBasket(real)

        XCTAssertEqual(dvm.basket, [real])
        XCTAssertEqual(dvm.basketBytes, 4_000_000,
                       "the basket quoted the copy that stays")
    }

    /// The same figure, one path at a time: the basket menu names each copy
    /// beside its own size, and asking the group would print the size of the
    /// copy that stays against every row in the list.
    func testACopysOwnSizeIsAskedOfThatCopy() async {
        let compressed = "\(home)/Downloads/compressed.bin"
        let real = "\(home)/Downloads/real.bin"
        let dvm = await searchedModel([DuplicateGroup(copies: [
            .init(path: compressed, bytes: 65_536),
            .init(path: real, bytes: 4_000_000),
        ])])

        XCTAssertEqual(dvm.bytes(of: real), 4_000_000)
        XCTAssertEqual(dvm.bytes(of: compressed), 65_536)
        XCTAssertEqual(dvm.bytes(of: "\(home)/Downloads/never-seen.bin"), 0,
                       "a path this search never returned has no size to quote")
    }

    /// And the whole group's promise is the sum of the ones that would go.
    func testWastedIsWhatTheExtrasOccupy() async {
        let dvm = await searchedModel([DuplicateGroup(copies: [
            .init(path: "\(home)/Downloads/a.bin", bytes: 1_000_000),
            .init(path: "\(home)/Downloads/b.bin", bytes: 2_000_000),
            .init(path: "\(home)/Downloads/c.bin", bytes: 3_000_000),
        ])])
        XCTAssertEqual(dvm.wastedBytes, 5_000_000)
    }
}
