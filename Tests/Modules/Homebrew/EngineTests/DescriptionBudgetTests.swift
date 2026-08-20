import XCTest
@testable import Module_Homebrew_Engine

/// The number `describe`'s split is allowed to spend, and why it is two floors
/// rather than one.
///
/// `ADescriptionBatchCannotCostMoreThanItsNamesTests` bounds the whole engine's
/// behaviour; this bounds the arithmetic under it, where the two cases that
/// pull in opposite directions can be stated one at a time. Both are properties
/// of the bisection `describe` performs, not preferences:
///
///   * a batch brew refuses **wholesale** walks to a leaf per name and pays for
///     every interior node — `2n-1` calls, each a `brew` run taking one of the
///     app's eight `HelmProcess` slots;
///   * a batch with **one** name brew cannot resolve costs `2⌈log₂n⌉ + 1` — two
///     calls a level, the half that answers and the half that does not — and
///     that is the case the split exists for, so it must fit.
///
/// The second is larger than `n + 1` for a small batch, which is the trap: a
/// budget of `n + 1` alone silently drops descriptions brew was willing to give
/// for any batch under eight names.
final class DescriptionBudgetTests: XCTestCase {

    /// Spelled out rather than derived from the production formula — a test
    /// whose two sides read one expression cannot fail. Each expected value is
    /// the cost of isolating one bad name at that size, counted by hand.
    func testABatchAlwaysAffordsIsolatingOneBadName() {
        for (names, isolating) in [(1, 1), (2, 3), (3, 5), (4, 5), (5, 7), (8, 7),
                                   (16, 9), (32, 11), (54, 13)] {
            XCTAssertGreaterThanOrEqual(DescriptionBudget(forBatchOf: names).allowance, isolating, """
                a batch of \(names) names is cut off before the split can isolate the \
                one name brew cannot resolve, which costs \(isolating) calls — every \
                description in the abandoned half is lost for a reason brew never gave
                """)
        }
    }

    /// The other floor, and the one that bounds the pathological case: past one
    /// call per name plus the batch itself, the bisection has stopped beating
    /// the naive strategy it replaced.
    func testALargeBatchIsNeverAllowedMoreThanACallPerNameAndOne() {
        for names in [8, 16, 32, 54, 200] {
            XCTAssertLessThanOrEqual(DescriptionBudget(forBatchOf: names).allowance, names + 1,
                                     "a batch of \(names) names may spend "
                                     + "\(DescriptionBudget(forBatchOf: names).allowance) `brew` runs")
        }
    }

    /// And it is far under the `2n-1` the unbounded split reaches, which is the
    /// whole point: 54 packages — an ordinary Cellar — turned one page load
    /// into 107 `brew` runs the moment brew refused for a reason that was not
    /// about any one name.
    func testTheBudgetIsWellUnderTheUnboundedSplit() {
        XCTAssertLessThan(DescriptionBudget(forBatchOf: 54).allowance, 2 * 54 - 1)
    }

    /// And it is spent one call at a time and then refuses — without which the
    /// two floors above are arithmetic nothing enforces.
    func testABudgetIsSpentAndThenRefuses() {
        let budget = DescriptionBudget(forBatchOf: 2)   // three calls, by both floors
        XCTAssertFalse(budget.exhausted)
        XCTAssertTrue(budget.spend())
        XCTAssertTrue(budget.spend())
        XCTAssertTrue(budget.spend())
        XCTAssertFalse(budget.spend(), "a fourth call was allowed out of a budget of three")
        XCTAssertTrue(budget.exhausted)
    }
}
