import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

private struct FakeFiles: LeftoversFilePort {
    var writable = true
    func isWritable(_ url: URL) -> Bool { writable }

    var listing: [String: [String]] = [:]
    var existing: Set<String> = []
    var plists: [String: PlistData] = [:]
    func children(of url: URL) -> [URL] {
        (listing[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
    func exists(_ path: String) -> Bool { existing.contains(path) }
    func size(_ url: URL) -> Int { 100 }
    func readPlist(_ url: URL) -> PlistData? { plists[url.path] }
}

private struct FakeApps: InstalledAppsPort {
    let ids: Set<String>
    func installedBundleIDs() -> Set<String> { ids }
}

private struct FakeExtensions: ExtensionsPort {
    var installed: [SystemExtensionInfo] = []
    func installedExtensions() -> [SystemExtensionInfo] { installed }
    var disabled: Set<String> = []
    func disabledLabels() -> Set<String> { disabled }
    func setDisabled(_ disabled: Bool, label: String) {}
}

final class LeftoversScanTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    private func scanner(files: FakeFiles, installed: Set<String> = [],
                         extensions: FakeExtensions = FakeExtensions()) -> LeftoversScanner {
        LeftoversScanner(home: home, files: files,
                         apps: FakeApps(ids: installed), extensions: extensions)
    }

    // MARK: - Everything is listed; status says what it is

    /// The list shows what is running as well as what is left over, so the user
    /// can see the whole picture instead of a list they must take on trust.
    func testAgentsInUseAreListedAsInUse() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.live.vendor.agent.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.live.vendor.agent.plist"] = PlistData([
            "Label": "com.live.vendor.agent",
            "Program": "/usr/local/bin/live",
        ])
        files.existing = ["/usr/local/bin/live"]
        let items = scanner(files: files).scan()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].status, .inUse)
        XCTAssertFalse(items[0].removable)
    }

    func testAppleAndSystemItemsAreListedAsProtected() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/Preferences"] = ["com.apple.dock.plist"]
        let items = scanner(files: files).scan()
        XCTAssertEqual(items.map(\.status), [.protectedItem])
        XCTAssertFalse(items[0].removable)
    }

    func testOrphansAreTheOnlyRemovableOnes() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/Preferences"] = [
            "com.gone.vendor.app.plist", "com.acme.tool.plist", "com.apple.dock.plist",
        ]
        let items = scanner(files: files, installed: ["com.acme.tool"]).scan()
        XCTAssertEqual(items.filter(\.removable).map(\.identifier), ["com.gone.vendor.app"])
        XCTAssertEqual(Set(items.map(\.status)), [.orphaned, .inUse, .protectedItem])
    }

    func testFindsAnAgentWhoseAppIsGone() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.gone.vendor.agent.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.gone.vendor.agent.plist"] = PlistData([
            "Label": "com.gone.vendor.agent",
            "Program": "/Applications/Gone.app/Contents/MacOS/agent",
            "RunAtLoad": true,
        ])
        let items = scanner(files: files, installed: ["com.other.app"]).scan()
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.status, .orphaned)
        XCTAssertTrue(item.removable)
        XCTAssertEqual(item.kind, .launchAgent)
        XCTAssertEqual(item.identifier, "com.gone.vendor.agent")
        XCTAssertEqual(item.missingTarget, "/Applications/Gone.app/Contents/MacOS/agent")
        XCTAssertTrue(item.runAtLoad)
    }

    /// The job's target still exists — listed, but not as a leftover.
    func testKeepsAnAgentWhoseProgramIsPresent() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.live.vendor.agent.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.live.vendor.agent.plist"] = PlistData([
            "Label": "com.live.vendor.agent",
            "Program": "/usr/local/bin/live",
        ])
        files.existing = ["/usr/local/bin/live"]
        XCTAssertEqual(scanner(files: files).scan().filter(\.removable).count, 0)
    }

    func testFindsPreferencesOfUninstalledApps() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/Preferences"] = [
            "com.gone.vendor.app.plist",     // owner missing → offered
            "com.acme.tool.plist",           // still installed → kept
            "com.apple.dock.plist",          // Apple → never
            ".GlobalPreferences.plist",      // system → never
            "notes.txt",                     // not a plist → ignored
        ]
        let items = scanner(files: files, installed: ["com.acme.tool"]).scan()
        XCTAssertEqual(items.filter(\.removable).map(\.identifier), ["com.gone.vendor.app"])
        XCTAssertEqual(items.first?.kind, .preference)
    }

    /// An extension is only stale when its app is gone AND it is not activated.
    func testExtensionsOfMissingAppsAreOfferedUnlessStillActive() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/Preferences"] = []
        // Through the field the port actually answers with. `ids` was a
        // leftover of `activeExtensionIdentifiers`, deleted today, and the
        // fixture went on setting it — so the scan saw no extensions at all and
        // the rule below was asserted over an empty list.
        let active = FakeExtensions(installed: [
            SystemExtensionInfo(identifier: "com.gone.vendor.app.ext", teamID: "T",
                                name: "Ext", version: "1", state: "activated enabled",
                                enabled: true),
        ])
        var scannerFiles = files
        scannerFiles.listing["/Users/x/Library/LaunchAgents"] = []
        let items = scanner(files: scannerFiles, installed: [], extensions: active).scan()
        XCTAssertTrue(items.filter(\.removable).isEmpty, "an activated extension must not be offered")
    }

    // MARK: - System extensions

    /// The module is called "Login Items & Extensions", and system extensions
    /// were the one thing it never listed: they showed up only as a count on
    /// another page, with no names.
    func testInstalledExtensionsAreListed() {
        let extensions = FakeExtensions(installed: [
            SystemExtensionInfo(identifier: "com.acme.app.network", teamID: "T1",
                                name: "Acme Network", version: "1.0",
                                state: "activated enabled", enabled: true),
        ])
        let items = scanner(files: FakeFiles(), installed: ["com.acme.app"],
                            extensions: extensions).scan()
        let extensionItems = items.filter { $0.kind == .systemExtension }
        XCTAssertEqual(extensionItems.count, 1)
        XCTAssertEqual(extensionItems.first?.identifier, "com.acme.app.network")
    }

    /// An extension whose host app is installed is in use; one whose host is
    /// gone is a leftover the user may want to clear in System Settings.
    func testExtensionStatusFollowsItsHostApp() {
        let info = SystemExtensionInfo(identifier: "com.acme.app.network", teamID: "T1",
                                       name: "Acme Network", version: "1.0",
                                       state: "activated enabled", enabled: true)
        let live = scanner(files: FakeFiles(), installed: ["com.acme.app"],
                           extensions: FakeExtensions(installed: [info])).scan()
        XCTAssertEqual(live.first { $0.kind == .systemExtension }?.status, .inUse)

        let orphan = scanner(files: FakeFiles(), installed: [],
                             extensions: FakeExtensions(installed: [info])).scan()
        XCTAssertEqual(orphan.first { $0.kind == .systemExtension }?.status, .orphaned)
    }

    /// Helm cannot delete an extension by moving a file — that is done in
    /// System Settings — so it must never offer a checkbox for one.
    func testExtensionsAreNeverSelectable() {
        let info = SystemExtensionInfo(identifier: "com.acme.app.network", teamID: "T1",
                                       name: "Acme Network", version: "1.0",
                                       state: "activated enabled", enabled: true)
        let items = scanner(files: FakeFiles(), installed: [],
                            extensions: FakeExtensions(installed: [info])).scan()
        let ext = items.first { $0.kind == .systemExtension }
        XCTAssertEqual(ext?.removable, false)
    }
}
