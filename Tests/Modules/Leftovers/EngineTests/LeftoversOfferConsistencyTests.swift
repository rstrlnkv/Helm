import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Leftovers_Engine

/// A row on this page makes two offers, and they are computed by two different
/// pieces of code that never consult each other.
///
/// `StaleItem.removable` draws the checkbox, and the checkbox is the bulk path:
/// "Select all" ticks every one of them and one button sends the lot to the
/// engine. `LeftoverActions.available` draws the row's own menu, and where it
/// withholds `.delete` the menu says so in words — "needs an administrator".
///
/// Where the two disagree, the person is told both that this cannot be deleted
/// and, by a ticked box in a batch of thirty, that it is about to be.
final class LeftoversOfferConsistencyTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/x")

    private func scan(_ files: LeftoversFakeFiles, installed: Set<String> = []) -> [StaleItem] {
        LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(ids: installed),
                         extensions: LeftoversFakeLoaded()).scan()
    }

    /// A daemon whose owner is gone, in a folder that can be written to.
    ///
    /// `LeftoverActions` refuses `.delete` for a daemon on purpose — "Daemons
    /// load in the system domain: switching one off needs root, so the row
    /// offers nothing rather than a button that always fails". `removable`
    /// checks the status, the kind-is-not-an-extension and the writability, and
    /// never asks about the daemon at all.
    func testABulkTickIsNeverOfferedForSomethingTheRowRefusesToDelete() {
        var files = LeftoversFakeFiles()
        files.listing["/Library/LaunchDaemons"] = ["com.gone.vendor.helper.plist"]
        files.plists["/Library/LaunchDaemons/com.gone.vendor.helper.plist"] =
            PlistData(["Label": "com.gone.vendor.helper"])

        let items = scan(files)
        let daemon = items.first { $0.kind == .launchDaemon }
        XCTAssertNotNil(daemon)
        XCTAssertEqual(daemon?.status, .orphaned, "the fixture is an orphan, as intended")

        XCTAssertEqual(daemon?.removable, daemon?.actions.contains(.delete),
                       "the checkbox says \(daemon?.removable == true ? "delete this" : "no") "
                       + "and the menu on the same row says "
                       + "\(daemon?.actions.contains(.delete) == true ? "delete this" : "needs an administrator")")
    }

    /// Said over a whole scan rather than one fixture, so a later kind cannot
    /// reintroduce the same disagreement somewhere else.
    func testTheCheckboxAndTheRowMenuAgreeAboutEveryItemAScanReturns() {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.gone.vendor.agent.plist"]
        files.listing["/Library/LaunchAgents"] = ["com.gone.other.agent.plist"]
        files.listing["/Library/LaunchDaemons"] = ["com.gone.vendor.helper.plist"]
        // **Listed *and* readable, which are two facts in the fake as they are on
        // disk.** These three were listed and never given a plist, so the scan read
        // them as jobs whose definition would not come — `.unreadable` since
        // `APlistNobodyCouldReadTests`, and before that `.orphaned` by way of «no
        // `Program`, so it points at nothing». A row this file is about is an
        // ordinary orphan: a job Helm read, whose owner is gone.
        for (directory, label) in [("/Users/x/Library/LaunchAgents", "com.gone.vendor.agent"),
                                   ("/Library/LaunchAgents", "com.gone.other.agent"),
                                   ("/Library/LaunchDaemons", "com.gone.vendor.helper")] {
            files.plists["\(directory)/\(label).plist"] = PlistData(["Label": label])
        }
        files.listing["/Users/x/Library/Preferences"] = ["com.gone.vendor.app.plist",
                                                         "com.apple.dock.plist"]
        files.listing["/Users/x/Library/QuickLook"] = ["Gone.qlgenerator"]
        files.plists["/Users/x/Library/QuickLook/Gone.qlgenerator/Contents/Info.plist"] =
            PlistData(["CFBundleIdentifier": "com.gone.vendor.quicklook"])

        let disagreeing = scan(files).filter { $0.removable != $0.actions.contains(.delete) }

        XCTAssertEqual(disagreeing.map(\.path), [],
                       "these rows are ticked by Select all and refuse to be deleted "
                       + "from their own menu")
    }
}
