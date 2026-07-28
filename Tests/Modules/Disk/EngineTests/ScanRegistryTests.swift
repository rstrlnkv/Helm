import Foundation
import XCTest
@testable import Module_Disk_Engine

/// Two scans can be in flight at once, so one slot is not enough.
///
/// The engine kept a single box and wrote it unconditionally: a scan starting
/// replaced whatever was there, and a scan finishing set it to nil whether or
/// not the thing it cleared was its own. Drilling into an unmeasured folder
/// issues a second "scan" command while the first is still walking, so the
/// order start-A, start-B, finish-B left the box empty with A still walking the
/// volume — Stop did nothing, New scan did nothing, and switching the module
/// off left the walk running and emitting.
///
/// Identity is the fix: a scan clears the slot it was given, never the slot
/// somebody else holds, and cancelling reaches everything in flight rather than
/// whatever happened to be stored last.
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

    /// The failure the ring showed: B finishes, and A stops being cancellable.
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
}
