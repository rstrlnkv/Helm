import Foundation
import XCTest
@testable import Module_Leftovers_Engine

/// Whether Helm can actually move a file is asked of the filesystem, for every
/// kind of item — not only for launch agents.
///
/// The initialiser defaults `writable:` to true, and that value drives `.delete`
/// in `LeftoverActions.available` and `StaleItem.removable`, which is what
/// "Select all" ticks — so an item built without asking would be offered for
/// bulk deletion from a folder Helm cannot write to. `RemovableScope` and
/// `HelmTrash` would still refuse at trash time; the screen would say something
/// untrue.
///
/// **The fixtures lock the directory, not the item**: unlinking a file needs
/// write access to its parent, and `FileSystemLeftovers` answers about the
/// parent. A fake answering by item path would prove a case no scan can
/// produce.
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

    /// **The pair every Mac with an updater on it has.** `com.vendor.updater` sits
    /// in `~/Library/LaunchAgents` for this person and in `/Library/LaunchAgents`
    /// for everybody — the same label, two files, and the second is root's.
    ///
    /// Three things have to be true of it at once: the person's copy may be moved,
    /// root's may not — and **neither may be switched**. Both files register
    /// `com.vendor.updater`, `launchctl disable gui/<uid>/…` is aimed at that name,
    /// and Helm cannot read which registration launchd kept
    /// (`OneLabelIsOneSwitchTests`). «launchd's disabled list is the user's own, so
    /// root's folder does not withhold the switch» is asserted below, on an agent
    /// no second file claims.
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

        XCTAssertFalse(mine.canToggle)
        XCTAssertFalse(everybodys.canToggle,
                       "one label, two files, one `launchctl disable` — the row a person "
                       + "presses would be the one whose badge they liked least")
        XCTAssertEqual(mine.labelAlsoClaimedBy, everybodys.path,
                       "and the row says which other file wears its name, or the switch is "
                       + "simply missing")
        XCTAssertEqual(everybodys.labelAlsoClaimedBy, mine.path)
    }

    /// An agent installed for everybody, in a folder Helm may not write in, with
    /// nobody else claiming its label. launchd's disabled list is the user's own,
    /// so it is switchable without a password — the one offer this row keeps, and
    /// the reason `LeftoverActions` withholds delete and not the switch.
    func testASystemWideAgentNobodyElseClaimsIsStillSwitchable() throws {
        var files = LeftoversFakeFiles()
        files.listing["/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater",
                       "Program": "/Library/Application Support/Vendor/updater"])
        files.unwritable = ["/Library/LaunchAgents"]

        let everybodys = try XCTUnwrap(scan(files).first)

        XCTAssertNil(everybodys.labelAlsoClaimedBy, "precondition: one file wears this label")
        XCTAssertFalse(everybodys.writable)
        XCTAssertTrue(everybodys.canToggle,
                      "launchd's disabled list is the user's own, so a system-wide agent can be "
                      + "switched off without a password")
    }
}
