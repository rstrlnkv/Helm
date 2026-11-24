import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

/// Two scans can be in flight at once, so one slot is not enough.
///
/// In the order start-A, start-B, finish-B a single slot would be left empty
/// with A still walking, and Stop, New scan and the module's switch would not
/// reach it. So a scan clears only the slot it was given, and cancelling
/// reaches everything in flight.
final class ScanRegistryTests: XCTestCase {

    /// Any object will do — the registry is bookkeeping, not scanning.
    private final class Scan {}

    func testEveryScanInFlightIsReachable() {
        let registry = ScanRegistry<Scan>()
        let first = Scan(), second = Scan()
        _ = registry.add(first)
        _ = registry.add(second)

        let held = registry.inFlight
        XCTAssertEqual(held.count, 2)
        XCTAssertTrue(held.contains { $0 === first })
        XCTAssertTrue(held.contains { $0 === second })
    }

    /// B finishes, and A is still cancellable.
    func testAFinishedScanClearsOnlyItsOwnSlot() {
        let registry = ScanRegistry<Scan>()
        let walking = Scan(), measuring = Scan()
        let walkingToken = registry.add(walking)
        let measuringToken = registry.add(measuring)

        registry.remove(measuringToken)

        XCTAssertEqual(registry.inFlight.count, 1)
        XCTAssertTrue(registry.inFlight.first === walking,
                      "the scan that finished took the other one's slot with it")
        registry.remove(walkingToken)
        XCTAssertTrue(registry.inFlight.isEmpty)
    }

    /// A token spends once. Clearing again must not reach the scan that took
    /// the slot afterwards.
    func testATokenCannotBeSpentTwice() {
        let registry = ScanRegistry<Scan>()
        let first = Scan()
        let token = registry.add(first)
        registry.remove(token)

        let second = Scan()
        _ = registry.add(second)
        registry.remove(token)

        XCTAssertEqual(registry.inFlight.count, 1)
        XCTAssertTrue(registry.inFlight.first === second)
    }

    func testNothingInFlightIsNotAnError() {
        let registry = ScanRegistry<Scan>()
        XCTAssertTrue(registry.inFlight.isEmpty)
        registry.remove(7)
        XCTAssertTrue(registry.inFlight.isEmpty)
    }

    /// What `cancel()` is for: a walk told to stop answers nil, and nil is also
    /// the answer for a path that is not there — hence the control, a scanner
    /// that was not cancelled reading the same root.
    func testCancelReturnsNil() throws {
        let root = scratchDirectory("disk-cancel")
        try write("a.bin", in: root, bytes: 1_000)
        XCTAssertNotNil(DiskScanner(foldThreshold: 0).scan(root: root.path))

        let scanner = DiskScanner(foldThreshold: 0)
        scanner.cancel()
        XCTAssertNil(scanner.scan(root: root.path))
    }
}
