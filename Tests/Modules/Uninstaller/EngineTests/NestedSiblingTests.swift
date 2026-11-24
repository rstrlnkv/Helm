import XCTest
@testable import Module_Uninstaller_Engine

/// The sibling test again, for the sibling the *directory listing* cannot see.
///
/// `SiblingPrefixTests` pins the rule that uninstalling `com.acme.tool` does
/// not claim `com.acme.tool.staging`'s data. Here the sibling is where
/// `installedBundleIDs()` cannot see it (nested in a bundle, or deeper than
/// two levels), so only LaunchServices refuses it; otherwise its container
/// would arrive on the review pre-ticked.
///
/// Assertions name paths, never counts: a count is satisfied by any two.
final class NestedSiblingTests: XCTestCase {
    private let lib = "/Users/x/Library"

    private func scan(_ id: String, topLevel: Set<String>, nested: Set<String>,
                      entries: [String: Int]) async throws -> ScanResult {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: FakeApps.installed(topLevel, nested: nested),
                                       fs: FakeFS(existing: entries, globbing: true),
                                       trash: NoTrash(), running: NoRunning())
        return await engine.scan(bundleID: id, appName: "Acrobat")
    }

    /// The shape `SiblingPrefixTests` already refuses, moved one folder down.
    ///
    /// `com.adobe.acrobat.reader` passes the separator rule; only "another
    /// installed app" stops it, and the listing does not hold it.
    func test_a_nested_installed_sibling_is_not_this_apps_leftover() async throws {
        let mine = "\(lib)/Containers/com.adobe.acrobat"
        let theirs = "\(lib)/Containers/com.adobe.acrobat.reader"

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: [mine: 10, theirs: 4_000_000])

        XCTAssertFalse(result.leftovers.map(\.path).contains(theirs),
                       "claimed an installed app's container because it lives one folder "
                       + "down: \(result.leftovers.map(\.path))")
        XCTAssertEqual(result.leftovers.map(\.path), [mine], "and it still claims its own")
    }

    /// Every glob folder: a filter that misses LaunchAgents is not a filter, and
    /// trashing one stops the neighbour's updater for good.
    func test_no_glob_folder_lets_a_nested_installed_sibling_through() async throws {
        var entries: [String: Int] = [:]
        var theirs: [String] = []
        for dir in ["Caches", "Containers", "Application Scripts"] {
            entries["\(lib)/\(dir)/com.adobe.acrobat"] = 1
            let path = "\(lib)/\(dir)/com.adobe.acrobat.reader"
            entries[path] = 1
            theirs.append(path)
        }
        for path in ["\(lib)/LaunchAgents/com.adobe.acrobat.reader.plist",
                     "\(lib)/Group Containers/group.com.adobe.acrobat.reader"] {
            entries[path] = 1
            theirs.append(path)
        }

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: entries)

        let claimed = Set(result.leftovers.map(\.path))
        for path in theirs { XCTAssertFalse(claimed.contains(path), "claimed \(path)") }
    }

    /// A glob hit is not `matchedByName`, which `defaultSelection` ticks, so the
    /// neighbour's data would be selected, not merely listed.
    func test_a_nested_siblings_data_does_not_arrive_pre_ticked() async throws {
        let theirs = "\(lib)/Containers/com.adobe.acrobat.reader"
        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: ["com.adobe.acrobat.reader"],
                                    entries: ["\(lib)/Containers/com.adobe.acrobat": 1,
                                              theirs: 1])
        let app = InstalledApp(name: "Acrobat", bundleID: "com.adobe.acrobat",
                               path: "/Applications/Acrobat.app")
        let group = UninstallGroup(app: app, leftovers: result.leftovers, running: false)

        XCTAssertFalse(UninstallPlan.defaultSelection([group]).contains(theirs),
                       "pre-ticked a nested installed app's container")
    }

    /// The control: a helper container belonging to no installed app is still
    /// found, or refusing everything would pass the tests above.
    func test_a_helper_belonging_to_nobody_is_still_found() async throws {
        let entries = [
            "\(lib)/Caches/com.adobe.acrobat": 1,
            "\(lib)/Caches/com.adobe.acrobat.helper": 1,
            "\(lib)/Containers/com.adobe.acrobat.packet-extension-mac": 1,
        ]

        let result = try await scan("com.adobe.acrobat",
                                    topLevel: ["com.adobe.acrobat"],
                                    nested: [],
                                    entries: entries)

        XCTAssertEqual(Set(result.leftovers.map(\.path)), Set(entries.keys))
    }
}
