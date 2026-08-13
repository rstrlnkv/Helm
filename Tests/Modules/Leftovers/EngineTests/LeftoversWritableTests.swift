import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// Whether Helm can actually move a file is asked of the filesystem, for every
/// kind of item — not only for launch agents.
///
/// `preferences()` and `plugins()` built their items without a `writable:`
/// argument, and the initialiser defaults it to true. That value drives
/// `.delete` in `LeftoverActions.available` and `StaleItem.removable`, which is
/// what "Select all" ticks — so an item in a folder Helm cannot write to was
/// offered for one-click bulk deletion. Nothing was lost silently, because
/// `RemovableScope` and `HelmTrash` still refuse at trash time; the screen
/// simply said something that was not true.
///
/// The existing consistency tests only build launch-agent fixtures, which is
/// the one kind that did ask, so they were vacuous for these two.
///
/// **The fixtures used to lock the item and not its folder.** `FakeFiles`
/// answered by the item's own path — "one locked file among readable ones",
/// said its comment — while `FileSystemLeftovers` answered about the parent
/// directory, which is what unlinking a file actually needs. So the case these
/// tests proved was one no scan can produce, and the case they were written for
/// — a root-owned `/Library` folder — went through the same assertion by
/// accident. They lock the directory now, which is the only lock that decides
/// this — and the fake that does it is `LeftoversFakeFiles`, shared with the rest
/// of this target since 2026-08-13, because the two fakes that folded writability
/// to a single flag could not describe one scan with both answers in it. The last
/// test below is the case they made unwritable.
final class LeftoversWritableTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    private func scan(_ files: LeftoversFakeFiles) -> [StaleItem] {
        LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                         extensions: LeftoversFakeLoaded()).scan()
    }

    // MARK: - Preferences

    private func preferences(locked: Bool) -> StaleItem? {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/Preferences"] = ["com.gone.vendor.app.plist"]
        if locked { files.unwritable = ["/Users/x/Library/Preferences"] }
        return scan(files).first { $0.kind == .preference }
    }

    func testALockedPreferenceIsNotOfferedForBulkDeletion() throws {
        let item = try XCTUnwrap(preferences(locked: true))
        XCTAssertEqual(item.status, .orphaned, "the fixture must be an orphan, or this proves nothing")
        XCTAssertFalse(item.writable, "the scanner never asked whether the folder could be written")
        XCTAssertFalse(item.actions.contains(.delete))
        XCTAssertFalse(item.removable, "Select all would have ticked a file Helm cannot move")
    }

    func testAWritablePreferenceIsStillOffered() throws {
        let item = try XCTUnwrap(preferences(locked: false))
        XCTAssertTrue(item.writable)
        XCTAssertTrue(item.removable)
    }

    // MARK: - Plug-ins

    private func plugins(locked: Bool) -> StaleItem? {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/QuickLook"] = ["Gone.qlgenerator"]
        files.plists["/Users/x/Library/QuickLook/Gone.qlgenerator/Contents/Info.plist"] =
            PlistData(["CFBundleIdentifier": "com.gone.vendor.quicklook"])
        if locked { files.unwritable = ["/Users/x/Library/QuickLook"] }
        return scan(files).first { $0.kind == .plugin }
    }

    func testALockedPluginIsNotOfferedForBulkDeletion() throws {
        let item = try XCTUnwrap(plugins(locked: true))
        XCTAssertEqual(item.status, .orphaned)
        XCTAssertFalse(item.writable, "the scanner never asked whether the folder could be written")
        XCTAssertFalse(item.actions.contains(.delete))
        XCTAssertFalse(item.removable)
    }

    func testAWritablePluginIsStillOffered() throws {
        let item = try XCTUnwrap(plugins(locked: false))
        XCTAssertTrue(item.writable)
        XCTAssertTrue(item.removable)
    }

    // MARK: - One scan, both answers

    /// **The pair every Mac with an updater on it has, and no test could hold it.**
    /// `com.vendor.updater` sits in `~/Library/LaunchAgents` for this person and in
    /// `/Library/LaunchAgents` for everybody — the same label, two files, and the
    /// second is root's. `ScanOrderIsTotalTests` already builds that pair for its
    /// sort, against a fake whose writability was one flag: both rows came back
    /// `writable: true`, so the row that needs an administrator was ticked in every
    /// fixture the suite had.
    ///
    /// Three things have to be true of it at once, and only the third is about the
    /// sort: the person's copy may be moved, root's may not — and both may still be
    /// switched off, because launchd's disabled list is per-user and works on a
    /// system-wide agent without a password. That last one is why the row offers
    /// «Turn off» where it offers no delete, and it is the whole of what
    /// `LeftoverActions` documents about the two.
    func testTheSameLabelInBothFoldersIsTwoRowsWithDifferentOffers() throws {
        var files = LeftoversFakeFiles()
        for directory in ["/Users/x/Library/LaunchAgents", "/Library/LaunchAgents"] {
            files.listing[directory] = ["com.vendor.updater.plist"]
            files.plists["\(directory)/com.vendor.updater.plist"] =
                PlistData(["Label": "com.vendor.updater",
                           "Program": "/Library/Application Support/Vendor/updater"])
        }
        // Root's folder, and only root's.
        files.unwritable = ["/Library/LaunchAgents"]

        let items = scan(files)

        XCTAssertEqual(items.count, 2, "precondition: both copies of the label were found")
        let mine = try XCTUnwrap(items.first { $0.path.hasPrefix("/Users/x/") })
        let everybodys = try XCTUnwrap(items.first { $0.path.hasPrefix("/Library/") })
        XCTAssertEqual(mine.identifier, everybodys.identifier,
                       "precondition: one label, two files — the case the sort breaks by path")

        XCTAssertTrue(mine.writable)
        XCTAssertTrue(mine.removable, "the person's own LaunchAgents folder is theirs to unlink in")

        XCTAssertFalse(everybodys.writable)
        XCTAssertFalse(everybodys.removable,
                       "«Select all» ticked a file in root's folder, and the batch then asked "
                       + "`HelmTrash` for something no password here can give it")
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: everybodys), .needsAdministrator,
                       "and this is the row where that sentence is the true one")

        XCTAssertTrue(mine.canToggle)
        XCTAssertTrue(everybodys.canToggle,
                      "launchd's disabled list is the user's own, so a system-wide agent can be "
                      + "switched off without a password — the one offer this row keeps")
    }
}
