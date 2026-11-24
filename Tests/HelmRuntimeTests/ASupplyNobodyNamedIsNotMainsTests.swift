import XCTest
import IOKit.ps
@testable import HelmRuntime

/// «Is this Mac on mains» is a reading of its own, not derived from the
/// battery reading.
///
/// The battery reading is nil for two unrelated reasons: a Mac with no battery
/// (an empty power-source list) and an IOKit dictionary without a capacity.
/// Folding nil into «on mains» would make `BatteryGuard`'s not-on-mains branch
/// unreachable and let Keep Awake hold the Mac awake on a source it cannot
/// read. `IOPSGetProvidingPowerSourceType` names the supply from the same
/// snapshot without consulting the source list, so it answers on a desktop too.
///
/// So `supply()` answers the question, `Supply` is the vocabulary, and a supply
/// the system did not name is not mains. Each caller states its own fold: a
/// background scan reads unknown as mains, because never scanning on a quiet
/// Mac is its worse failure; Keep Awake reads it as not-mains, because letting
/// the Mac sleep is that module's.
final class ASupplyNobodyNamedIsNotMainsTests: XCTestCase {

    // MARK: - The reading, against IOKit's own constants

    func testTheSystemsWordForMains() {
        XCTAssertEqual(PowerSource.supply(providing: kIOPSACPowerValue), .mains)
    }

    func testTheSystemsWordForBattery() {
        XCTAssertEqual(PowerSource.supply(providing: kIOPSBatteryPowerValue), .battery)
    }

    /// No answer is not mains.
    func testNoAnswerAtAllIsNotMains() {
        XCTAssertNil(PowerSource.supply(providing: nil),
                     "a snapshot that named no supply used to read as «on mains», which is how "
                     + "an unreadable power source came to hold the Mac awake")
    }

    /// A supply that exists and is not one of the two this app reasons about —
    /// `kIOPMUPSPowerKey`, and whatever a later macOS invents. Unknown, not
    /// mains: a Mac drawing from a UPS is a Mac whose power can run out.
    func testASupplyThisAppDoesNotKnowIsUnknownRatherThanMains() {
        XCTAssertNil(PowerSource.supply(providing: "UPS Power"))
        XCTAssertNil(PowerSource.supply(providing: "Something macOS has not shipped yet"))
    }

    /// And the empty string, a CFString bridged from nothing.
    func testAnEmptyAnswerIsUnknownToo() {
        XCTAssertNil(PowerSource.supply(providing: ""))
    }

    // MARK: - The fold the background scan asks for, kept

    /// `ScanCoordinator` reads `isOnMains`, and its worse failure is the
    /// opposite of Keep Awake's: a Mac whose hardware stays quiet must still be
    /// scanned. So unknown stays mains *here*, and the module folds the other
    /// way at its own call site.
    func testTheScansReaderStillTreatsAnUnknownSupplyAsMains() {
        XCTAssertTrue(PowerSource.isOnMains(PowerSource.supply(providing: nil)))
        XCTAssertTrue(PowerSource.isOnMains(PowerSource.supply(providing: kIOPSACPowerValue)))
        XCTAssertFalse(PowerSource.isOnMains(PowerSource.supply(providing: kIOPSBatteryPowerValue)),
                       "a Mac on its battery is the one reading that stops a scan")
    }

    // MARK: - Against the machine

    /// The reading really comes from the system, so nothing above is a test of
    /// a table of strings. It holds in either power state: what is pinned is
    /// that the supply is named.
    func testThisMacNamesItsSupply() throws {
        let supply = try XCTUnwrap(PowerSource.supply(),
                                   "IOKit named no supply on a running Mac, so every reader here "
                                   + "is on its fallback and none of them is being exercised")
        XCTAssertEqual(supply == .battery, PowerSource.current()?.onBattery ?? (supply == .battery),
                       "the independent mains fact and the battery reading disagree about this "
                       + "machine, which is the one thing they may not do while both can be read")
    }
}
