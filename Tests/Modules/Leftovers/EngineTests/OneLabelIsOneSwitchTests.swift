import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **launchd's switch is aimed at a label, and a label is not a file.**
///
/// `ScanOrderIsTotalTests` records the ordinary Mac this is about: «`com.vendor.updater`
/// sits in `~/Library/LaunchAgents` and in `/Library/LaunchAgents` on plenty of
/// Macs — one agent per user, one for everybody». The scan returns both, and it is
/// right to: they are two files, and one of them may well be dead while the other
/// is the one doing the work.
///
/// What is not two is the switch. `ActiveExtensions.setDisabled` runs
/// `launchctl disable gui/<uid>/<label>` and `bootout` beside it, and neither
/// takes a path — `LaunchLabel.mayBeSwitched` reads the path only to decide
/// whether the *label* may be aimed at. Both rows pass it: each sits in a folder
/// ending `/Library/LaunchAgents` and each is named after the label it claims. So
/// the page draws «Turn off» twice, on two rows wearing the same name, and either
/// press is the same act on the same label.
///
/// The cost is not the duplicate button, it is which row a person presses. One of
/// these rows is badged «Leftover» — orange, with a checkbox — and the other «In
/// use», green. Turning off the leftover is the obvious tidy-up, and it stops the
/// job the other row says is running: the vendor's updater no longer loads at
/// login, with nothing on screen having claimed that it would.
///
/// The assertion is about the pair rather than about the button, so a fix is free
/// to be any of the ones available — withhold the switch where a label is claimed
/// twice in one scan, fold the pair into a row that says «two files, one job», or
/// ask before the press. What it may not be is wording alone: two rows carrying
/// one name, one of them green and one orange, do not leave a person able to act
/// correctly on either.
final class OneLabelIsOneSwitchTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// The pair: root's copy points at a program that is there, the person's own
    /// at one that is gone. Nothing here is planted — this is one vendor's
    /// updater installed for everybody and a stale per-user copy of it, which is
    /// what an upgrade that moved the agent leaves behind.
    private func scan() -> [StaleItem] {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.listing["/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater",
                       "Program": "/Library/Application Support/Vendor/updater"])
        files.plists["/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater",
                       "Program": "/Library/Application Support/Vendor/updater-2"])
        // Only the second program is on the disk, so the person's own copy is the
        // one badged «Leftover».
        files.existing = ["/Library/Application Support/Vendor/updater-2"]
        return LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(ids: []),
                                extensions: LeftoversFakeLoaded()).scan()
    }

    /// The Mac this is about, stated before anything is claimed about it: two
    /// rows, one name, one of them dead and one of them working.
    func testTheScanReallyHoldsALeftoverAndALiveJobUnderOneName() throws {
        let items = scan()

        XCTAssertEqual(items.count, 2, "precondition: both copies were found")
        XCTAssertEqual(Set(items.map(\.identifier)), ["com.vendor.updater"],
                       "precondition: they share the label the switch is aimed at")
        XCTAssertEqual(Set(items.map(\.status)), [.orphaned, .inUse],
                       "precondition: one is a leftover and the other is in use")
    }

    /// **The finding.** The switch on the leftover row is the switch on the live
    /// one.
    func testNoSwitchOnALeftoverStopsAJobTheSameScanCallsInUse() throws {
        let items = scan()

        for row in items where row.status == .orphaned && row.canToggle {
            let live = items.filter { $0.identifier == row.identifier && $0.status == .inUse }
            XCTAssertEqual(live.map(\.path), [], """
                The row at \(row.path) is badged «Leftover» and offers «Turn off», \
                and the press sends `launchctl disable gui/<uid>/\(row.identifier)` \
                — the same label this scan reports as in use at \
                \(live.map(\.path)). Turning off what the page calls rubbish stops \
                what the page calls working software, and the two rows carry the \
                same name.
                """)
        }
    }

    /// And the other half of it, said once so a fix can be measured against it:
    /// one label, at most one row offering to switch it.
    func testOneLabelIsOfferedOneSwitch() {
        let items = scan()
        let offered = items.filter(\.canToggle)

        XCTAssertEqual(Set(offered.map(\.identifier)).count, offered.count, """
            \(offered.count) rows offer «Turn off» for \
            \(Set(offered.map(\.identifier)).count) label(s): \(offered.map(\.path)). \
            launchd's disabled list is keyed by label, so these are not two \
            switches — they are one switch drawn twice, and the row a person \
            presses is the one whose badge they liked least.
            """)
    }
}
