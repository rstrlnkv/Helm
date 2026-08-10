import XCTest
import AppKit
import IOKit.pwr_mgt
@testable import Module_KeepAwake_Engine

/// «This Mac is being kept awake by something that is not Helm» is worth
/// exactly as much as it is rare, and it shipped permanently true.
///
/// The user's report was the whole test case: the line was on screen with
/// nothing of the sort running. It was not wrong — `pmset -g assertions` on
/// that Mac listed three holders — it was *useless*, because two of the three
/// are macOS itself:
///
/// ```
/// pid 377(powerd):   PreventUserIdleSystemSleep  "Powerd - Prevent sleep while display is on"
/// pid 1145(sharingd): PreventUserIdleSystemSleep "Handoff"
/// pid 1789(Claude):   NoIdleSleepAssertion       "Electron"
/// ```
///
/// `powerd`'s is held for as long as the screen is lit — so the sentence was
/// true whenever there was somebody there to read it. The port already filtered
/// `UserIsActive` for precisely this reason and had missed the bigger case.
final class AWarningThatIsAlwaysTrueTests: XCTestCase {

    private let systemSleep = kIOPMAssertionTypePreventUserIdleSystemSleep as String
    private let userIsActive = "UserIsActive"

    /// The control. An application really holding one of the sleep kinds is
    /// the entire point of the line, and every assertion below is about
    /// something *not* counting — which passes trivially if nothing counts.
    func testAnOrdinaryAppHoldingSleepIsCounted() {
        XCTAssertTrue(SleepHolderFilter.counts(kind: systemSleep, policy: .regular),
                      "a regular app holding PreventUserIdleSystemSleep is the case this "
                      + "warning exists for")
        XCTAssertTrue(SleepHolderFilter.counts(kind: systemSleep, policy: .accessory),
                      "a menu-bar app is still an app somebody can go and quit")
    }

    /// `powerd`, `WindowServer`, `coreaudiod`, `backupd`: measured `nil`.
    func testADaemonWithNoLaunchServicesRecordIsNotCounted() {
        XCTAssertFalse(SleepHolderFilter.counts(kind: systemSleep, policy: nil),
                       "powerd holds this for as long as the display is on, which made the "
                       + "line permanently true")
    }

    /// The one a nil check would have missed. `sharingd` *is* registered — it
    /// comes back as `com.apple.sharingd` — and holds "Handoff" for as long as
    /// Handoff is switched on, which for most people is always.
    func testAProhibitedBackgroundProcessIsNotCounted() {
        XCTAssertFalse(SleepHolderFilter.counts(kind: systemSleep, policy: .prohibited),
                       "sharingd answers NSRunningApplication and holds \"Handoff\" for ever; "
                       + "a nil check alone would have shipped this warning still stuck on")
    }

    /// The older half of the filter, kept honest: four of the ten assertions on
    /// an idle Mac are of this family.
    func testBeingAtTheKeyboardIsNotHoldingSleep() {
        XCTAssertFalse(SleepHolderFilter.counts(kind: userIsActive, policy: .regular))
    }

    /// And the kinds list is not empty, so the kind test above can fail.
    func testTheKindListIsRealAndNamesTheSleepAssertions() {
        XCTAssertEqual(SleepHolderFilter.holdingKinds.count, 4)
        XCTAssertTrue(SleepHolderFilter.holdingKinds.contains(systemSleep))
        XCTAssertFalse(SleepHolderFilter.holdingKinds.contains(userIsActive))
    }
}
