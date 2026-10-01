import XCTest
@testable import HelmRuntime

/// `Int.saturatingAdding(_:)` and `Sequence.saturatingSum()` at the two ends of an
/// integer and with signs mixed — the inputs nobody fed the Disk sums, which only
/// ever add figures held to `0...byteCeiling`.
///
/// The helper is public and lives in the runtime, so the next caller may hand it
/// a negative figure; the low end is half of what it promises (`Int.min` instead
/// of trapping) and nothing else checks that half.
final class SaturatingSumUnderOddInputsTests: XCTestCase {

    func testTheTopHoldsAtTheTop() {
        XCTAssertEqual(Int.max.saturatingAdding(1), .max)
        XCTAssertEqual(Int.max.saturatingAdding(.max), .max)
        XCTAssertEqual(1.saturatingAdding(.max), .max)
    }

    func testTheBottomHoldsAtTheBottom() {
        XCTAssertEqual(Int.min.saturatingAdding(-1), .min, "an underflow must stop at Int.min, not at Int.max")
        XCTAssertEqual(Int.min.saturatingAdding(.min), .min)
        XCTAssertEqual((-1).saturatingAdding(.min), .min)
    }

    /// Opposite signs never overflow, and the exact answer comes back.
    func testOppositeSignsAddExactly() {
        XCTAssertEqual(Int.max.saturatingAdding(.min), -1)
        XCTAssertEqual(Int.min.saturatingAdding(.max), -1)
        XCTAssertEqual(Int.max.saturatingAdding(-1), .max - 1)
        XCTAssertEqual(Int.min.saturatingAdding(1), .min + 1)
    }

    func testAnEmptySequenceIsZero() {
        XCTAssertEqual([Int]().saturatingSum(), 0)
    }

    func testAnOrdinarySumIsTheSum() {
        XCTAssertEqual([3, -5, 7].saturatingSum(), 5)
    }

    /// Figures that are all non-negative saturate for good: once the top is
    /// reached no later figure can bring the sum back, so the answer does not
    /// depend on the order they came in — which is the property the Disk sums
    /// rely on.
    func testNonNegativeFiguresSaturateWhateverTheirOrder() {
        let figures = [Int.max / 2, 1, Int.max / 2, 7, Int.max / 3, 0]
        XCTAssertEqual(figures.saturatingSum(), .max)
        XCTAssertEqual(figures.reversed().saturatingSum(), .max)
        XCTAssertEqual(figures.sorted().saturatingSum(), .max)
    }

    /// **With signs mixed the sum depends on the order.** Saturation forgets how
    /// far past the top the running total went, so a later negative figure takes
    /// from `Int.max` instead of from the true total. Pinned so a caller that adds
    /// signed figures learns it from a test and not from a wrong total.
    func testMixedSignsDependOnTheOrderTheyArrive() {
        XCTAssertEqual([Int.max, 1, -1].saturatingSum(), .max - 1, "saturated first, then reduced")
        XCTAssertEqual([Int.max, -1, 1].saturatingSum(), .max, "reduced first, then saturated")
        XCTAssertEqual([Int.min, -1, 1].saturatingSum(), .min + 1)
    }
}
