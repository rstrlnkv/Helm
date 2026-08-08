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
/// this.
final class LeftoversWritableTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// Writability by directory, because that is the only distinction the
    /// filesystem offers here: `~/Library/Preferences` against
    /// `/Library/LaunchAgents`.
    private struct FakeFiles: LeftoversFilePort {
        var unwritable: Set<String> = []
        var listing: [String: [String]] = [:]
        var plists: [String: PlistData] = [:]

        func isWritableDirectory(_ url: URL) -> Bool { !unwritable.contains(url.path) }
        func children(of url: URL) -> [URL] {
            (listing[url.path] ?? []).map { url.appendingPathComponent($0) }
        }
        func exists(_ path: String) -> Bool { false }
        func size(_ url: URL) -> Int { 100 }
        func readPlist(_ url: URL) -> PlistData? { plists[url.path] }
    }

    private struct FakeApps: InstalledAppsPort {
        func installedBundleIDs() -> Set<String> { [] }
    }

    private struct FakeExtensions: LoadedItemsPort {
        func installedExtensions() -> [SystemExtensionInfo] { [] }
        func disabledLabels() -> Set<String> { [] }
    }

    private func scan(_ files: FakeFiles) -> [StaleItem] {
        LeftoversScanner(home: home, files: files, apps: FakeApps(),
                         extensions: FakeExtensions()).scan()
    }

    // MARK: - Preferences

    private func preferences(locked: Bool) -> StaleItem? {
        var files = FakeFiles()
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
        var files = FakeFiles()
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
}
