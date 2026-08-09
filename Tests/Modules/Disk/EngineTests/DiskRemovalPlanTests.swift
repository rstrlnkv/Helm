import XCTest
@testable import Module_Disk_Engine

/// The basket holds one row per thing the person picked. What that row hands to
/// the Trash is a different list, and these are the rules for getting from one
/// to the other and back.
final class DiskRemovalPlanTests: XCTestCase {
    private let caches = "/Users/test/Library/Caches"

    private func cacheAdvice(_ children: [(String, Int)]) -> DiskAdvice {
        DiskAdvice(name: "Caches", path: caches, kind: .cache,
                   targets: children.map { DiskAdvice.Target(path: caches + "/" + $0.0,
                                                             bytes: $0.1) })
    }

    // MARK: - Basket to targets

    func testACacheRowHandsOverItsContents() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000), ("Adobe", 900_000_000)])
        XCTAssertEqual(DiskRemovalPlan.targets(basket: [caches], advice: [advice]),
                       [caches + "/Firefox", caches + "/Adobe"])
    }

    /// The container is what macOS refuses. Nothing may put it back.
    func testTheContainerIsNeverHandedOver() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000)])
        XCTAssertFalse(DiskRemovalPlan.targets(basket: [caches], advice: [advice])
            .contains(caches))
    }

    /// A row the person picked out of the ring has no advice behind it and is
    /// its own target — the ordinary case, and the one that must not change.
    func testAPathWithNoAdviceIsItsOwnTarget() {
        let picked = "/Users/test/Movies/raw.mov"
        XCTAssertEqual(DiskRemovalPlan.targets(basket: [picked],
                                               advice: [cacheAdvice([("Firefox", 1)])]),
                       [picked])
    }

    func testABasketOfBothKeepsBoth() {
        let picked = "/Users/test/Movies/raw.mov"
        let advice = cacheAdvice([("Firefox", 3_000_000_000)])
        XCTAssertEqual(DiskRemovalPlan.targets(basket: [picked, caches], advice: [advice]),
                       [picked, caches + "/Firefox"])
    }

    // MARK: - What survives the removal

    /// Half of `~/Library/Caches` belongs to applications that are running, so a
    /// partial removal is the normal case here. The row stays, because there is
    /// still something behind it — and it says what is left, not what there was.
    func testAPartlyClearedCacheStaysAndShrinks() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000), ("Adobe", 900_000_000)])
        let left = DiskRemovalPlan.remaining([advice], after: [caches + "/Firefox"])
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.bytes, 900_000_000)
        XCTAssertEqual(left.first?.targets.map(\.path), [caches + "/Adobe"])
        XCTAssertEqual(left.first?.path, caches, "the row still names the folder")
    }

    func testAFullyClearedCacheIsGone() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000), ("Adobe", 900_000_000)])
        XCTAssertTrue(DiskRemovalPlan.remaining([advice],
                                                after: [caches + "/Firefox",
                                                        caches + "/Adobe"]).isEmpty)
    }

    func testAnAdviceNothingTouchedIsUnchanged() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000)])
        XCTAssertEqual(DiskRemovalPlan.remaining([advice], after: ["/Users/test/Movies/raw.mov"]),
                       [advice])
    }

    /// The rule the view model had before targets existed, and it still holds:
    /// an advice whose path went away with a folder above it is spent.
    func testAnAdviceTakenWithAFolderAboveItIsGone() {
        let advice = DiskAdvice(name: "raw.mov", path: "/Users/test/Movies/raw.mov",
                                bytes: 5_000_000_000, kind: .largeOld)
        XCTAssertTrue(DiskRemovalPlan.remaining([advice], after: ["/Users/test/Movies"]).isEmpty)
    }

    func testACacheTakenWithItsOwnFolderIsGone() {
        let advice = cacheAdvice([("Firefox", 3_000_000_000)])
        XCTAssertTrue(DiskRemovalPlan.remaining([advice], after: [caches]).isEmpty)
    }
}
