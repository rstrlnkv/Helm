import XCTest
@testable import Module_Uninstaller_Engine

/// `LeftoverMatcher` pastes a bundle id or a display name onto a shared
/// `~/Library` folder, and the review arrives with the id's candidates ticked.
/// These pin two invariants: a candidate is strictly inside its kind folder,
/// and a glob is anchored to something the app owns. The names come from
/// free-form plist strings, so empty and hostile ones are real inputs.
final class LeftoverMatcherHostileNamesTests: XCTestCase {
    private let lib = URL(fileURLWithPath: "/Users/x/Library")

    private func candidates(id: String, name: String) -> [LeftoverMatcher.Candidate] {
        LeftoverMatcher.candidates(bundleID: id, appName: name, library: lib)
    }

    /// `URL.appendingPathComponent("")` returns the parent unchanged, so an empty
    /// display name would claim the whole shared folder as a leftover.
    func testEmptyAppNameNeverTargetsAWholeLibraryFolder() {
        let paths = candidates(id: "com.acme.tool", name: "").map(\.url.path)
        XCTAssertFalse(paths.contains("/Users/x/Library/Application Support"),
                       "an empty display name claimed the shared folder: \(paths)")
        XCTAssertFalse(paths.contains("/Users/x/Library/Logs"),
                       "an empty display name claimed the shared folder: \(paths)")
    }

    /// The structural form, so a new candidate line cannot reintroduce it: every
    /// candidate is at least two components below `~/Library`, the kind folder
    /// and the app's own entry. One component below is a shared folder.
    func testEveryCandidateSitsAtLeastTwoLevelsBelowTheLibrary() {
        for (id, name) in [("com.acme.tool", ""), ("", "Tool"), ("", ""),
                           ("com.acme.tool", "Tool")] {
            for c in candidates(id: id, name: name) {
                let relative = c.url.path.dropFirst(lib.path.count)
                let parts = relative.split(separator: "/")
                XCTAssertGreaterThanOrEqual(
                    parts.count, 2,
                    "id=\(id.debugDescription) name=\(name.debugDescription) produced \(c.url.path)")
            }
        }
    }

    /// A name carrying a path separator or `..` would escape its folder, and
    /// `FileManager` resolves it before both `fileExists` and `trashItem`.
    func testNoCandidateWalksOutOfTheLibrary() {
        for name in ["../../..", "..", "../Preferences"] {
            for c in candidates(id: "com.acme.tool", name: name) {
                XCTAssertFalse(c.url.pathComponents.contains(".."),
                               "name \(name.debugDescription) produced \(c.url.path)")
                XCTAssertTrue(c.url.standardizedFileURL.path.hasPrefix(lib.path + "/"),
                              "name \(name.debugDescription) escaped to \(c.url.standardizedFileURL.path)")
            }
        }
    }

    /// With an empty id, `"\(id)*"` and `"*\(id)*"` collapse to `*` and `**`,
    /// matching every sibling, and `*.plist` every LaunchAgent.
    func testEmptyBundleIdNeverProducesAMatchEverythingGlob() {
        let strangers = ["com.unrelated.app", "com.unrelated.app.plist", "Stranger"]
        for c in candidates(id: "", name: "Tool") where c.isGlob {
            let pattern = c.url.lastPathComponent
            for stranger in strangers {
                XCTAssertFalse(GlobMatch.matches(stranger, pattern: pattern),
                               "empty id produced pattern \(pattern.debugDescription), which swallows \(stranger)")
            }
        }
    }

    /// Positive control: a well-formed app still gets scoped candidates, so a
    /// guard that returns nothing cannot pass the tests above by emptiness.
    func testWellFormedInputStillProducesScopedCandidates() {
        let all = candidates(id: "com.acme.tool", name: "Tool")
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.contains { $0.isGlob })
        for c in all where c.isGlob {
            XCTAssertFalse(GlobMatch.matches("com.unrelated.app", pattern: c.url.lastPathComponent))
        }
        for c in all {
            XCTAssertTrue(c.url.path.hasPrefix(lib.path + "/"))
            XCTAssertFalse(c.url.pathComponents.contains(".."))
        }
    }
}
