import XCTest
@testable import Module_Leftovers_Engine

private struct FakeFiles: LeftoversFilePort {
    var listing: [String: [String]] = [:]
    var existing: Set<String> = []
    var plists: [String: PlistData] = [:]
    func children(of url: URL) -> [URL] {
        (listing[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
    func exists(_ path: String) -> Bool { existing.contains(path) }
    func size(_ url: URL) -> Int { 100 }
    func readPlist(_ url: URL) -> PlistData? { plists[url.path] }
    func trash(_ url: URL) -> TrashResult { .success }
}

private struct FakeApps: InstalledAppsPort {
    let ids: Set<String>
    func installedBundleIDs() -> Set<String> { ids }
}

private struct FakeExtensions: ExtensionsPort {
    var ids: Set<String> = []
    func activeExtensionIdentifiers() -> Set<String> { ids }
}

final class LeftoversScanTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    private func scanner(files: FakeFiles, installed: Set<String> = [],
                         extensions: FakeExtensions = FakeExtensions()) -> LeftoversScanner {
        LeftoversScanner(home: home, files: files,
                         apps: FakeApps(ids: installed), extensions: extensions)
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
        XCTAssertEqual(item.kind, .launchAgent)
        XCTAssertEqual(item.identifier, "com.gone.vendor.agent")
        XCTAssertEqual(item.missingTarget, "/Applications/Gone.app/Contents/MacOS/agent")
        XCTAssertTrue(item.runAtLoad)
    }

    /// The job's target still exists — nothing stale about it.
    func testKeepsAnAgentWhoseProgramIsPresent() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.live.vendor.agent.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.live.vendor.agent.plist"] = PlistData([
            "Label": "com.live.vendor.agent",
            "Program": "/usr/local/bin/live",
        ])
        files.existing = ["/usr/local/bin/live"]
        XCTAssertTrue(scanner(files: files).scan().isEmpty)
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
        XCTAssertEqual(items.map(\.identifier), ["com.gone.vendor.app"])
        XCTAssertEqual(items.first?.kind, .preference)
    }

    /// An extension is only stale when its app is gone AND it is not activated.
    func testExtensionsOfMissingAppsAreOfferedUnlessStillActive() {
        var files = FakeFiles()
        files.listing["/Users/x/Library/Preferences"] = []
        let active = FakeExtensions(ids: ["com.gone.vendor.app.ext"])
        var scannerFiles = files
        scannerFiles.listing["/Users/x/Library/LaunchAgents"] = []
        let items = scanner(files: scannerFiles, installed: [], extensions: active).scan()
        XCTAssertTrue(items.isEmpty, "an activated extension must not be offered")
    }
}
