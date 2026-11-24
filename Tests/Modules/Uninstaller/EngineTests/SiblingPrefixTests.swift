import XCTest
@testable import Module_Uninstaller_Engine

/// Uninstalling one app must not offer another installed app's data.
///
/// A bundle id is a prefix of its vendor's next product: `com.acme.tool*`
/// matches `com.acme.toolPro`, a different app, and a glob hit arrives ticked.
///
/// These assert which paths the scan claims, never how many.
final class SiblingPrefixTests: XCTestCase {
    private let lib = "/Users/x/Library"

    private func scan(_ id: String, installed: Set<String>, entries: [String: Int]) async throws -> ScanResult {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: FakeApps.installed(installed),
                                       fs: FakeFS(existing: entries, globbing: true),
                                       trash: NoTrash(), running: NoRunning())
        return await engine.scan(bundleID: id, appName: "Tool")
    }

    /// The trap. `com.acme.toolPro` is installed and has a container of its own;
    /// removing `com.acme.tool` must not reach into it.
    func test_uninstalling_an_app_does_not_claim_a_longer_named_siblings_data() async throws {
        let mine = "\(lib)/Containers/com.acme.tool"
        let theirs = "\(lib)/Containers/com.acme.toolPro"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: [mine: 10, theirs: 9_000_000])
        XCTAssertFalse(result.leftovers.map(\.path).contains(theirs),
                       "the scan claimed an installed sibling's container: \(result.leftovers.map(\.path))")
        XCTAssertEqual(result.leftovers.map(\.path), [mine],
                       "and it still claims its own")
    }

    /// The same shape in every folder a glob reaches.
    func test_no_glob_folder_lets_a_longer_named_sibling_through() async throws {
        var entries: [String: Int] = [:]
        var theirs: [String] = []
        for dir in ["Caches", "Containers", "Application Scripts"] {
            entries["\(lib)/\(dir)/com.acme.tool"] = 1
            let p = "\(lib)/\(dir)/com.acme.toolPro"
            entries[p] = 1
            theirs.append(p)
        }
        entries["\(lib)/LaunchAgents/com.acme.toolPro.plist"] = 1
        theirs.append("\(lib)/LaunchAgents/com.acme.toolPro.plist")
        entries["\(lib)/Group Containers/group.com.acme.toolPro"] = 1
        theirs.append("\(lib)/Group Containers/group.com.acme.toolPro")

        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: entries)
        let claimed = Set(result.leftovers.map(\.path))
        for path in theirs {
            XCTAssertFalse(claimed.contains(path), "claimed \(path)")
        }
    }

    /// A namespaced app of the same vendor (`com.acme.tool.staging`) passes the
    /// separator rule; it is installed, so it is not this app's leftover.
    func test_an_installed_namespaced_app_is_not_this_apps_leftover() async throws {
        let mine = "\(lib)/Caches/com.acme.tool"
        let theirs = "\(lib)/Caches/com.acme.tool.staging"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.tool.staging"],
                                    entries: [mine: 1, theirs: 1])
        XCTAssertEqual(result.leftovers.map(\.path), [mine])
    }

    /// Positive control: a helper or extension container belonging to no
    /// installed app is still found, or refusing everything would pass.
    func test_helper_and_team_prefixed_containers_are_still_found() async throws {
        let entries = [
            "\(lib)/Caches/com.acme.tool": 1,
            "\(lib)/Caches/com.acme.tool.helper": 1,
            "\(lib)/Containers/com.acme.tool.packet-extension-mac": 1,
            "\(lib)/Group Containers/2XZUN9L63Z.com.acme.tool": 1,
            "\(lib)/LaunchAgents/com.acme.tool.updater.plist": 1,
        ]
        let result = try await scan("com.acme.tool", installed: ["com.acme.tool"], entries: entries)
        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(entries.keys))
    }

    /// A glob hit is not `matchedByName`, which `defaultSelection` ticks, so an
    /// unfiltered hit would be pre-selected, not merely listed.
    func test_nothing_belonging_to_an_installed_sibling_arrives_pre_ticked() async throws {
        let theirs = "\(lib)/Containers/com.acme.toolPro"
        let result = try await scan("com.acme.tool",
                                    installed: ["com.acme.tool", "com.acme.toolPro"],
                                    entries: ["\(lib)/Containers/com.acme.tool": 1, theirs: 1])
        let app = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                               path: "/Applications/Tool.app")
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)
        XCTAssertFalse(UninstallPlan.defaultSelection([group]).contains(theirs),
                       "pre-ticked an installed app's container")
    }
}
