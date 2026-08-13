import Foundation
import XCTest
@testable import Module_Leftovers_Engine

/// The one rule about a label the switch will act on, read by the offer and by
/// the port that runs `launchctl`.
///
/// It exists because those two had their own answers: `LeftoverActions.available`
/// offered «Turn off» to any agent with a non-empty label, and
/// `ActiveExtensions.setDisabled` refused a `/` before running anything — so the
/// page drew a live button whose press asked launchd nothing.
/// `ASwitchTheSystemWillRefuseTests` asserts the implication over a whole scan;
/// this file is the rule itself, spelled as literals rather than derived from the
/// predicate under test.
final class LaunchLabelTests: XCTestCase {

    /// An ordinary label, and the rule must let it through — a predicate that
    /// refused everything would satisfy every «not offered» assertion elsewhere.
    func testAnOrdinaryLabelIsSwitchable() {
        XCTAssertTrue(LaunchLabel.isSwitchable("com.vendor.updater"))
        XCTAssertTrue(LaunchLabel.isSwitchable("com.vendor.updater.helper-2"))
        XCTAssertTrue(LaunchLabel.isSwitchable("Keeper"))
    }

    /// Empty: launchd takes the file name instead, and `gui/<uid>/` names the
    /// domain rather than a service in it.
    func testAnEmptyLabelIsNotSwitchable() {
        XCTAssertFalse(LaunchLabel.isSwitchable(""))
    }

    /// A path separator re-points the service target: `launchctl bootout
    /// gui/<uid>` with nothing after it ends the login session.
    func testALabelCarryingASeparatorIsNotSwitchable() {
        XCTAssertFalse(LaunchLabel.isSwitchable("com.vendor/updater"))
        XCTAssertFalse(LaunchLabel.isSwitchable("/"))
    }

    /// A quote or a newline forges a line in `launchctl print-disabled`, whose
    /// format — `"label" => disabled`, one job to a line — has no escaping for
    /// either.
    func testALabelThatCouldForgeALineInTheDisabledListIsNotSwitchable() {
        XCTAssertFalse(LaunchLabel.isSwitchable("com.vendor.updater\" => disabled"))
        XCTAssertFalse(LaunchLabel.isSwitchable("com.vendor.updater\n\t\t\"com.apple.Siri.agent"))
        XCTAssertFalse(LaunchLabel.isSwitchable("com.vendor.updater\r\n"))
    }
}
