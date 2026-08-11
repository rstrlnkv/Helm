import XCTest
import IOKit.ps
@testable import HelmRuntime

/// «Is this Mac on mains» was derived from the *battery* reading, so it could
/// only ever answer yes when the reading failed.
///
/// `isOnMains` was `guard let reading = current() else { return true }`, and
/// `current()` is nil for two reasons that have nothing in common: a Mac with no
/// battery (an empty power-source list — a mini, a Studio, an iMac) and an IOKit
/// dictionary that came back without a capacity. Both arrived as «on mains», so
/// two things followed. `BatteryGuard.shouldDeactivateWithNoReading`'s
/// `!isOnMains` branch was unreachable in production — the one thing that ever
/// ends an unattended session could not fire on the path written for it. And
/// Keep Awake's `powerCondition()` read a source it could not read at all as ON
/// power and *started holding the Mac awake*, against its own comment («nil for
/// an incomplete dictionary still has to mean not-on-power»).
///
/// The mains fact has to be independent of the battery reading, and IOKit has
/// one: `IOPSGetProvidingPowerSourceType` names the supply from the same
/// snapshot without consulting the source list, which is why it answers on a
/// desktop where the list is empty. Measured on the Mac this was written on,
/// plugged in: `providing: AC Power`, one source, `state=AC Power now=80
/// max=100`.
///
/// So `supply()` answers the question, `Supply` is the vocabulary, and **a
/// supply the system did not name is not mains**. Each caller then states its
/// own fold in the open: a background scan reads unknown as mains, because
/// never scanning on a Mac whose hardware stays quiet is its worse failure;
/// Keep Awake reads it as not-mains, because letting the Mac sleep is that
/// module's.
final class ASupplyNobodyNamedIsNotMainsTests: XCTestCase {

    // MARK: - The reading, against IOKit's own constants

    func testTheSystemsWordForMains() {
        XCTAssertEqual(PowerSource.supply(providing: kIOPSACPowerValue), .mains)
    }

    func testTheSystemsWordForBattery() {
        XCTAssertEqual(PowerSource.supply(providing: kIOPSBatteryPowerValue), .battery)
    }

    /// The whole point of the change: nothing to fold into mains.
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

    /// And the empty string, which is what a CFString bridged from nothing at
    /// all looks like if anybody ever changes how it is read.
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
    /// a table of strings. Written to hold in both states rather than to assert
    /// this Mac's: what is pinned is that the supply is *named* — the state the
    /// whole change is about is the one where it is not.
    func testThisMacNamesItsSupply() throws {
        let supply = try XCTUnwrap(PowerSource.supply(),
                                   "IOKit named no supply on a running Mac, so every reader here "
                                   + "is on its fallback and none of them is being exercised")
        XCTAssertEqual(supply == .battery, PowerSource.current()?.onBattery ?? (supply == .battery),
                       "the independent mains fact and the battery reading disagree about this "
                       + "machine, which is the one thing they may not do while both can be read")
    }
}
